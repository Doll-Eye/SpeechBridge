import Foundation
import AppKit

/// Reads Steam's Big Picture aloud.
///
/// Big Picture is silent on macOS for a reason no flag fixes: Steam draws its Chromium UI
/// off-screen in a background helper and composites the pixels itself, so there is no native
/// accessibility tree — the helper's accessibility application is empty even with
/// `AXEnhancedUserInterface` set. Valve's own "screen reader" is Orca reading an AT-SPI tree
/// on SteamOS; on Mac there is nothing to read from.
///
/// So the reading is supplied from outside, through the one interface Steam's Chromium does
/// offer: remote debugging on localhost:8080, enabled by an empty switch file in the client's
/// own directory. This attaches to every Big Picture page — the main UI, the Quick Access
/// overlay, the Steam menu, the toasts — installs a `MutationObserver` on the class attribute
/// Valve's own focus tree toggles (`gpfocus`; the gamepad UI never moves DOM focus), computes a
/// name from the semantics Valve wrote, and hands it out through a `Runtime` binding. Every
/// move is an event from inside the page.
///
/// It does nothing else. Steam stays the front app and reads the controller itself; this app
/// listens and talks — through VoiceOver when VoiceOver is on, with the system voice when it
/// is off. It does not try to keep VoiceOver's cursor on Big Picture: every way of doing that
/// from outside Steam was measured and failed, because VoiceOver follows the active
/// application and Steam Helper (an accessory process with no accessibility tree) cannot hold
/// activation. The narration does not depend on where the cursor is. History: the Muteny project.
final class Reader: ObservableObject {
    static let shared = Reader()

    @Published private(set) var isOn = false
    @Published private(set) var portIsUp = false
    @Published private(set) var attachedTitles: [String] = []
    @Published private(set) var lastSpoken = ""
    @Published private(set) var steamRunningWithoutPort = false
    /// Something is answering on port 8080 that is not Steam — a dev server, someone
    /// else's debug port. Attaching to it would inject our script into a stranger's pages.
    @Published private(set) var portIsNotSteam = false
    private var warnedNotSteam = false
    private var hadBigPicture = false

    private var pollTimer: Timer?
    private var sessions: [String: Session] = [:]
    private var lastSpokenAt = Date.distantPast

    private static let endpoint = URL(string: "http://localhost:8080/json")!

    /// Every Steam this Mac can read — the native client and any CrossOver bottle holding one
    /// (`SteamInstall`) — gets the switch file. A Steam update replaces the client directory and
    /// the file with it, so it is put back every time the reader starts rather than trusted.
    /// Returns false only when no Steam is installed anywhere.
    @discardableResult
    static func ensureSwitchFile() -> Bool {
        let installs = SteamInstall.all
        for install in installs { install.ensureSwitchFile() }
        return !installs.isEmpty
    }

    /// A sentence for the menu bar.
    var status: String {
        if !isOn { return "Not reading." }
        if steamRunningWithoutPort { return "Steam is running without its port — restart Steam below." }
        if portIsNotSteam { return "Port 8080 is in use by something that is not Steam. Quit that program, then restart Steam." }
        if !portIsUp { return "Waiting for Steam." }
        if attachedTitles.isEmpty { return "Steam is up; waiting for Big Picture." }
        return lastSpoken.isEmpty ? "Reading Big Picture." : "Reading Big Picture. Last: \(lastSpoken.prefix(60))"
    }

    func start() {
        guard !isOn else { return }
        isOn = true
        Self.ensureSwitchFile()
        log("Reader: on. Watching localhost:8080 for Big Picture.")
        pollTimer?.invalidate()
        pollTimer = Timer.common(2.0, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    func stop() {
        guard isOn else { return }
        isOn = false
        pollTimer?.invalidate()
        pollTimer = nil
        for session in sessions.values { session.close() }
        sessions.removeAll()
        attachedTitles = []
        Speaker.shared.stop()
        log("Reader: off.")
    }

    // MARK: Finding the pages

    private var portDownSince: Date?
    private var warnedPortDown = false

    /// Steam is running and its port is not there. Said once, out loud, because the alternative
    /// is a reader that goes silent and a person who does not know why — which is what a Steam
    /// update does: it replaces the client directory, the switch file goes with it, and Steam
    /// comes back up with no port. The file is put back here; the menu has Restart Steam.
    private func portDownWhileSteamRuns() {
        let steamRunning = NSWorkspace.shared.runningApplications.contains(where: SteamInstall.isSteamProcess)
        guard steamRunning else {
            portDownSince = nil; warnedPortDown = false; steamRunningWithoutPort = false
            return
        }
        Self.ensureSwitchFile()
        if portDownSince == nil { portDownSince = Date() }
        guard let since = portDownSince, Date().timeIntervalSince(since) > 8 else { return }
        steamRunningWithoutPort = true
        guard !warnedPortDown else { return }
        warnedPortDown = true
        log("Reader: Steam is running without its debugging port. It needs restarting before Big Picture can be read.")
        Speaker.shared.speak("Steam needs restarting before Big Picture can be read. Restart Steam is in the Steam Speak menu.", interrupting: false)
    }

    private struct Target: Decodable {
        let id: String
        let type: String?
        let title: String?
        let url: String?
        let webSocketDebuggerUrl: String?
    }

    private func poll() {
        URLSession.shared.dataTask(with: Self.endpoint) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self, self.isOn else { return }
                let targets = data.flatMap { try? JSONDecoder().decode([Target].self, from: $0) }
                // Steam's own endpoint always lists SharedJSContext at steamloopback.host.
                // Anything on 8080 without it is some other program — never attach to that:
                // our observer script must not be injected into a stranger's pages, and
                // "restart Steam" would be the wrong advice.
                let isSteam = targets?.contains { ($0.url ?? "").contains("steamloopback.host") } ?? false
                guard let steamTargets = targets, error == nil, isSteam else {
                    let somethingAnswered = error == nil && data != nil
                    if somethingAnswered {
                        if !self.warnedNotSteam {
                            self.warnedNotSteam = true
                            log("Reader: port 8080 is answering but it is not Steam — not attaching. Whatever owns the port has to be quit before Steam can be read.")
                        }
                        self.portIsNotSteam = true
                    } else {
                        self.portIsNotSteam = false
                        self.warnedNotSteam = false
                        self.portDownWhileSteamRuns()
                    }
                    if self.portIsUp {
                        self.portIsUp = false
                        log("Reader: the debugging port went away — Steam has quit, or an update replaced its directory and took the switch file with it.")
                        Self.ensureSwitchFile()
                        for session in self.sessions.values { session.close() }
                        self.sessions.removeAll()
                        self.attachedTitles = []
                        self.hadBigPicture = false
                    }
                    return
                }
                if !self.portIsUp { self.portIsUp = true; log("Reader: debugging port is up.") }
                self.portDownSince = nil
                self.warnedPortDown = false
                self.steamRunningWithoutPort = false
                self.portIsNotSteam = false
                self.warnedNotSteam = false
                self.pingSessions()
                self.reconcile(steamTargets)
            }
        }.resume()
    }

    /// Attach to new Big Picture pages, drop the ones that have gone. SharedJSContext is Steam's
    /// own JS bridge and has no UI; everything else that is a page is something the cursor can
    /// be in.
    private func reconcile(_ targets: [Target]) {
        let wanted = targets.filter { $0.type == "page" && $0.title != "SharedJSContext" && $0.webSocketDebuggerUrl != nil }
        let ids = Set(wanted.map { $0.id })
        for (id, session) in sessions where !ids.contains(id) {
            log("Reader: \(session.title) closed.")
            session.close()
            sessions.removeValue(forKey: id)
        }
        for target in wanted where sessions[target.id] == nil {
            guard let url = URL(string: target.webSocketDebuggerUrl!) else { continue }
            let id = target.id
            let session = Session(title: target.title ?? target.id, url: url, onFocus: { [weak self] payload in
                self?.heard(payload, from: target.title ?? "Steam")
            }, onDead: { [weak self] in
                self?.sessionDied(id)
            })
            sessions[target.id] = session
            log("Reader: attached to \(session.title).")
        }
        attachedTitles = sessions.values.map { $0.title }.sorted()
        let hasBigPicture = sessions.values.contains { $0.title == "Steam Big Picture Mode" }
        if hasBigPicture && !hadBigPicture {
            hadBigPicture = true
            log("Reader: Big Picture is open — reading.")
            Speaker.shared.speak("Reading Big Picture.", interrupting: false)
        } else if !hasBigPicture {
            hadBigPicture = false
        }
    }

    /// A page's socket died without the page going away — Steam hiccupped, the machine
    /// slept, anything. Left alone this was permanent silence: the target id still appears
    /// in /json, so reconcile never re-attached. Drop it; the next poll attaches afresh.
    private func sessionDied(_ id: String) {
        guard sessions[id] != nil else { return }
        let title = sessions[id]?.title ?? id
        sessions.removeValue(forKey: id)
        attachedTitles = sessions.values.map { $0.title }.sorted()
        log("Reader: \(title)'s connection died — reattaching on the next poll.")
    }

    /// Every poll, ping every socket. A dead one that never delivers a receive error —
    /// seen after sleep — fails its ping instead, and gets reaped the same way.
    private func pingSessions() {
        for session in sessions.values { session.ping() }
    }

    // MARK: Speaking

    private func heard(_ payload: String, from title: String) {
        // Delivered on a URLSession thread; the reader's state is main-thread work.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.heard(payload, from: title) }
            return
        }
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if object["focusGone"] as? Bool == true {
            // An overlay (the Steam menu, Quick Access) lost focus: it is closing. Have the main
            // page say what is under focus now, since it will be the same element as before and
            // would otherwise stay silent.
            if title != "Steam Big Picture Mode" {
                sessions.values.first { $0.title == "Steam Big Picture Mode" }?
                    .evaluate("window.__steamSpeakReport && window.__steamSpeakReport()")
            }
            return
        }
        if object["skipped"] as? Bool == true {
            // A focused element with no name and no role. Logged so the gaps — Steam's settings
            // screens, for one — can be seen and closed; nothing is said for it.
            log("Reader: skipped a nameless focus in \(title) — tag=\(object["tag"] ?? "") cls=\(object["cls"] ?? "") text=\"\(object["text"] ?? "")\"")
            return
        }
        var text = (object["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let role = object["role"] as? String ?? ""
        let state = object["state"] as? String ?? ""
        guard !text.isEmpty || !role.isEmpty else { return }
        // Role words only where they carry information: a tab is worth knowing about, a button
        // is what most things are.
        if role == "tab" { text += ", tab" }
        if role == "slider" || role == "checkbox" || role == "switch" || role == "radio" { text += ", \(role)" }
        if !state.isEmpty { text += ", \(state)" }
        if text.isEmpty { text = role }
        if let blurb = object["blurb"] as? String, !blurb.isEmpty { text += ". \(blurb)" }
        // The same thing twice in quick succession is one event that fired twice.
        let now = Date()
        if text == lastSpoken && now.timeIntervalSince(lastSpokenAt) < 0.6 { return }
        lastSpoken = text
        lastSpokenAt = now
        log("Reader (\(title)): \(text.prefix(120))")
        Speaker.shared.speak(text, interrupting: true)
    }

    // MARK: One DevTools session

    /// The script that lives in the page. Valve's semantics do the work: `aria-label` first,
    /// then a title-like descendant, then the element's own text, capped, first line only — a
    /// news card is not its whole body. Versioned so a newer build replaces an older observer
    /// rather than deferring to it; named for this app so it can run beside Muteny's without
    /// either hearing the other's events.
    private static let observer = #"""
    (() => {
      if (window.__steamSpeakReader === 2) return 'already';
      window.__steamSpeakReader = 2;
      if (window.__steamSpeakStop) { try { window.__steamSpeakStop(); } catch (e) {} }
      const clean = s => (s || '').replace(/\s+/g, ' ').trim();
      const firstLine = s => (s || '').split('\n').map(x => x.trim()).filter(Boolean)[0] || '';
      const name = el => {
        const al = el.getAttribute('aria-label'); if (al) return clean(al);
        const lb = el.getAttribute('aria-labelledby');
        if (lb) { const t = clean(lb.split(/\s+/).map(id => (document.getElementById(id) || {}).innerText || '').join(' ')); if (t) return t; }
        // Several things in a tile can look like a title. The shortest non-empty one is the
        // title; the long one is the blurb, and it comes after a pause, capped, so a card reads
        // as "name — then what it is" rather than as one breath.
        const cands = Array.from(el.querySelectorAll('h1,h2,h3,h4,[class*="Title" i],[class*="Name" i],[class*="Label" i]'))
          .map(n => clean(firstLine(n.innerText))).filter(s => s && s.length <= 90);
        if (cands.length) return cands.sort((a, b) => a.length - b.length)[0];
        const own = clean(firstLine(el.innerText || el.textContent));
        if (own) return own.length > 90 ? own.slice(0, 90).replace(/\s+\S*$/, '') : own;
        const img = el.querySelector('img[alt]'); if (img && img.alt) return clean(img.alt);
        return '';
      };
      const blurb = (el, nm) => {
        const all = clean(el.innerText || '');
        if (!all || all.length <= nm.length + 12) return '';
        const rest = clean(all.replace(nm, ''));
        return rest.length > 140 ? rest.slice(0, 140).replace(/\s+\S*$/, '') + '…' : rest;
      };
      const role = el => el.getAttribute('role') || (el.tagName === 'BUTTON' ? 'button' : el.tagName === 'INPUT' ? (el.type || 'input') : '');
      const state = el => {
        const s = [];
        if (el.getAttribute('aria-selected') === 'true' && el.getAttribute('role') !== 'tab') s.push('selected');
        if (el.getAttribute('aria-checked') === 'true' || el.getAttribute('aria-pressed') === 'true') s.push('on');
        if (el.getAttribute('aria-checked') === 'false' || el.getAttribute('aria-pressed') === 'false') s.push('off');
        if (el.getAttribute('aria-disabled') === 'true') s.push('unavailable');
        const v = el.getAttribute('aria-valuetext') || el.getAttribute('aria-valuenow'); if (v) s.push(v);
        return s.join(', ');
      };
      let last = null;
      const report = () => {
        const el = document.querySelector('.gpfocus');
        if (!el) {
          // Focus left this page — an overlay took it. Forget the last element, so that when
          // focus comes back to the very same element it is announced again. Backing out of
          // the Steam menu with Circle used to be silent for exactly this reason. Tell the app,
          // so an overlay closing can have the page underneath speak again.
          if (last !== null) { last = null; window.__steamSpeak(JSON.stringify({ focusGone: true })); }
          return;
        }
        if (el === last) return;
        last = el;
        const nm = name(el);
        if (!nm && !role(el)) {
          window.__steamSpeak(JSON.stringify({ skipped: true, tag: el.tagName, cls: (el.className || '').toString().slice(0, 90),
            text: (el.textContent || '').trim().slice(0, 90) }));
          return;
        }
        window.__steamSpeak(JSON.stringify({ name: nm, role: role(el), state: state(el), blurb: blurb(el, nm) }));
      };
      const focusObserver = new MutationObserver(report);
      focusObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['class'], subtree: true });
      // Valve's own announcements — the on-screen keyboard's key names go through a live region.
      const liveObserver = new MutationObserver(muts => {
        for (const m of muts) {
          const el = m.target.nodeType === 1 ? m.target : m.target.parentElement;
          const region = el && el.closest('[aria-live]');
          if (!region) continue;
          const t = clean(region.textContent);
          if (t) window.__steamSpeak(JSON.stringify({ name: t, role: '', state: '' }));
        }
      });
      liveObserver.observe(document.documentElement, { childList: true, characterData: true, subtree: true });
      // Asked for by the app when an overlay closes; and when this window gets focus back.
      window.__steamSpeakReport = () => { last = null; report(); };
      window.addEventListener('focus', window.__steamSpeakReport);
      window.__steamSpeakStop = () => { focusObserver.disconnect(); liveObserver.disconnect(); window.removeEventListener('focus', window.__steamSpeakReport); };
      report();
      return 'installed v2';
    })()
    """#

    private final class Session {
        let title: String
        private let task: URLSessionWebSocketTask
        private let lock = NSLock()
        private var nextId = 1
        private var pending: [Int: ([String: Any]) -> Void] = [:]
        private let onFocus: (String) -> Void
        private let onDead: () -> Void
        private var closed = false

        init(title: String, url: URL, onFocus: @escaping (String) -> Void, onDead: @escaping () -> Void) {
            self.title = title
            self.onFocus = onFocus
            self.onDead = onDead
            task = URLSession.shared.webSocketTask(with: url)
            task.resume()
            receive()
            send("Runtime.enable")
            send("Page.enable")
            send("Runtime.addBinding", ["name": "__steamSpeak"])
            // Installed now, and again on every navigation inside the page, so leaving the
            // library for the store and coming back does not lose the reader.
            send("Page.addScriptToEvaluateOnNewDocument", ["source": Reader.observer])
            send("Runtime.evaluate", ["expression": Reader.observer, "returnByValue": true]) { result in
                let value = ((result["result"] as? [String: Any])?["value"] as? String) ?? "\(result)"
                log("Reader: observer in \(title): \(value)")
            }
        }

        func close() {
            closed = true
            task.cancel(with: .goingAway, reason: nil)
        }

        func ping() {
            task.sendPing { [weak self] error in
                guard error != nil else { return }
                self?.died()
            }
        }

        /// Once. An intentional close is not a death.
        private func died() {
            guard !closed else { return }
            closed = true
            task.cancel(with: .goingAway, reason: nil)
            DispatchQueue.main.async { self.onDead() }
        }

        func evaluate(_ expression: String) {
            send("Runtime.evaluate", ["expression": expression])
        }

        private func send(_ method: String, _ params: [String: Any] = [:], _ done: (([String: Any]) -> Void)? = nil) {
            lock.lock()
            let id = nextId
            nextId += 1
            if let done = done { pending[id] = done }
            lock.unlock()
            guard let data = try? JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params]) else { return }
            task.send(.string(String(decoding: data, as: UTF8.self))) { error in
                if let error = error { log("Reader: send failed — \(error.localizedDescription)") }
            }
        }

        private func receive() {
            task.receive { [weak self] result in
                guard let self = self, !self.closed else { return }
                switch result {
                case .failure(let error):
                    log("Reader: \(self.title) socket closed — \(error.localizedDescription)")
                    self.died()
                case .success(let message):
                    var text = ""
                    if case .string(let s) = message { text = s }
                    if case .data(let d) = message { text = String(decoding: d, as: UTF8.self) }
                    if let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
                        if let id = object["id"] as? Int {
                            self.lock.lock()
                            let callback = self.pending.removeValue(forKey: id)
                            self.lock.unlock()
                            callback?((object["result"] as? [String: Any]) ?? (object["error"] as? [String: Any]) ?? [:])
                        } else if object["method"] as? String == "Runtime.bindingCalled",
                                  let payload = (object["params"] as? [String: Any])?["payload"] as? String {
                            self.onFocus(payload)
                        }
                    }
                    self.receive()
                }
            }
        }
    }
}
