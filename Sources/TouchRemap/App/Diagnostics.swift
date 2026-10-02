import Foundation

/// Optional log of raw touch reports, for troubleshooting panels: ~/Library/Logs/TouchRemap/diagnostics.log
enum Diagnostics {
    static let defaultsKey = "diagnosticsLogging"
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/TouchRemap/diagnostics.log")
    }

    /// Set by --dump: print to stdout instead of the log file.
    static var echoToStdout = false

    static var isEnabled: Bool { echoToStdout || UserDefaults.standard.bool(forKey: defaultsKey) }

    private static var handle: FileHandle?
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ message: String) {
        guard isEnabled else { return }
        if echoToStdout { print(message); fflush(stdout); return }
        if handle == nil {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: fileURL)
            _ = try? handle?.seekToEnd()
        }
        handle?.write(Data("\(formatter.string(from: Date())) \(message)\n".utf8))
    }
}
