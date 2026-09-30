import AVFoundation
import AppKit
import Foundation

/// Steam Speak's voice.
///
/// **With VoiceOver on: VoiceOver itself speaks** (`tell application "VoiceOver" to output`)
/// — the route that read Big Picture all day on 17 September 2026. It needs the Automation
/// permission, granted once. Every call is a child process killed after 3 seconds, with the
/// synthesiser saying that item instead if the call fails — so a hung VoiceOver or a pending
/// permission prompt can cost a few items their voice, never their words. The accessibility-
/// announcement route stays dead: silent on this macOS in every state (log-proven 18 Sep,
/// 19:17). **With VoiceOver off: the system synthesiser**, voice and speed from the menu.
///
/// Speech is coalesced: at most one utterance per 0.3 s, and when items come faster only the
/// latest is spoken — scrolling a shelf sounds like flicking through it, and you always end
/// on the item you are on.
final class Speaker: ObservableObject {
    static let shared = Speaker()

    private let synth = AVSpeechSynthesizer()

    /// The identifier of the chosen voice; empty means the system default.
    @Published var voiceIdentifier: String {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: "voice") }
    }
    /// AVSpeechUtterance rate, 0…1. The system default is 0.5.
    @Published var rate: Float {
        didSet { UserDefaults.standard.set(rate, forKey: "rate") }
    }

    private init() {
        let defaults = UserDefaults.standard
        voiceIdentifier = defaults.string(forKey: "voice") ?? ""
        rate = (defaults.object(forKey: "rate") as? Float) ?? 0.55
    }

    /// Voices in the user's language first, then everything else, each group by name.
    var voices: [AVSpeechSynthesisVoice] {
        let mine = Locale.current.language.languageCode?.identifier ?? "en"
        let all = AVSpeechSynthesisVoice.speechVoices()
        let local = all.filter { $0.language.hasPrefix(mine) }.sorted { $0.name < $1.name }
        let rest = all.filter { !$0.language.hasPrefix(mine) }.sorted { $0.name < $1.name }
        return local + rest
    }

    var currentVoiceName: String {
        voices.first { $0.identifier == voiceIdentifier }?.name ?? "System default"
    }

    // MARK: The coalescer

    private var pending: (text: String, interrupting: Bool)?
    private var lastDeliveredAt = Date.distantPast
    private var gapTimer: Timer?
    private static let minimumGap: TimeInterval = 0.3

    func speak(_ text: String, interrupting: Bool = true) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.speak(trimmed, interrupting: interrupting) }
            return
        }
        // Latest wins. A non-interrupting message (a status sentence) must not be eaten by a
        // later focus item, so it delivers on its own, outside the slot.
        if !interrupting { deliver(trimmed, interrupting: false); return }
        pending = (trimmed, true)
        let since = Date().timeIntervalSince(lastDeliveredAt)
        if since >= Self.minimumGap {
            deliverPending()
        } else if gapTimer == nil {
            gapTimer = Timer.common(Self.minimumGap - since, repeats: false) { [weak self] _ in
                self?.gapTimer = nil
                self?.deliverPending()
            }
        }
    }

    private func deliverPending() {
        guard let (text, interrupting) = pending else { return }
        pending = nil
        deliver(text, interrupting: interrupting)
    }

    private func deliver(_ text: String, interrupting: Bool) {
        lastDeliveredAt = Date()
        log("Speaker → \(text.prefix(80))")
        if NSWorkspace.shared.isVoiceOverEnabled, Date() >= voBrokenUntil {
            noteRoute("VoiceOver itself")
            speakThroughVoiceOver(text) { [weak self] ok in
                guard let self = self else { return }
                if !ok {
                    // This utterance still gets said — by the synthesiser — and the route
                    // rests for a moment so a denied permission cannot lag every item.
                    self.voBrokenUntil = Date().addingTimeInterval(20)
                    self.speakWithSynth(text, interrupting: interrupting)
                } else if self.pending != nil, self.gapTimer == nil {
                    self.deliverPending()
                }
            }
        } else {
            noteRoute("the system voice")
            speakWithSynth(text, interrupting: interrupting)
        }
    }

    private func speakWithSynth(_ text: String, interrupting: Bool) {
        if interrupting, synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        if !voiceIdentifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        }
        synth.speak(utterance)
    }

    // MARK: VoiceOver itself

    /// `tell application "VoiceOver" to output` — the route that read Big Picture all day on
    /// 17 September 2026 in the parent project. It failed in this app for one reason only:
    /// Steam Speak is a new bundle and was never granted the Automation permission, so its
    /// first call sat as an unanswered consent prompt and was mistaken for a broken OS.
    /// It runs as a child `osascript` killed after 3 seconds, so no call can ever wedge
    /// speech: worst case that one item is spoken by the synthesiser instead.
    private var voBrokenUntil = Date.distantPast
    private var warnedDenied = false
    private let voQueue = DispatchQueue(label: "steamspeak.voiceover.output")

    private func speakThroughVoiceOver(_ text: String, done: @escaping (Bool) -> Void) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        voQueue.async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "tell application \"VoiceOver\" to output \"\(escaped)\""]
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = Pipe()
            do { try process.run() } catch {
                DispatchQueue.main.async { log("Speaker: could not run osascript — \(error.localizedDescription)"); done(false) }
                return
            }
            let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3.0, execute: watchdog)
            process.waitUntilExit()
            watchdog.cancel()
            let ok = process.terminationStatus == 0
            let err = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            DispatchQueue.main.async { [weak self] in
                if !ok, let self = self, !self.warnedDenied {
                    self.warnedDenied = true
                    if err.contains("-1743") {
                        log("Speaker: VoiceOver route refused (-1743) — allow Steam Speak under Privacy & Security, Automation, VoiceOver.")
                        self.speakWithSynth("To hear VoiceOver's own voice, allow Steam Speak to control VoiceOver in Privacy and Security settings, under Automation.", interrupting: false)
                    } else {
                        log("Speaker: VoiceOver route failed — \(err.isEmpty ? "timed out after 3 seconds (a pending permission prompt looks exactly like this)" : String(err.prefix(160)))")
                    }
                }
                done(ok)
            }
        }
    }

    func stop() {
        pending = nil
        gapTimer?.invalidate()
        gapTimer = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    private var lastRoute = ""
    private func noteRoute(_ route: String) {
        guard route != lastRoute else { return }
        lastRoute = route
        log("Speaker: speaking through \(route).")
    }
}
