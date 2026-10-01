import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// The default speakers and microphone, through Core Audio — the same controls the volume keys use.
@MainActor
enum SystemAudio {
    /// One press of the volume keys.
    static let step: Float = 1.0 / 16

    static func volume(input: Bool = false) -> Float? {
        guard let device = defaultDevice(input: input) else { return nil }
        var address = volumeAddress(input: input)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    @discardableResult
    static func setVolume(_ value: Float, input: Bool = false) -> Bool {
        guard let device = defaultDevice(input: input) else { return false }
        var address = volumeAddress(input: input)
        var level = Float32(min(max(value, 0), 1))
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level) == noErr
    }

    static func isMuted(input: Bool = false) -> Bool? {
        guard let device = defaultDevice(input: input) else { return nil }
        var address = muteAddress(input: input)
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr ? muted != 0 : nil
    }

    @discardableResult
    static func setMuted(_ muted: Bool, input: Bool = false) -> Bool {
        guard let device = defaultDevice(input: input) else { return false }
        var address = muteAddress(input: input)
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    // MARK: Commands

    static func toggleMute() {
        setMuted(!(isMuted() ?? false))
    }

    static func changeVolume(by delta: Float) {
        let next = (volume() ?? 0.5) + delta
        if delta > 0, isMuted() == true {
            setMuted(false)
        }
        setVolume(next)
    }

    static func setPreset(_ value: Float) {
        setVolume(value)
        setMuted(value == 0)
    }

    private static let micLevelKey = "microphoneLevelBeforeMute"

    /// Mutes the microphone, or turns its level to zero when it has no mute switch; again to undo.
    static func toggleMicrophone() {
        if let muted = isMuted(input: true), setMuted(!muted, input: true) {
            return
        }
        let level = volume(input: true) ?? 0
        if level > 0 {
            UserDefaults.standard.set(level, forKey: micLevelKey)
            setVolume(0, input: true)
        } else {
            let saved = UserDefaults.standard.object(forKey: micLevelKey) as? Float ?? 0.75
            setVolume(saved, input: true)
        }
    }

    // MARK: Media keys

    /// NX_KEYTYPE_PLAY, NX_KEYTYPE_NEXT, NX_KEYTYPE_PREVIOUS from IOKit's ev_keymap.h.
    enum MediaKey: Int {
        case playPause = 16
        case next = 17
        case previous = 18
    }

    /// Presses a media key, so whatever's playing (Music, Spotify, a browser tab) responds.
    static func press(_ key: MediaKey) {
        for isDown in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: isDown ? 0xA00 : 0xB00)
            let data1 = (key.rawValue << 16) | ((isDown ? 0xA : 0xB) << 8)
            NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1
            )?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Plumbing

    private static func defaultDevice(input: Bool) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func volumeAddress(input: Bool) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func muteAddress(input: Bool) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
