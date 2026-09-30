# Steam Speak

A menu bar app for the Mac that reads Steam's **Big Picture** aloud. With VoiceOver on it speaks through VoiceOver — one voice, yours; with VoiceOver off it uses the system voice you pick. Either way you open Big Picture, drive it with your controller, and Steam Speak tells you what is highlighted.

## Why it exists

Big Picture is silent on macOS and no setting fixes it: Steam draws its interface off-screen in a helper process and hands macOS finished pixels, so there is nothing for VoiceOver to read. The one door Steam leaves open is Chromium's remote-debugging port. Steam Speak enables it (an empty switch file in Steam's client directory), attaches to every Big Picture page, watches the class Valve's own focus system toggles as you move, and speaks the name of each thing you land on.

## VoiceOver on or off

Because VoiceOver follows the active application, and Steam's Big Picture process cannot hold activation on macOS — it is an accessory process with no accessibility tree, so a second after you enter, macOS hands the front to Finder and VoiceOver goes with it, reading the desktop. Every way of keeping VoiceOver's cursor on Big Picture from outside Steam was tried in the parent project and measured to fail, or to cost Steam's own controller handling and sounds. Steam Speak does not try: it narrates from the side. The voice picks itself. When VoiceOver is on **and settled inside Steam** — turn VoiceOver off, enter Big Picture, turn it back on, and it stays put — every item is spoken in **VoiceOver's own voice**, each new item cutting off the last. Any other time — VoiceOver off, or VoiceOver flung out at entry — the **system voice** you chose speaks instead, so it is never silent. When you scroll faster than speech, only the latest item is spoken — you always end on the item you are on.

## Using it

1. Install Steam Speak and open it. It lives in the menu bar (a speaker icon).
2. The first time, choose **Restart Steam so it can be read**. Steam comes back with its port open. You need this again after a Steam update — Steam Speak will tell you if Steam is running without its port.
3. Pick a **Voice** and **Speed** in the menu, with VoiceOver on if you like; **Speak a test sentence** to check.
4. Open Big Picture and use the controller. For VoiceOver's own voice: turn VoiceOver off, enter Big Picture, turn VoiceOver back on — it stays settled in Steam and speaks the items itself. Skip that and the system voice reads instead. No permissions either way. Steam Speak reads each highlighted item: its name, a role word where it matters (tab, slider, switch), its state, and a short blurb for cards.
5. Do not run Muteny at the same time: its frame would claim the front and seize the controller, and its own reader would narrate too.

The status line at the top of the menu says what it is doing, and says so if VoiceOver is on.

## Steam inside a CrossOver bottle

Since 28 September 2026 the reader also covers the **Windows** Steam client running in a
CrossOver bottle (installed for Diablo IV, whose screen reader exists only on Windows). Wine
shares the Mac's loopback, so that client's Big Picture appears on the same port and is read
exactly like the native one — verified the same day with protocol arrow keys. Steam Speak puts
the switch file into every bottle that holds a `steam.exe` as well as into the Mac client, and
**Restart Steam** acts on whichever is running. Two measured facts behind that: the bottle's
Steam ignores `-shutdown` and SIGTERM, so its restart is a forced quit; and it must be launched
through CrossOver's own app (`open -a CrossOver …/steam.exe`) — started from a shell it gets a
Wine server that cannot reach the network, shows no window, and exits three minutes in with a
stalled-pipe assert.

## What it does not do

Hold the front, seize the controller, or relay input. It uses no AppleScript and needs no permissions at all. All of those were built in Muteny, this app's parent, and each worked in part and cost more than it gave. Steam Speak is the part that worked from the beginning: the reading.

## Known gap

Steam's settings screens have focused elements without a recognisable name, and are read as nothing. The log records each one (`skipped a nameless focus`) so the gap can be closed.

## Building

`./build.sh` — see CLAUDE.md. Logs are in `~/Library/Application Support/Steam Speak/logs/`.
