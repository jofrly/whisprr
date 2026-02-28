import AVFoundation
import Foundation

final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    static let recordingInterruptedNotification = Notification.Name("AudioRecorder.recordingInterrupted")

    private var recorder: AVAudioRecorder?
    private var isRecording = false
    private var tempFileURL: URL?

    func startRecording() -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisprr_\(UUID().uuidString).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            guard recorder.record() else {
                print("[AudioRecorder] record() returned false")
                return false
            }
            self.recorder = recorder
            self.tempFileURL = url
            isRecording = true
            print("[AudioRecorder] Recording started")
            return true
        } catch {
            print("[AudioRecorder] Failed to create recorder: \(error)")
            return false
        }
    }

    func stopRecording() -> URL? {
        guard isRecording, let recorder = recorder else { return nil }

        recorder.stop()
        self.recorder = nil
        isRecording = false

        guard let url = tempFileURL else { return nil }
        tempFileURL = nil

        // Verify the file exists and has content
        guard FileManager.default.fileExists(atPath: url.path),
              (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64 ?? 0 > 44 else {
            print("[AudioRecorder] No audio data recorded")
            return nil
        }

        return url
    }

    static func requestPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    // MARK: - AVAudioRecorderDelegate

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag && isRecording {
            print("[AudioRecorder] Recording finished unsuccessfully")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.recordingInterruptedNotification, object: self)
            }
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("[AudioRecorder] Encode error: \(error?.localizedDescription ?? "unknown")")
        if isRecording {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.recordingInterruptedNotification, object: self)
            }
        }
    }
}
