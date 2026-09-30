import SwiftUI
import AppKit
import ApplicationServices

/// Steam Speak: a menu bar app that reads Steam's Big Picture aloud with the system voice.
///
/// Used with VoiceOver off. Steam stays the front app and reads the controller itself; this
/// app only listens on Steam's debugging port and talks. There is deliberately nothing else
/// here — no windows, no controller code, no VoiceOver scripting.
@main
struct SteamSpeakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var reader = Reader.shared
    @StateObject private var speaker = Speaker.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContents(reader: reader, speaker: speaker)
        } label: {
            Label("Steam Speak", systemImage: reader.isOn ? "speaker.wave.2.fill" : "speaker.slash")
        }
    }
}

struct MenuContents: View {
    @ObservedObject var reader: Reader
    @ObservedObject var speaker: Speaker

    var body: some View {
        Text(reader.status)
        Divider()
        Toggle("Read Big Picture aloud", isOn: Binding(
            get: { reader.isOn },
            set: { on in on ? reader.start() : reader.stop() }))
        Menu("Voice: \(speaker.currentVoiceName)") {
            Picker("Voice", selection: $speaker.voiceIdentifier) {
                Text("System default").tag("")
                ForEach(speaker.voices, id: \.identifier) { voice in
                    Text("\(voice.name) — \(voice.language)").tag(voice.identifier)
                }
            }
            .pickerStyle(.inline)
        }
        Menu("Speed") {
            Picker("Speed", selection: $speaker.rate) {
                Text("Slow").tag(Float(0.45))
                Text("Normal").tag(Float(0.55))
                Text("Fast").tag(Float(0.65))
                Text("Faster").tag(Float(0.75))
                Text("Very fast").tag(Float(0.85))
            }
            .pickerStyle(.inline)
        }
        Button("Speak a test sentence") { speaker.speak("Steam Speak is ready.") }
        Divider()
        Button("Restart Steam so it can be read") {
            SteamRestart.run { sentence in speaker.speak(sentence) }
        }
        Button(LoginItem.isEnabled ? "Don't open at login" : "Open at login") {
            speaker.speak(LoginItem.setEnabled(!LoginItem.isEnabled), interrupting: false)
        }
        Button("Show the log folder") { NSWorkspace.shared.open(AppLog.directory) }
        Divider()
        Button("Quit Steam Speak") { NSApplication.shared.terminate(nil) }
    }
}

/// Lifetime wiring lives here, not on a view: this is a menu bar app with no window, so a
/// view's `onAppear` may never run — at login it does not — and anything started there never
/// starts. `applicationDidFinishLaunching` runs for the process, every time.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Parked 19 Sep 2026: the owner judged the VoiceOver barriers too many for daily use
        // and may instead ask Valve to enable their own screen reader on the Mac. These flags
        // let the login item be turned on or off from outside while the app is shelved.
        if CommandLine.arguments.contains("--disable-login-item") { _ = LoginItem.setEnabled(false); exit(0) }
        if CommandLine.arguments.contains("--enable-login-item") { _ = LoginItem.setEnabled(true); exit(0) }
        log("Steam Speak starting. \(ProcessInfo.processInfo.operatingSystemVersionString)")
        LoginItem.registerOnFirstRun()
        Reader.shared.start()
        // Ask for the VoiceOver Automation permission explicitly. The implicit ask — the
        // first osascript call — sat as a pending event and macOS never showed a dialog
        // (measured 18 Sep 2026, 19:32). This call raises the dialog reliably. Background
        // queue, never the main thread: with the dialog pending it blocks until answered,
        // and it once froze the parent project's whole app from the main thread.
        DispatchQueue.global(qos: .utility).async {
            var target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.VoiceOver").aeDesc!.pointee
            let status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, true)
            DispatchQueue.main.async {
                switch status {
                case 0: log("Automation permission for VoiceOver: granted.")
                case -1743: log("Automation permission for VoiceOver: refused — allow Steam Speak in Privacy & Security, Automation.")
                default: log("Automation permission for VoiceOver: status \(status).")
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Reader.shared.stop()
    }
}
