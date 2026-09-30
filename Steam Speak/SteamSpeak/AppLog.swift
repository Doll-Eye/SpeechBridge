import Foundation

extension Timer {
    /// A scheduled timer added in the common run-loop modes. `Timer.scheduledTimer` uses
    /// the default mode only, and the main run loop leaves that mode whenever AppKit is
    /// tracking a menu — during which every timer in that mode silently stops. The poll
    /// that finds Big Picture must keep running while the menu bar menu is open.
    @discardableResult
    static func common(_ interval: TimeInterval, repeats: Bool,
                       _ block: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

/// Plain-text logging to ~/Library/Application Support/Steam Speak/logs, so behaviour can
/// be inspected without watching the screen. Every diagnosis in the project this came from
/// was made from the log; it is the primary instrument.
final class AppLog {
    static let shared = AppLog()
    private var handle: FileHandle?
    private(set) var url: URL?
    private let queue = DispatchQueue(label: "steamspeak.log")

    static var directory: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support"))
            .appendingPathComponent("Steam Speak/logs", isDirectory: true)
    }

    private init() {
        let directory = Self.directory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let fileURL = directory.appendingPathComponent("steamspeak-\(formatter.string(from: Date())).log")
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            handle = try FileHandle(forWritingTo: fileURL)
            url = fileURL
            // A week of logs is plenty; unpruned they grow forever.
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            if let old = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) {
                for file in old where file.pathExtension == "log" {
                    if let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                       modified < cutoff {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            }
        } catch {
            handle = nil
        }
    }

    func write(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async { [weak self] in
            if let data = line.data(using: .utf8) { self?.handle?.write(data) }
        }
    }
}

func log(_ message: String) { AppLog.shared.write(message) }
