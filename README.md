# SpeechBridge — Windows games with a screen reader, on a Mac

This repository turns an Apple-silicon Mac into a gaming computer for a blind player. Windows
games run in a CrossOver bottle, their speech is caught by small stand-in Windows DLLs and sent
to a Mac app, and the Mac app says it through **VoiceOver** (or the system voice). Steam's Big
Picture, silent on macOS, is read aloud by a second Mac app, **Steam Speak**.

Everything here was built in a week of September 2026 by a blind developer and an AI (Claude),
on a MacBook Air M4 with 24 GB, macOS 27, CrossOver 26.3. It is written for two readers: a
blind Mac user who wants to play, and an AI or engineer picking up the same problem. The
first group should read "What you need" and "Install"; the second should also read "Traps"
and the engineering logs linked at the end.

## What plays today

| Game | Speech route | Notes |
|---|---|---|
| Diablo IV | its own screen reader → Tolk → SAAPI64 stand-in | the big one; see its section, it has rules |
| Hades II | Blind Accessibility + HadesIIAccess mods → Tolk → SAAPI64 | mods installed by hand |
| Fallout 4 | Fallout 4 Access (F4SE) → Prism → ZDSR stand-in | F4SE, Address Library, XDI, MCM |
| Stardew Valley | Stardew Access via SMAPI → Tolk → SAAPI64 | Steam launch option points at SMAPI |
| Final Fantasy VI Pixel Remaster | FF6 Screen Reader mod via MelonLoader → Tolk → SAAPI64 | MelonLoader installs .NET 6 itself on first run |
| Cyberpunk 2077 | Cyberpunk Access via RED4ext → Cyber TTS Engine (Prism) → ZDSR stand-in | nine prerequisites; Windows build, not the native Mac one |
| Bits & Bops, Rhythm Doctor, Blind Drive | UAP plugin → NVDA / WindowsTTS stand-ins | run the Setup app after installing |
| Slay the Princess (and any Ren'Py game) | Ren'Py self-voicing → `sbsay.exe` | one registry value |
| Periphery Synthetic EP (Electron) | aria-live regions → web reader in the listener | launch option opens a debugging port |
| Steam Big Picture | Chromium debugging port → **Steam Speak** | works for the Mac client and the bottle's |
| Any game that uses Windows' built-in voice (SAPI) | SapiBridge engine + SpVoice stand-in | nothing per game |

Not working: SEQUENCE STORM (needs an OpenGL 3.3 compatibility context, which macOS does not
have; not a speech problem). Untested: anything not in the table.

A DualSense works wired and over Bluetooth, including rumble in Steam games (that needed a
fix of its own, below).

## How it works, in one paragraph

A Windows game asks a speech API to talk: a screen reader through Tolk, NVDA's controller
client, the UAP `WindowsTTS.dll`, Microsoft SAPI, the Prism library, Ren'Py's external TTS
command. SpeechBridge puts a **stand-in DLL** where each of those is looked for. Each stand-in
does nothing but send the text as one line, `S <text>`, to `127.0.0.1:52134` (`X` to stop).
Wine shares the Mac's loopback, so the **SpeechBridge Listener**, a Mac menu-bar-less app, hears
it and speaks it through VoiceOver with a raw Apple event (about 30 ms; `osascript` per line
cost 500 ms). With VoiceOver off it uses the system voice. No screen reader for Windows is
installed in the bottle, and nothing in the bottle needs one.

## What you need

- A Mac with Apple silicon. Tested on an M4 MacBook Air with 24 GB; Diablo IV wants that
  much memory and a lot of disk (about 160 GB with expansions).
- **CrossOver 26** or later (paid, with a trial). Its "D3DMetal" graphics backend is what runs
  DirectX 12 games such as Diablo IV and Hades II.
- A Steam account and the Windows games you own.
- To build: Xcode's Command Line Tools (`xcode-select --install`), Homebrew, `mingw-w64`
  (`brew install mingw-w64`) for the Windows DLLs, and Xcode itself for Steam Speak. Prebuilt
  DLLs are in this repository, so the build step for them is optional.
- VoiceOver. The listener speaks through it; the first time, macOS asks you to allow the
  listener to control VoiceOver (System Settings → Privacy & Security → Automation).

## Install

Headings follow the order to do things in.

### 1. CrossOver and a bottle called Steam

Install CrossOver. Make one bottle, named **Steam**, Windows 10. In its settings turn on
**MSync** (the fast synchronisation) and set the graphics backend to **D3DMetal** (DXMT lacks
Direct3D 12 and Diablo IV cannot create a device on it). Install Steam into that bottle with
CrossOver's installer; sign in with "remember me".

CrossOver's own interface is only partly usable with VoiceOver. The install page defaults to
a new bottle; the existing bottle is chosen from the Edit sheet's pop-up. An AI driving the
Mac can do this with keyboard-only element navigation.

**A rule that cost an afternoon:** never start anything in the bottle from a terminal that an
AI runs, or from a login shell without a window server session — with MSync on, the bottle's
server is started under that shell's namespace, later launches attach to it, TLS fails, no
window appears and Steam dies after three minutes with "fatal stalled cross-thread pipe". Start
programs with `open -a CrossOver "<path to the .exe>"`, or with the run-in-bottle applet in
`SpeechBridge/tools/run-in-bottle.applescript` (compile with `osacompile`; it runs the command
written in a file called `cmd` and writes the output to `out`). If the bottle is wedged:
`pkill -9` every `.exe`, `winetemp-` and `bin/wineserver`, then relaunch with `open`.

A launcher for Steam that a blind user can open from Spotlight is
`SpeechBridge/tools/steam-launcher.applescript`, saved as an application with
`osacompile -o /Applications/Steam.app`. It starts Steam with CrossOver's command-line starter
(`cxstart --bottle Steam --no-update --no-wait --no-gui wscript.exe C:\SpeechBridge\steam.vbs`,
the script being `tools/steam.vbs`), so CrossOver's own window never opens, and brings Steam
forward if it is already running. Going through the script host matters: a program started
by another Windows program gets CrossOver's per-process package and its own name in the app
switcher, where one started directly is just "wine". (`open -a CrossOver <exe>`
also works but opens CrossOver, and its trial reminder dialog swallows launches while showing.)

### 2. The listener on the Mac

```bash
git clone https://github.com/Doll-Eye/SpeechBridge.git
cd SpeechBridge/SpeechBridge/listener
./build.sh          # builds /Applications/SpeechBridge Listener.app
./login-item.sh install   # a LaunchAgent keeps it running, at login too
```

Open the app once and allow it to control VoiceOver when asked. Its log is in
`~/Library/Application Support/SpeechBridge/logs/`; every line it speaks is written there,
which is how you check a silent game without ears. The build targets macOS 14 or newer.

### 3. The stand-ins in the bottle

`SpeechBridge/setup-app/build.sh` builds **/Applications/SpeechBridge Setup.app**, a
self-contained copy of the installer and every DLL. Open it after installing any game and
after a Steam "verify integrity" (which puts a game's original speech plugins back). It:

- replaces `nvdaControllerClient*.dll`, `WindowsTTS.dll` under every game in
  `steamapps/common` with the stand-ins, keeping the originals as `.orig`;
- puts the SAPI engine, the SpVoice stand-in, SAAPI64 and the ZDSR client into
  `C:\windows\system32` (and 32-bit copies into `syswow64`), and `sbsay.exe` into
  `C:\SpeechBridge`;
- installs the Bluetooth-rumble shim beside `steam.exe`;
- and tells you which one-off registrations are still missing.

The one-off registrations must run **inside the bottle** once (with the applet, or CrossOver's
Run Command):

```
regsvr32 C:\windows\system32\SapiBridge64.dll
C:\windows\syswow64\regsvr32 C:\windows\syswow64\SapiBridge32.dll
regsvr32 C:\windows\system32\SpVoiceBridge64.dll
C:\windows\syswow64\regsvr32 C:\windows\syswow64\SpVoiceBridge32.dll
reg add HKLM\SOFTWARE\WOW6432Node\zhiduo\zdsr /v Path /t REG_SZ /d C:\SpeechBridge /f
reg add HKCU\Software\Wine\AppDefaults\steam.exe\DllOverrides /v cfgmgr32 /t REG_SZ /d native,builtin /f
reg import C:\SpeechBridge\renpy.reg
```

The SAPI engine registers itself as the default voice with two tokens, one with Language
exactly `409` (Diablo IV insists) and one `809`. Wine reads the default voice from
`DefaultDefaultTokenId`, which a fresh bottle does not have; the registration writes it.

### 4. Steam Speak, for Big Picture

```bash
cd "Steam Speak" && ./build.sh     # needs Xcode; installs /Applications/Steam Speak.app
```

Open it, choose **Restart Steam so it can be read**. It writes an empty
`.cef-enable-remote-debugging` file into Steam's directory (Mac client and every bottle
holding a `steam.exe`), which makes Steam expose its Chromium debugging port on
`localhost:8080`, and it reads whichever Big Picture is there. Steam updates delete that file;
the app tells you and offers the restart again. Its README explains why VoiceOver cannot be
pinned to Big Picture and what was measured trying.

## Game by game

### Diablo IV

Diablo IV has its own screen reader; it wants a SAPI voice and, with "third party reader" on,
speaks through Tolk. What it took, in order:

1. In `Documents\Diablo IV\LocalPrefs.txt` (the bottle's Documents is your real Documents
   folder): `UseScreenReader "1"`, `UseThirdPartyReader "1"`, and `SkipIntroMovie "1"`,
   `PlayInBackground "1"`, `LimitBackgroundFPS "0"`, `DisplayModeWindowMode "1"` for comfort.
2. The first run shows a "Screen Reader Enable / Disable" prompt that nothing reads. Press
   Return; Enable is highlighted.
3. **Every DLL the game loads must live in `C:\windows\system32` or `syswow64`.** The game's
   protection layer (`diablo_iv_loader.dll`) ends the process about 123 seconds after any DLL
   is loaded from anywhere else, with nothing in the game's log. Ten crashes were spent on
   that. Nothing of SpeechBridge goes in the game folder; the Setup app removes an old copy if
   it finds one.
4. Wine's own SpVoice cannot render into the stream the game supplies and fails every
   Speak; the SpVoice stand-in replaces the class (CLSID `{96749377-…}`) and forwards the text.
5. Over Bluetooth, the game's native DualSense support fails under Wine. Turn **Steam Input**
   on for the game with the Xbox "Gamepad" template; the game then sees an XInput pad.

The game's own log is `FenrisDebug.txt` in the game folder (`[ScreenReader]` lines).

### Hades II

Three Thunderstore mods, installed by hand because r2modman does not run here: Lirin's
**Blind Accessibility** and **Hades 2 TOLk Compatibility**, FlatArther's **HadesIIAccess**,
plus their dependencies (Hell2Modding, LuaENVY-ENVY, SGG_Modding's ENVY, Chalk, ReLoad, SJSON,
ModUtil, DemonDaemon). Layout, all inside the game's `Ship` folder:

- Hell2Modding's `d3d12.dll` beside `Hades2.exe`;
- each package unpacked into `ReturnOfModding/plugins/<Team-Name>/`;
- HadesIIAccess's `plugins_data` folder moved to `ReturnOfModding/plugins_data/FlatArther-HadesIIAccess/`.

Wine loads a DLL from a program's folder only when told to, so once inside the bottle:
`reg add HKCU\Software\Wine\AppDefaults\Hades2.exe\DllOverrides /v d3d12 /t REG_SZ /d native,builtin /f`.
The loader finds the real d3d12 by path, so D3DMetal is untouched. Hell2Modding has Tolk built
in and picks the SAAPI64 stand-in on its own. To play unmodded, rename `d3d12.dll`.

### Fallout 4

Game version 1.11.240 needs **F4SE 0.7.9**; also **Address Library for F4SE Plugins** (only
`version-1-11-240-0.bin` is needed), **Extended Dialogue Interface**, **Mod Configuration
Menu** and **Fallout 4 Access** by alex19EP. All are Nexus downloads, which need a Nexus
account. Put F4SE's loader, DLL and `Data\Scripts` in the game folder and the mods' `Data`
contents in `Data`. Then:

- `Documents\My Games\Fallout4\Fallout4Custom.ini` with `[Archive]`, `bInvalidateOlderFiles=1`,
  `sResourceDataDirsFinal=` (empty), so loose files load;
- `AppData\Local\Fallout4\plugins.txt` with `*XDI.esm` and `*fallout4access.esp`;
- sound: Wine's own XAudio2 gives static in this game. Copy Microsoft's XAudio2 2.7, XAPOFX 1.5,
  XACT 3.7 and X3DAudio 1.7 from the DirectX June 2010 cabinets Steam ships (under
  `Steamworks Shared/_CommonRedist/DirectX/Jun2010`, unpack with `cabextract`) into
  `system32`/`syswow64`, and give `Fallout4.exe` `native` overrides for `xaudio2_7`,
  `x3daudio1_7`, `xapofx1_5`, `xactengine3_7` (the Setup app's installer does the copy);
- controller: force Steam Input on for the game (Big Picture, or `UseSteamControllerConfig "2"`
  under the top-level `apps` block of `localconfig.vdf`), as for Diablo IV;
- no Steam launch option: F4SE 0.7.9 refuses the launcher path Steam appends through
  `%command%` ("too many free args"), so copy `f4se_loader.exe` over `Fallout4Launcher.exe`
  (keep the original as `.orig`); the Setup app re-applies this after a Steam verify.

Fallout 4 Access speaks through the **Prism** library, which tries screen readers first. Under
Wine every route it prefers is closed (NVDA over RPC, JAWS over COM, OneCore missing, SAPI
probed on a thread without COM). Its ZDSR backend needs only a registry key and a client DLL,
so SpeechBridge provides `ZDSRAPI_x64.dll`; the mod logs `Prism initialized, speaking through
ZDSR`. Anything else built on Prism will take the same door.

### Final Fantasy VI Pixel Remaster

BlindGuyNW's **FF6 Screen Reader** (GitHub, v2.0) on **MelonLoader 0.7.3**. Unpack
`MelonLoader.x64.zip` into the game folder (`version.dll` and `MelonLoader/`), the mod's
`FFVI_ScreenReader.dll` into `Mods`, and its `Tolk.dll` and `nvdaControllerClient64.dll` beside
the game (then run the Setup app, which swaps in the stand-in). Inside the bottle, once:
`reg add "HKCU\Software\Wine\AppDefaults\FINAL FANTASY VI.exe\DllOverrides" /v version /t REG_SZ /d native,builtin /f`.
The first launch takes several minutes: MelonLoader downloads and installs the .NET 6
runtime in the bottle and generates the game's assemblies, all on its own. Launch from Steam;
Steam's first launch shows an "On-Screen Keyboard" notice that wants an OK. The same recipe
should serve the other Pixel Remasters and their mods by bladestorm360.

### Cyberpunk 2077

**Cyberpunk Access** by Ludark (Nexus) with its requirements: Cyber TTS Engine, RED4ext,
redscript, Codeware, TweakXL, ArchiveXL, Input Loader, Mod Settings (all Nexus) and Audioware
1.9.4 from GitHub (the version the mod names). Each unpacks over the game folder; Cyberpunk
Access's archive has a top folder whose contents go in the game root. RED4ext loads through
`winmm.dll`, so once inside the bottle:
`reg add HKCU\Software\Wine\AppDefaults\Cyberpunk2077.exe\DllOverrides /v winmm /t REG_SZ /d native,builtin /f`.
Cyber TTS Engine speaks through Prism, so the ZDSR stand-in from the Fallout 4 section carries
it. Launch from Steam; the game's user agreement is read aloud with Decline and Accept. This
needs the Windows build of the game in the bottle; the native macOS version cannot load
these mods.

### Stardew Valley

Install SMAPI by hand (unzip its `install.dat` into the game folder, copy
`StardewModdingAPI.deps.json`), then the **Stardew Access** mod and its dependencies
(Project Fluent, Kokoro) into `Mods`. Stardew Access ships its own `SAAPI64.dll`; the Setup app
replaces that one with the stand-in. Steam launch option:
`"C:\Program Files (x86)\Steam\steamapps\common\Stardew Valley\StardewModdingAPI.exe" %command%`.

### Bits & Bops, Rhythm Doctor, Blind Drive and other UAP games

These ship `nvdaControllerClient.dll` and `WindowsTTS.dll`. The Setup app replaces both; the
WinRT `WindowsTTS.dll` crashes under Wine, the stand-in does not. Nothing else to do.

### Ren'Py games (Slay the Princess)

Ren'Py's self-voicing runs an external command when set. The registration above adds
`RENPY_TTS_COMMAND=C:\SpeechBridge\sbsay.exe` to the bottle's environment. Turn self-voicing
on in the game with `v`.

### Electron games that use aria-live (Periphery Synthetic EP)

The listener has a web reader on port 9223: it attaches to a Chromium page, watches
`aria-live` regions and focus, and speaks the changes. Steam launch option:
`%command% --remote-debugging-port=9223`.

### Steam launch options without the Steam window

Launch options live in `Steam\userdata\<your id>\config\localconfig.vdf`, under
`Software\Valve\Steam\apps\<app id>`, as `"LaunchOptions"` — editable with Steam closed
(quotes as `\"`, backslashes doubled). Steam re-reads the file on start.

### Rumble over Bluetooth

Over Bluetooth a DualSense rumbled in nothing until this was found: Steam's controller code
(SDL 3) asks Windows' device manager for the pad's parent device to learn its bus, and Wine's
`CM_Get_Parent` has no answer, so every pad counts as wired and gets USB-format reports the pad
ignores. `SpeechBridge/BusType/cfgmgr32.dll` sits beside `steam.exe`, passes every call through
to Wine's cfgmgr32 and answers that one from the registry. The override registered above makes
Wine load it. Steam's controller log then shows the mapping GUID starting `0500` (Bluetooth)
instead of `0300`.

## Traps, briefly

Each is told in full in the engineering logs; here is the list to check against.

- **Launching from an AI's shell** poisons the bottle for the session (above).
- **Diablo IV kills itself two minutes after a foreign DLL loads.** system32 only.
- **A SAPI voice token's Language must be exactly `409`** for Diablo IV; `809;409` fails as "no voice".
- **`cscript` SAPI tests hang** in `GetVoices` under Wine; use a compiled test.
- **Wine loads its own DLL over a native one in the program folder** unless an override says
  `native,builtin`. This is true of proxies (`d3d12.dll` loaders) and shims alike.
- **Wine's DualSense "report fixup" is input-only** and switches itself off at the first
  feature report; it never helps rumble.
- **Chrome's download manager stalls on large files while Steam is downloading**; a page can
  fetch the file itself and save it through a button clicked as a real click (a
  script-started save is blocked as an automatic download).
- **`@Published`-style traps in the Mac apps**, Big Picture's Space, and everything about
  pinning VoiceOver to Steam are in Steam Speak's notes.
- **The listener must be built for macOS 14** (`-target arm64-apple-macos14.0`) or Launch
  Services refuses to open it.
- **The Setup app must carry its own copy of everything**; an applet that reads from
  `~/Desktop` blocks on a privacy prompt no one sees.

## For AIs and engineers

The two engineering logs are the primary sources; they record what was measured, what failed
and why, with dates: [SpeechBridge/README.md](SpeechBridge/README.md) for everything in the
bottle, and [Steam Speak/NOTES.md](Steam%20Speak/NOTES.md) plus
[Steam Speak/README.md](Steam%20Speak/README.md) for Big Picture and VoiceOver. Working rules
that held up:

- **Instrument before reasoning.** Every stand-in logs to `C:\SpeechBridge\*.log`; the
  listener logs every line it speaks; `cxstart --debugmsg +hid --cx-log <file> '<exe>'` from
  the applet gives a Wine trace of one program; `screencapture -x` from a shell shows the game
  when computer-use tools cannot target Wine windows.
- **Test the interface, not the game.** `SapiBridge/sapitest.c`, `Tolk/tolktest.c`,
  `tools/prism/prismtest.c` and `tools/rumble/hidrumble.c` each replay exactly the calls a
  game or library makes, so a failure is placed in one layer.
- **Measure the hardware.** `tools/rumble/motion.swift` reads the pad's own gyro from the Mac,
  so a rumble pulse is a number, not a feeling.
- **Read the source when it is open.** Prism, SDL, Wine, Hell2Modding and hidapi are all on
  GitHub; the SDL bus check and Prism's SAPI probe were both settled by reading, not guessing.
- **Keep the owner in the loop only where only they can act:** ears, a Nexus login, a
  controller in the hand. Everything else, verify from the log.

## Credits

Tolk (Davy Kager), NVDA and its controller client, Prism (Ethin Probst), Hell2Modding,
ReturnOfModding, Lirin and erumi321 (Hades II Blind Accessibility), FlatArther
(HadesIIAccess), F4SE, alex19EP (Fallout 4 Access), Stardew Access, SMAPI, Wine and
CodeWeavers' CrossOver, AWDLControl, and Blizzard for shipping a screen reader in Diablo IV.
The stand-ins reproduce interfaces only; see THIRD-PARTY.md.

MIT licence. Built by Doll-Eye with Claude, September 2026.
