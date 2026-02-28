import AVFoundation
import CoreAudio
import Foundation

struct AudioInputDevice {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isDefault: Bool
}

final class AudioDeviceManager {
    static let devicesDidChangeNotification = Notification.Name("AudioDeviceManager.devicesDidChange")

    private let defaultsKey = "selected_audio_input_uid"
    private var listenerBlocks: [AudioObjectPropertyListenerBlock] = []

    func inputDevices() -> [AudioInputDevice] {
        let defaultID = defaultInputDeviceID()

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize) == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        var devices: [AudioInputDevice] = []
        for id in deviceIDs {
            guard hasInputChannels(deviceID: id),
                  let uid = deviceUID(deviceID: id),
                  let name = deviceName(deviceID: id) else { continue }
            devices.append(AudioInputDevice(id: id, uid: uid, name: name, isDefault: id == defaultID))
        }
        return devices
    }

    func selectedDeviceID() -> AudioDeviceID? {
        guard let uid = UserDefaults.standard.string(forKey: defaultsKey) else {
            return nil // system default
        }
        return inputDevices().first(where: { $0.uid == uid })?.id
    }

    func selectedUID() -> String? {
        UserDefaults.standard.string(forKey: defaultsKey)
    }

    func selectDevice(uid: String?) {
        UserDefaults.standard.set(uid, forKey: defaultsKey)
    }

    func startObserving() {
        let queue = DispatchQueue.main

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let devicesBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.postDevicesChanged()
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, queue, devicesBlock)
        listenerBlocks.append(devicesBlock)

        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.postDevicesChanged()
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, queue, defaultBlock)
        listenerBlocks.append(defaultBlock)
    }

    // MARK: - Private

    private func postDevicesChanged() {
        NotificationCenter.default.post(name: Self.devicesDidChangeNotification, object: self)
    }

    private func defaultInputDeviceID() -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, bufferListPointer) == noErr else {
            return false
        }
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private func deviceUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &cfUID) == noErr,
              let uid = cfUID?.takeUnretainedValue() else {
            return nil
        }
        return uid as String
    }

    private func deviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &size, &cfName) == noErr,
              let name = cfName?.takeUnretainedValue() else {
            return nil
        }
        return name as String
    }
}
