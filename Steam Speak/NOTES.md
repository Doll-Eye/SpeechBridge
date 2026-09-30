# Working on Steam Speak

Read `README.md` first — it says what the app is, the verified Steam facts it rests on, and why it is shaped the way it is. This file is about how to work here. Steam Speak was forked from Muteny (`../Muteny`) on 17 September 2026; Muteny's README and CLAUDE.md hold the full measured history of every approach that was tried and failed before this one.

## Who you are working with

The owner is a blind developer using VoiceOver full-time. This app works with VoiceOver on (speaking through it, one voice) or off (system voice). Consequences:

- Every control needs a label that makes sense out of context. Do not make things speak that VoiceOver already reads — the app's narration is for Big Picture, which VoiceOver cannot read.
- Never use the word "quietly".
- Answer directly. If uncertain, say so and say what would settle it. Do not present reconstructed facts as verified.
- Prose replies: headings, so they can be navigated by heading. No long undifferentiated blocks.

## Build and run

    ./build.sh

builds Debug with `xcodebuild -scheme "Steam Speak"` (the shared scheme was cloned from Muteny's; `-derivedDataPath` requires a scheme), installs to `/Applications/Steam Speak.app` and relaunches it. Read the newest file in `~/Library/Application Support/Steam Speak/logs/` after every build; the log is the primary instrument, the owner cannot glance at the screen. **Do not build into the project directory** — it is under `~/Desktop`, which iCloud syncs, and the file provider's extended attributes make `codesign` reject the bundle. `build.sh` builds into `~/Library/Developer/SteamSpeak`.

Test the read loop without a controller by sending arrow keys over the protocol (`Input.dispatchKeyEvent` to the Big Picture page's WebSocket) and reading the log. Muteny's scratch tools did exactly this.

## The CrossOver bottle

`SteamInstall` (in `SteamRestart.swift`) is the one list of Steam clients: the Mac client and
every CrossOver bottle with a `steam.exe`. Anything that needs a Steam path — the switch file,
"is Steam running", restart — goes through it; do not add a second path. Never start the
bottle's Steam from a shell (a sandboxed or shell-spawned wineserver kills it at ~190 s);
`open -a CrossOver <steam.exe>` is the launch that works, and the restart code does the same
through `NSWorkspace.open(_:withApplicationAt:)`. The bottle restart path was built on
28 Sep 2026 and is **not yet exercised live** — the first Restart Steam with only the bottle
running is its test; read the log for `Steam restart (Steam bottle)`.

## Rules

- **`project.pbxproj` is hand-maintained.** New source file = four lines: PBXBuildFile, PBXFileReference, the group's children, the Sources phase. IDs are `BB00000000000000000001NN` / `…02NN`; next free is 06. Do not let Xcode "upgrade" it.
- **The synthesiser is the only speech route.** Two VoiceOver-mediated routes were built and
  are dead on the owner's macOS (27.2 beta, 18 Sep 2026): AppleScript `output` queues, needs
  two permissions, is not main-thread-safe, and hung unkillably in the field (−1712, one full
  minute); accessibility announcements (high-priority, posted on an anchor panel — ear-verified
  on 27.0) are **silent on 27.2 in every state including fully settled** — log-proven at
  19:17 that day: VoiceOver on, Steam Helper frontmost, a dozen announcements delivered,
  nothing heard. "VoiceOver's voice" is delivered honestly instead: the user picks the same
  voice VoiceOver uses in the Voice menu. Do not rebuild either dead route without a fresh
  ear test on the owner's current macOS.
- **Speech is coalesced** (`Speaker`): at most one utterance per 0.3 s, latest item wins.
  Under a 40-key 90 ms burst: 25 heard → 13 spoken, final spoken = final heard. At human pace
  every item is spoken (223-key soak: 161/161). Do not remove the coalescer; an unbounded
  spoken backlog was the original "misbehaving".
- **Never attach to port 8080 without the steamloopback gate.** Steam's own endpoint always
  lists SharedJSContext at `steamloopback.host`; anything else on 8080 is a stranger — a dev
  server gets a clear status message, and a foreign CDP endpoint must never receive our
  script (stress-tested with a fake endpoint: 0 attachments). A foreign server is also not a
  reason to nag "restart Steam".
- **Dead sockets are reaped.** A page's WebSocket can die while the page stays listed in
  /json — left alone that was permanent silence. Sessions report death once (receive failure
  or failed ping; pings go out every poll) and the Reader drops them so the next poll
  reattaches.
- **Keep it slim.** This app listens and talks. It does not hold the front, seize the controller, or relay input — each of those was built in Muteny, worked partially, and was judged not worth its complexity. The one VoiceOver script is `output`, so VoiceOver says the words when it is on; note `output` queues behind VoiceOver's own speech and cannot interrupt it. If a feature needs any of them, it belongs in Muteny.
- **Every `Timer` goes through `Timer.common(…)`**, never `Timer.scheduledTimer` — the poll must survive the menu being open.
- **Edit files with anchored replacements and assert each anchor.** Silent no-op edits cost hours in the parent project.
- **No `+` string chains inside SwiftUI bodies.** Use interpolation.
- **Nothing the app needs may hang off a view.** `start()` runs in `applicationDidFinishLaunching`.

## Verified Steam facts (17 September 2026, this Mac)

- Steam's remote-debugging port (localhost:8080) is enabled by an **empty file** `~/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/.cef-enable-remote-debugging`. At the Steam root it does nothing. A Steam update replaces that directory and removes the file; the reader recreates it on every start, and warns aloud when Steam is running without the port.
- Page targets: `Steam Big Picture Mode`, `MainMenu_uidN`, `QuickAccess_uidN`, `notificationtoasts_uidN`, plus `SharedJSContext` (no UI — skipped).
- Gamepad focus is the CSS class `gpfocus` on `Focusable` elements; DOM focus never moves, so `activeElement` sees nothing. A `MutationObserver` on the class attribute is the whole mechanism.
- Steam's game shelf ignores arrow-left/right and moves on Tab / Shift-Tab; the tabs move on arrows. Irrelevant to this app (Steam reads its own controller) but worth knowing if input is ever revisited.
- Steam Remote Play runs in its own process, `steamstreamingclient`, which never appears as an application to activation. Irrelevant here for the same reason.

## Layout

    SteamSpeak/
      SteamSpeakApp.swift   the menu bar app and the delegate that starts the reader
      Reader.swift          the whole reader: switch file, port poll, page sessions, the observer script, text building
      Speaker.swift         the system synthesiser, with a remembered voice and speed
      SteamRestart.swift    quit Steam and relaunch it so the port comes up
      LoginItem.swift       opens at login by default (SMAppService); menu can turn it off
      AppLog.swift          log + Timer.common (logs older than 7 days are pruned)

## Backing out with Circle

Focus returns to the element you left, and the observer only reports a *change*, so it was silent. The observer (v2) now forgets its last element when focus leaves a page, tells the app (`focusGone`), and the app has the main page re-report when an overlay closes; the page also re-reports on `window` focus. Muteny's reader has the same fix (v5).

## Valve's own screen reader (researched 18 Sep 2026)

The client JS on this Mac contains a full screen-reader layer: setting keys
`accessibility_screen_reader_enabled` (protobuf n:26001), `_rate`/`_pitch`/`_volume`/`_locale`
(26003…26011), gate `is_screen_reader_supported` (n:24, false on Mac), controller actions
`#ControllerActionKey_ScreenReader_Enable/NextHeading/NextLandmark/…`, an OOBE
`ScreenReaderConfirm` page, and `AnnounceToScreenReader` rendering into an assertive
`AriaLiveRegion` (the virtual keyboard uses it — our live-region observer already reads it).
The speech sink is `SteamOSManager` (Linux only), which is why Big Picture is silent on Mac.
`SteamClient.Settings.SetSetting` exists in SharedJSContext; flipping the setting on Mac was
attempted once and did not visibly change the DOM (regions list stayed empty; call stalled) —
parked. If Valve ever ships the desktop screen reader (their June 2025 beta brought UI scale,
high contrast and reduced motion to desktop Big Picture; screen reader stayed SteamOS-only),
this app may become unnecessary, which would be the good ending.

## Desktop mode (measured 18 Sep 2026)

Steam's desktop windows are pages on the same port: 'Welcome to Steam', 'Steam',
'Library/Store/Community Supernav', menus — all attachable. They have **no `gpfocus`**
(that class is gamepad-UI only), so today's observer hears nothing there. But the pages
carry real aria-labels (88 on the store page alone; 239 focusable elements) — Valve's 2022
desktop-accessibility work — and keyboard focus is ordinary DOM focus. A desktop reader is
therefore feasible: a `focusin` listener announcing `document.activeElement`'s
label/role/state, same Speaker, same everything else. Not built yet. Native AX stays empty
(measured 17 Sep; a blind user gets nothing from VoiceOver directly in either mode).

## Known gap

Steam's settings screens have focused elements with no name and no role the observer recognises; the reader logs them as "skipped a nameless focus" and says nothing. Open the settings in Big Picture, read the log, and improve `name()` in the observer from what it shows.
