import Foundation

enum Shell {
    struct Result {
        var status: Int32
        var stdout: String
        var stderr: String
        var ok: Bool { status == 0 }
    }

    /// POSIX single-quote escaping.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs a process synchronously. Never call on the main thread.
    static func run(_ executable: String, _ args: [String], environment: [String: String]? = nil,
                    timeout: TimeInterval = 20) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        if let environment { p.environment = environment }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            return Result(status: -1, stdout: "", stderr: error.localizedDescription)
        }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.wait()
        p.waitUntilExit()
        killer.cancel()
        return Result(status: p.terminationStatus,
                      stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errData, as: UTF8.self))
    }
}

/// User preferences shared by the GUI (via @AppStorage) and the headless launcher mode.
enum Prefs {
    static let terminalKey = "terminal"
    static let customTemplateKey = "customTerminalTemplate"
    static let claudePathKey = "claudePathOverride"
    static let desktopAppKey = "desktopAppOverride"
    static let commandsDirKey = "commandsDir"
    static let showMenuBarKey = "showMenuBarExtra"

    static let defaultCommandsDir = "~/.local/bin"
    static let defaultCustomTemplate = "open -na Ghostty --args -e {script}"

    static var terminal: TerminalChoice {
        TerminalChoice(rawValue: UserDefaults.standard.string(forKey: terminalKey) ?? "") ?? .terminal
    }
    static var customTemplate: String {
        let v = UserDefaults.standard.string(forKey: customTemplateKey) ?? ""
        return v.isEmpty ? defaultCustomTemplate : v
    }
    static var claudePathOverride: String { UserDefaults.standard.string(forKey: claudePathKey) ?? "" }
    static var desktopAppOverride: String { UserDefaults.standard.string(forKey: desktopAppKey) ?? "" }
    static var commandsDir: URL {
        let v = UserDefaults.standard.string(forKey: commandsDirKey) ?? ""
        return URL(fileURLWithPath: Paths.expand(v.isEmpty ? defaultCommandsDir : v), isDirectory: true)
    }
}

enum TerminalChoice: String, CaseIterable, Identifiable {
    case terminal, iterm, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm: return "iTerm2"
        case .custom: return "Custom command"
        }
    }
}
