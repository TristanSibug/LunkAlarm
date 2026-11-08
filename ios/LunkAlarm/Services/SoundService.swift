import AVFoundation
import Foundation
import Observation

@MainActor @Observable
final class SoundService {
    private var player: AVAudioPlayer?
    private var previewTask: Task<Void, Never>?
    private(set) var previewing = false
    static var soundsDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Sounds")
    }
    static func url(filename: String) -> URL? {
        let imported = soundsDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: imported.path) { return imported }
        return Bundle.main.url(forResource: filename, withExtension: nil)
    }
    func play(filename: String, preview: Bool) throws {
        stop()
        guard let url = Self.url(filename: filename) else { throw NativeAlarmError.soundUnavailable }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true)
        do {
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.numberOfLoops = -1
            guard audio.prepareToPlay(), audio.play() else { throw NativeAlarmError.soundUnavailable }
            player = audio
            previewing = preview
            if preview {
                previewTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(6))
                    guard !Task.isCancelled else { return }
                    self?.stop()
                }
            }
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }
    func stop() {
        previewTask?.cancel(); previewTask = nil
        player?.stop(); player = nil; previewing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // AlarmKit accepts named PCM files in Library/Sounds. Imported files are converted
    // once to mono 44.1 kHz WAV and retain a unique name for every alarm snapshot.
    static func importSound(from source: URL) throws -> ImportedSound {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 2 * 1024 * 1024 else { throw SoundImportError.tooLarge }
        let input = try AVAudioFile(forReading: source)
        let duration = Double(input.length) / input.processingFormat.sampleRate
        guard duration > 0, duration < 30 else { throw SoundImportError.tooLong }
        try FileManager.default.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
        let id = "custom-" + UUID().uuidString
        let destination = soundsDirectory.appendingPathComponent(id + ".wav")
        do {
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false)!
            guard let converter = AVAudioConverter(from: input.processingFormat, to: format),
                  let original = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(input.length)),
                  let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(duration * 44_100)) + 1024)
            else { throw SoundImportError.unsupported }
            try input.read(into: original)
            var supplied = false
            var conversionError: NSError?
            let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
                if supplied { outStatus.pointee = .endOfStream; return nil }
                supplied = true; outStatus.pointee = .haveData; return original
            }
            if let conversionError { throw conversionError }
            guard status != .error, converted.frameLength > 0 else { throw SoundImportError.unsupported }
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ]
            let output = try AVAudioFile(forWriting: destination, settings: outputSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try output.write(from: converted)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
            return ImportedSound(id: id, name: source.deletingPathExtension().lastPathComponent, filename: destination.lastPathComponent)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}

enum SoundImportError: LocalizedError {
    case tooLarge, tooLong, unsupported
    var errorDescription: String? {
        switch self {
        case .tooLarge: "Choose an audio file smaller than 2 MB."
        case .tooLong: "Choose an audio clip shorter than 30 seconds for the iOS alarm sound."
        case .unsupported: "This audio format could not be imported. Try a WAV, MP3, or M4A file."
        }
    }
}
