# MPVTube

[![MPV Supported: 0.40+](https://img.shields.io/badge/MPV_Supported-0.40%2B-691F69)](https://mpv.io/installation/)
[![Style: YouTube-inspired](https://img.shields.io/badge/Style-YouTube--inspired-FF0033)](docs/FEATURES.md)

A YouTube-style on-screen controller for MPV, with rounded controls, chapters,
fast hover previews, subtitle customization, keyboard focus, advanced track controls and exports.
MPV handles playback; the skin needs no browser, account or icon font.

[Features and controls](docs/FEATURES.md) explains every feature and its effect
in MPV. [Development](docs/DEVELOPMENT.md) covers the code and tests.

## Install

### 1. Install MPV, the player that runs the skin

Use **MPV 0.40+ with Lua support**. Check with `mpv --version`.
MPV includes its Lua runtime; users do not need a separate Lua installation.
Get it from [MPV downloads](https://mpv.io/installation/), or run:

```sh
brew install mpv       # macOS with Homebrew
# Debian/Ubuntu: sudo apt install mpv
```

Optional helpers:

- **[FFmpeg](https://ffmpeg.org/download.html):** creates local-video previews and
  exports subtitle/audio tracks. Without it, timestamps and playback still work;
  extraction is unavailable. MPV has no general native extraction API.
- **[yt-dlp](https://github.com/yt-dlp/yt-dlp):** resolves YouTube URLs for MPV.
  It is separate software, not part of MPVTube. The
  [Homebrew MPV package](https://formulae.brew.sh/formula/mpv) includes both helpers;
  other packages may need them installed separately. Local playback needs no yt-dlp.

### 2. Find MPV's configuration folder

This is where MPV loads scripts, fonts and settings.

| Platform | Default folder |
| --- | --- |
| macOS / Linux | `~/.config/mpv/`, where `~` means your home folder |
| Windows | `%APPDATA%\mpv\`, paste into File Explorer |
| Windows portable | `portable_config\` beside `mpv.exe`, if present |

If you use `MPV_HOME`, `XDG_CONFIG_HOME` or `--config-dir`, use that folder instead.
See [MPV configuration paths](https://mpv.io/manual/stable/#files).
On macOS, Finder's **Go → Go to Folder** (`Cmd+Shift+G`) accepts the path above.
Create the folder if it does not exist yet.

### 3. Copy the skin and its fonts

Download/extract this project, then copy:

| From this project | Into your MPV configuration folder | Purpose |
| --- | --- | --- |
| Entire `scripts/mpvtube/` folder | `scripts/mpvtube/` | The controller; keep its subfolders intact |
| Four `.ttf` files in `fonts/` | `fonts/` | Roboto UI fonts, loaded by MPV without a system installation |
| `script-opts/mpvtube.conf`, optional | `script-opts/mpvtube.conf` | Skin settings; defaults work without this file |

Create missing folders. Keep existing fonts and your customized configuration
when upgrading. Copying only `main.lua` will not work.

```text
mpv/
├── mpv.conf
├── mpvtube-keys.json        # created by F1 when saving shortcuts
├── mpvtube-preferences.json # created by Settings when saving the animation choice
├── fonts/                  # four Roboto TTFs
├── script-opts/mpvtube.conf # optional skin settings
└── scripts/mpvtube/
    ├── main.lua
    ├── core/               # playback and input
    └── ui/                 # layout and drawing
```

### 4. Disable the built-in bar to avoid overlapping controls

Open/create `mpv.conf` in that folder. Replace any `osc=yes` line with:

```ini
osc=no
```

**OSC** means *on-screen controller*, MPV's built-in playback bar.
`osc=no` turns it off so MPVTube supplies the controls; `osc=yes` restores it.
MPVTube also disables the stock bar automatically, but this line records your choice.
Move other controller scripts, such as uosc, ModernZ or `youtube-ui.lua`, out of
`scripts`. `osc=no` does not disable those. Restart MPV to load the new files.

### 5. Open media and check the controls

Move the mouse over a video. Try play/pause, the expanding volume slider,
elapsed/remaining time, timeline dragging and the gear menu. Empty space in the
bottom strip should leave playback unchanged. Check key feedback and smooth
hover/menu transitions, then resize the window and press `f` for fullscreen.
Controls hide after 0.7 seconds during playback and stay visible while paused.

To try the skin **without installing**, run from this project's folder:

```sh
mpv --no-config --osd-fonts-dir=./fonts --script=./scripts/mpvtube "/path/to/video.mp4"
```

`--no-config` ignores your usual settings/scripts for this launch; `--script`
loads this skin; `--osd-fonts-dir` supplies its fonts. Replace the path with yours.
On Windows, use `mpv.exe` and a Windows path.

Audio works too. `--force-window=yes` requests a window when there is no video:

```sh
mpv --force-window=yes "/path/to/song.mp3"
```

Remote playback requires the appropriate URL helper and network access.

## Quick controls

| Key / gesture | Action |
| --- | --- |
| Space, click video | Play/pause |
| Hold left click on playing video | Temporary 2×, release restores speed |
| Left/Right; Shift; Ctrl; Ctrl+Alt | Seek ±10 / ±3 / ±60 / ±300 seconds |
| Up/Down, wheel; `m` | Volume, up to 200% by default; mute |
| `n` / `p`; `[` / `]` | Next/previous video; previous/next chapter |
| `v` / `Alt+v`; `b` / `B` (Shift+b) | Next/previous subtitles; next/previous audio |
| `c`; `Alt+c`; `u`; `C` (Shift+c); `a` | Toggle captions; subtitle selector; clean styling; chapters; audio selector |
| `g` / `h`; `j` / `k` | Subtitles earlier/later; audio earlier/later, 50 ms |
| `f`; `i` | Fullscreen; mini player |
| Tab / Shift+Tab; Enter | Focus controls; activate |
| Esc; Backspace | Step back; clear menus/focus and restore playback keys |
| Ctrl+P; F1 | Native MPV tools; categorized shortcut editor |

Letters are lowercase unless Shift is stated. Settings, CC and Audio open their
respective views when no menu is visible; any of these three closes an open view.
MPV Menu sits at the top right, beside information. **Settings → Export tracks** extracts tracks; **More controls**
groups chapter/track navigation, synchronization and native tools.
[Features and controls](docs/FEATURES.md) documents all keys, settings and native effects.

## Customize and troubleshoot

Edit `script-opts/mpvtube.conf` and restart MPV. The
[supplied file](script-opts/mpvtube.conf) explains **every option and default**,
including seek, volume/sync steps, amplification, panel sizes and preview cache.
For toggles, `yes` enables and `no` disables. Keep player settings in `mpv.conf`.

Animations are on by default. **Settings → Animations** switches them off/on
immediately and remembers your choice in `mpvtube-preferences.json`, beside
`mpv.conf`. The bar now auto-hides after 0.7 seconds of inactivity.

For configuration without using the UI toggle, edit `script-opts/mpvtube.conf`:

```ini
animations=no
hide_timeout=0.7
```

Set `animations=yes` to restore transitions. Saved UI preferences take precedence;
delete `mpvtube-preferences.json` to return to `.conf` defaults.
With `no`, controls, hovers, tooltips and feedback appear immediately; previews
skip any configured waiting period.
Video taps act on release in both modes. Existing installations with
`hide_timeout=3` should change that line to `0.7`, then restart MPV.

By default, **MPVTube owns the keyboard**, blocking native/input.conf fallbacks:
unassigned keys do nothing. F1 edits skin keys, checks conflicts and saves to
`mpvtube-keys.json` beside `mpv.conf`. Current/new keys are plain information.
Choose **Record new shortcut**, press a key, then **Save changes** or Enter.
Errors appear red in the fixed status card; successful saves appear green.
**Reset all shortcuts** restores the built-in keys after confirmation, including
unassigned keys. **Input diagnostics** is a read-only troubleshooting tool: inspect
which command and script receive an input when it behaves unexpectedly.
Only choose `shortcut_policy=compatible` if you want native/input.conf bindings;
`exclusive` is a legacy alias of the default `mpvtube` policy. `keyboard=no`
releases general keyboard ownership.

`thumbnails=auto` prefers [thumbfast](https://github.com/po5/thumbfast), otherwise
FFmpeg for local videos. Remote previews need thumbfast with network support.
Install `thumbfast.lua` beside the `mpvtube` folder and follow its setup guide.
`thumbnails=no` keeps timestamps only. If `ffmpeg -version` fails despite an
installation, set `ffmpeg_path` to the executable's full path, without quotes.

| Problem | Check |
| --- | --- |
| No controls | MPV version, active config folder, `scripts/mpvtube/main.lua`; move the mouse |
| Two bars | `osc=no`, other controller scripts, restart MPV |
| No preview image | Local video with known duration, FFmpeg path or thumbfast availability |
| Text/size differs | Bundled fonts, `font=Roboto`, `scale`; a custom `osd-fonts-dir` must include the TTFs |
| Unexpected shortcut | F1 shows owned/effective keys; Backspace clears UI focus; check `shortcut_policy` and competing scripts |
| Cannot export | Local source, supported codec, FFmpeg path, existing output file; check export status/log |
| Cannot seek | Source must be seekable; live streams need a DVR window |
| YouTube URL fails | yt-dlp availability and MPV's log; remote access can fail independently of the skin |

Run `mpv --log-file=mpvtube.log "/path/to/video.mp4"` to record startup errors.
Look for `MPVTube loaded` or an `[mpvtube]` error.

## Uninstall and scope

Close MPV, remove `scripts/mpvtube/` and its optional settings file, change
`osc=no` back to `osc=yes`, then restart. Remove the four Roboto TTFs if unused.
Remove `mpvtube-keys.json` if you do not want to retain saved assignments.
Remove `mpvtube-preferences.json` to discard saved UI choices.
Separately installed helpers can remain.

The skin retains a YouTube-inspired visual style, with native MPV window modes and an
in-player chapter list. It has no accounts, recommendations, casting or streaming
resolution selector. Font rendering, preview corners and window placement depend on native libraries
and the operating system. Native testing currently covers macOS with MPV 0.41;
Linux/Windows need platform verification.

Source: [MIT](LICENSE). Bundled fonts: [Apache 2.0](LICENSE-Roboto.txt).
MPVTube is an independent project with its own controls and behavior.
