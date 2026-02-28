import AVFoundation
import CoreAudio
import Foundation

final class AudioRecorder {
    static let recordingInterruptedNotification = Notification.Name("AudioRecorder.recordingInterrupted")

    private var engine: AVAudioEngine?
    private var audioData = Data()
    private var isRecording = false
    private var ignoreConfigChange = false

    private let targetSampleRate: Double = 16000
    private let targetChannels: AVAudioChannelCount = 1
    private let targetBitDepth: UInt32 = 16

    func startRecording(deviceID: AudioDeviceID? = nil) -> Bool {
        let engine = AVAudioEngine()

        // Set specific input device if requested
        if let deviceID = deviceID {
            let inputNode = engine.inputNode
            guard let audioUnit = inputNode.audioUnit else {
                print("Failed to get audio unit from input node")
                return false
            }
            var devID = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &devID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                print("Failed to set input device: \(status)")
                return false
            }
        }

        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            print("Invalid hardware format")
            return false
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else {
            print("Failed to create target format")
            return false
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            print("Failed to create audio converter")
            return false
        }

        audioData = Data()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.convert(buffer: buffer, converter: converter, targetFormat: targetFormat)
        }

        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
            inputNode.removeTap(onBus: 0)
            return false
        }

        self.engine = engine
        isRecording = true

        // Ignore config-change notifications briefly after start — setting a
        // device via AudioUnitSetProperty triggers an immediate
        // AVAudioEngineConfigurationChange that is not an actual disconnection.
        ignoreConfigChange = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.ignoreConfigChange = false
        }

        return true
    }

    func stopRecording() -> URL? {
        guard isRecording, let engine = engine else { return nil }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: engine)
        self.engine = nil
        isRecording = false

        guard !audioData.isEmpty else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisprr_\(UUID().uuidString).wav")

        do {
            let wavData = buildWAV(pcmData: audioData)
            try wavData.write(to: url)
            return url
        } catch {
            print("Failed to write WAV file: \(error)")
            return nil
        }
    }

    static func requestPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    // MARK: - Private

    private func convert(buffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        let frameCapacity = AVAudioFrameCount(
            ceil(Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate)
        )
        guard frameCapacity > 0,
              let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }

        var error: NSError?
        var consumed = false
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            print("Audio conversion error: \(error)")
            return
        }

        guard convertedBuffer.frameLength > 0 else { return }

        let byteCount = Int(convertedBuffer.frameLength) * Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
        if let int16Data = convertedBuffer.int16ChannelData {
            let ptr = UnsafeRawPointer(int16Data.pointee)
            audioData.append(ptr.assumingMemoryBound(to: UInt8.self), count: byteCount)
        }
    }

    private func buildWAV(pcmData: Data) -> Data {
        var data = Data()

        let dataSize = UInt32(pcmData.count)
        let sampleRate = UInt32(targetSampleRate)
        let channels = UInt16(targetChannels)
        let bitsPerSample = UInt16(targetBitDepth)
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        var chunkSize = 36 + dataSize
        data.append(Data(bytes: &chunkSize, count: 4))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt subchunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        var subchunk1Size: UInt32 = 16
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = 1 // PCM
        data.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = channels
        data.append(Data(bytes: &numChannels, count: 2))
        var sr = sampleRate
        data.append(Data(bytes: &sr, count: 4))
        var br = byteRate
        data.append(Data(bytes: &br, count: 4))
        var ba = blockAlign
        data.append(Data(bytes: &ba, count: 2))
        var bps = bitsPerSample
        data.append(Data(bytes: &bps, count: 2))

        // data subchunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        var ds = dataSize
        data.append(Data(bytes: &ds, count: 4))
        data.append(pcmData)

        return data
    }

    @objc private func handleConfigChange(_ notification: Notification) {
        guard isRecording, !ignoreConfigChange else { return }
        print("Audio engine configuration changed during recording — stopping")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.recordingInterruptedNotification, object: self)
        }
    }
}
