import AudioToolbox
import CoreAudio
import StudioCore

@MainActor final class CoreAudioVolume: VolumeController {
  private func device() throws -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout.size(ofValue: id))
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr, id != 0
    else { throw ActionError.unavailable("No default audio output device.") }
    return id
  }
  var outputName: String {
    guard let id = try? device() else { return "No audio output" }
    var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout.size(ofValue: name))
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
          let name else { return "Default output" }
    return name.takeRetainedValue() as String
  }
  private func writableProperty(_ id: AudioDeviceID) throws -> AudioObjectPropertyAddress {
    for selector in [
      kAudioDevicePropertyVolumeScalar, kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
    ] {
      var address = AudioObjectPropertyAddress(
        mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
      var writable: DarwinBoolean = false
      if AudioObjectHasProperty(id, &address),
        AudioObjectIsPropertySettable(id, &address, &writable) == noErr, writable.boolValue
      {
        return address
      }
    }
    throw ActionError.unavailable(
      "This output has no writable system volume. Use its hardware controls or select another output in Sound settings."
    )
  }
  func read() throws -> Double {
    let id = try device()
    var address = try writableProperty(id)
    var value = Float32(0)
    var size = UInt32(MemoryLayout<Float32>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, value.isFinite
    else { throw ActionError.unavailable("Could not read output volume.") }
    return Double(value)
  }
  func write(_ value: Double) throws {
    guard value.isFinite else { throw ActionError.invalid }
    let id = try device()
    var address = try writableProperty(id)
    var scalar = Float32(min(1, max(0, value)))
    guard
      AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar)
        == noErr
    else { throw ActionError.unavailable("Could not change output volume.") }
  }
}
