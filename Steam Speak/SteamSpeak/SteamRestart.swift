import AppKit
import Foundation

/// A Steam client this Mac can read. Two kinds exist: the native Mac client, and the Windows
/// client inside a CrossOver bottle — added 28 September 2026 for Diablo IV, whose screen reader
/// exists only on Windows. Wine shares the Mac's loopback, so a bottle's Steam puts its DevTools
/// on the same 127.0.0.1:8080 and the reader needs no other change: only the switch file lives
/// somewhere else (the Windows client reads it from its install root, next to steam.exe), and
/// restarting is a different verb. Measured the same day: the bottle's Steam ignores
/// `-shutdown` and SIGTERM, so a restart there is a forced quit and a relaunch through
/// CrossOver's own app — launching from a shell gave it a Wine server that could not reach the
/// network, and Steam died three minutes in every time.
enum SteamInstall {
    case mac
    case bottle(name: String, steamExe: URL)

    static let crossOverBundle = "com.codeweavers.CrossOver"

    /// Found by bisection on 17 September 2026: an empty `.cef-enable-remote-debugging` at the
    /// Mac client's root did nothing, and the same file in the client's own directory brought
    /// the port up in two seconds through the ordinary bootstrapper.
    private static let macSwitchFile = URL(fileURLWithPath: NSHomeDirectory()
        + "/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/.cef-enable-remote-debugging")

    private static let bottlesDirectory = URL(fileURLWithPath: NSHomeDirectory()
        + "/Library/Application Support/CrossOver/Bottles", isDirectory: true)

    var switchFile: URL {
        switch self {
        case .mac: return Self.macSwitchFile
        case .bottle(_, let steamExe): return steamExe.deletingLastPathComponent().appendingPathComponent(".cef-enable-remote-debugging")
        }
    }

    var name: String {
        switch self {
        case .mac: return "Steam"
        case .bottle(let name, _): return "Steam in the \(name) bottle"
        }
    }

    /// Every install on this Mac, native first. A bottle counts when it holds a steam.exe.
    static var all: [SteamInstall] {
        var found: [SteamInstall] = []
        if FileManager.default.fileExists(atPath: macSwitchFile.deletingLastPathComponent().path) {
            found.append(.mac)
        }
        let bottles = (try? FileManager.default.contentsOfDirectory(at: bottlesDirectory, includingPropertiesForKeys: nil)) ?? []
        for bottle in bottles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let exe = bottle.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe")
            if FileManager.default.fileExists(atPath: exe.path) {
                found.append(.bottle(name: bottle.lastPathComponent, steamExe: exe))
            }
        }
        return found
    }

    /// True if the file is there (or was just created).
    @discardableResult
    func ensureSwitchFile() -> Bool {
        if FileManager.default.fileExists(atPath: switchFile.path) { return true }
        let made = FileManager.default.createFile(atPath: switchFile.path, contents: Data())
        log("Reader: \(made ? "created" : "could not create") the debugging switch file for \(name) — it will open its port next time it starts.")
        return made
    }

    /// The Mac client's processes, or Wine's steam.exe (which macOS lists as an application
    /// named after the executable).
    static func isSteamProcess(_ app: NSRunningApplication) -> Bool {
        let path = (app.executableURL?.path ?? "").lowercased()
        if path.hasSuffix("/steam_osx") || app.bundleIdentifier == "com.valvesoftware.steam" || app.localizedName == "Steam Helper" {
            return true
        }
        return (app.localizedName ?? "").lowercased() == "steam.exe"
    }

    /// Which install a restart should act on: the one that is running, else the first found.
    static var toRestart: SteamInstall? {
        let installs = all
        let running = NSWorkspace.shared.runningApplications.filter(isSteamProcess)
        if running.contains(where: { ($0.localizedName ?? "").lowercased() == "steam.exe" }),
           let bottle = installs.first(where: { if case .bottle = $0 { return true } else { return false } }) {
            return bottle
        }
        if running.contains(where: { $0.bundleIdentifier == "com.valvesoftware.steam" || ($0.executableURL?.path ?? "").hasSuffix("/steam_osx") }),
           installs.contains(where: { if case .mac = $0 { return true } else { return false } }) {
            return .mac
        }
        return installs.first
    }
}

enum SteamRestart {

    /// Quits Steam and starts it again with the port enabled. Calls back with a sentence to say.
    static func run(then finished: @escaping (String) -> Void) {
        guard let install = SteamInstall.toRestart else {
            finished("Steam does not seem to be installed.")
            return
        }
        install.ensureSwitchFile()
        switch install {
        case .mac: restartMac(then: finished)
        case .bottle(let name, let steamExe): restartBottle(named: name, steamExe: steamExe, then: finished)
        }
    }

    private static func restartMac(then finished: @escaping (String) -> Void) {
        // Wherever it is installed — Launch Services knows; /Applications is the fallback.
        let location = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.valvesoftware.steam")
            ?? URL(fileURLWithPath: "/Applications/Steam.app")
        guard FileManager.default.fileExists(atPath: location.path) else {
            finished("Steam does not seem to be installed.")
            return
        }

        let running = NSWorkspace.shared.runningApplications.first { app in
            let path = (app.executableURL?.path ?? "").lowercased()
            return path.hasSuffix("/steam_osx") || (app.bundleIdentifier ?? "") == "com.valvesoftware.steam"
        }
        running?.terminate()
        log("Steam restart: asked \(running == nil ? "nothing" : "Steam") to quit; relaunching through the bootstrapper.")
        finished(running == nil ? "Starting Steam." : "Restarting Steam. It takes a few seconds.")

        // Long enough for Steam to finish shutting down. It is a big client and it saves as it
        // goes; starting a second copy on top of a dying one is how you get two.
        let delay: TimeInterval = running == nil ? 0.2 : 6.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: location, configuration: configuration) { _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        log("Steam restart failed: \(error.localizedDescription)")
                        Speaker.shared.speak("Could not start Steam: \(error.localizedDescription)")
                    } else {
                        log("Steam restart: Steam is starting.")
                    }
                }
            }
        }
    }

    /// The Windows client in a CrossOver bottle. Quit is forced (measured: it ignores every
    /// polite request), and the relaunch goes through CrossOver's app so the Wine server it
    /// gets can reach the network and the screen.
    private static func restartBottle(named name: String, steamExe: URL, then finished: @escaping (String) -> Void) {
        guard let crossOver = NSWorkspace.shared.urlForApplication(withBundleIdentifier: SteamInstall.crossOverBundle) else {
            finished("CrossOver is not installed, so Steam in the \(name) bottle cannot be started.")
            return
        }
        let running = NSWorkspace.shared.runningApplications.filter {
            ($0.localizedName ?? "").lowercased() == "steam.exe"
        }
        for app in running { app.forceTerminate() }
        // Its web helpers are separate Wine processes that outlive it and keep the port.
        let sweep = Process()
        sweep.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        sweep.arguments = ["-9", "-f", "steamwebhelper.exe"]
        try? sweep.run()
        log("Steam restart (\(name) bottle): force-quit \(running.count) Steam process(es); relaunching through CrossOver.")
        finished(running.isEmpty ? "Starting Steam in the \(name) bottle." : "Restarting Steam in the \(name) bottle. It takes a few seconds.")

        let delay: TimeInterval = running.isEmpty ? 0.2 : 4.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([steamExe], withApplicationAt: crossOver, configuration: configuration) { _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        log("Steam restart (\(name) bottle) failed: \(error.localizedDescription)")
                        Speaker.shared.speak("Could not start Steam in the \(name) bottle: \(error.localizedDescription)")
                    } else {
                        log("Steam restart (\(name) bottle): Steam is starting.")
                    }
                }
            }
        }
    }
}
