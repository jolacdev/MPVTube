# Features and controls

MPVTube controls an existing MPV session. MPV decodes media, loads files/streams
and manages the native window. This guide covers default behavior; see the
[README](../README.md) for installation and the
[configuration file](../script-opts/mpvtube.conf) for every skin option.

## Playback and sound

| Control | Effect in MPV |
| --- | --- |
| Play button, video click, `Space` / `k` | Pause/resume |
| Hold left click on playing video for 0.35 seconds | Temporary 2×; release restores the previous speed without pausing |
| Speaker hover/slider, Up/Down, wheel outside menus | Volume 0–100%; slider/wheel unmutes, keys preserve mute |
| Speaker button / `m` | Toggle mute while remembering volume |
| Time capsule | Toggle elapsed/negative remaining time; total stays visible, no seek |
| Timeline click/drag | Seek; release commits the exact chosen position |
| Left/Right; `j`/`l` | Seek ±5 seconds; ±10 seconds |
| `0`–`9` | Jump to 0%–90% of the file or DVR window |
| `,` / `.` | Pause and step one frame backward/forward |

Holding a slider changes that slider. Video 2× holds end on release, pause,
pointer exit or file change; later speed changes by another action are preserved.
`video_click=no` disables single-click playback and 2× holds; double-click
fullscreen remains available. Pending clicks are cancelled on file changes.

The **bottom 72 logical pixels are a safe area**: empty spaces/margins consume
left/right clicks, double-clicks and holds without pausing, entering fullscreen or starting
2×. Buttons and the timeline retain priority.

The time capsule fits its current text with equal 16 px side padding, including
hour fields and the remaining-time sign. Clicking `0:30 / 10:00:00` shows
`-9:59:30 / 10:00:00`. This choice lasts for the session. Narrow windows shorten
or hide the display; unknown duration shows LIVE and cannot toggle remaining time.

Mouse volume, speaker and wheel changes stay in the bottom controls.
**Keyboard** volume/mute shows a centered speaker pulse and percentage near the
top. Decrease/increase uses the reference's small/large wave; mute shows a crossed
speaker and 0%. The bottom icon uses one wave at 1–50%, two above 50%, and a cross
when muted/zero. Play/pause uses a centered circular pulse. Arrow seeks show an
edge chevron and bold signed amount; rapid presses accumulate in one direction,
while reversing starts a new amount.

## Timeline and previews

| Indicator | Meaning |
| --- | --- |
| Red | Elapsed progress, or selected position while dragging |
| Lighter grey | MPV's temporary buffered media, possibly including earlier positions |
| Darker grey | Remaining timeline |
| Gaps | Chapter boundaries supplied by the media |
| Hover | Timestamp, optional chapter title and preview; hovering never seeks |

The grey buffer is not a permanent download. Seeking needs a seekable file with
known duration or a DVR/cache window from MPV. A live stream without that window
cannot be scrubbed.

`thumbnails=auto` prefers thumbfast, otherwise FFmpeg for local video with a known
duration. Remote images require thumbfast's network support. Missing/failed
providers leave timestamps usable; `thumbnails=no` disables images.
The timestamp and chapter label keep their position while images load or are
unavailable; thumbnails appear above them without moving the label.

The local fallback starts without a deliberate delay, samples every two seconds,
caches up to 64 images and warms at most two neighbors. Cached images appear
immediately, including while controls fade in. One asynchronous decoder limits
concurrency. Fast decoding can show a later frame than the sampled timestamp;
playback and seeks keep their normal precision. An uncached hover still needs
decoding, especially with
large files or slow storage. New positions take priority over unrelated prefetch;
a nearby cached image can remain visible while decoding. Video-track changes
invalidate old frames. Cache files are removed on file/track changes and normal
exit. `thumbnail_delay`, `thumbnail_interval` and `thumbnail_cache` let you trade
latency, precision and cache size.

## Speed and menus

**Settings → Playback speed** offers 0.25×–2× in 0.05× steps, minus/plus buttons,
and 1×, 1.25×, 1.5×, 2× presets. Dragging updates continuously through reversals
and movement outside the slider; release keeps the final rate. Up increases by
0.05×, Down decreases, Enter closes. Outside this menu, `<` / `>` changes by 0.25×.
These controls change playback, not the file.

Other menus use Up/Down to focus actionable rows, Enter to activate, wheel to
scroll, a back arrow to return, and `Esc`/an outside click to close. Track choices
return to Settings; playlist choices close; chapter/appearance choices remain
open for comparison. Pointer actions inside a sliding page wait until its
transition ends; bottom controls and keyboard navigation remain available.
One left or right click outside closes the menu, including empty bottom-bar space.
Left clicks on bottom controls still perform their action. Right clicks do not
activate controls; outside the safe area with menus closed, MPV's native binding applies.
Video-background dismissal does not pause.

## Window modes

Each mode uses the **same MPV window and playback session**.

| Mode | Button / key | Window effect |
| --- | --- | --- |
| Fullscreen | Fullscreen, `f`, video double-click | Toggle native fullscreen |
| Theater | Theater / `t` | Exit fullscreen; request a centered, bordered window without stay-on-top |
| Mini player | Mini player / `i` | Exit fullscreen; request a small, borderless window near bottom-right, kept on top |

Default target widths are 1280 and 480 MPV pixels. For 16:9 media, the requests
are 1280 × 720 and 480 × 270. MPV preserves the media aspect ratio; DPI and the
window manager can affect the resulting size/placement. Theater can shrink an
already larger window. Configure `theater_width` / `pip_width` to change targets.

Toggle the same mode again to restore saved size, border, stay-on-top and sizing/
placement options. Switching directly between theater and mini player retains
the original normal-window snapshot. Entering fullscreen first restores these
settings and clears the mode. Restoring does not re-enter previous fullscreen.
Use `i` to leave mini player when its button no longer fits. `pip=no` / `theater=no`
disables that mode. See [MPV window options](https://mpv.io/manual/stable/#window).

## Chapters, playlists and timers

**Chapters:** metadata divides the timeline and supplies the current-title
capsule. Its list marks the current chapter and scrolls it into view. Selecting
one seeks to its start, **starts playback even if paused**, and keeps the list
open. Long titles truncate; compact windows hide the capsule. Wide fullscreen
can show a central up-arrow for chapters, or the playlist when no chapters exist.
This is an in-player list rather than YouTube's page sidebar/fullscreen drawer.

**Playlist:** open multiple files, such as `mpv "one.mp4" "two.mp4"`.
Settings → Playlist marks the current entry; selecting another preserves pause
state. Previous/next buttons appear when an entry exists and space permits;
`Shift+P` / `Shift+N` also navigate.

**Autoplay:** controls advance through the loaded playlist. Off sets
`keep-open=always`, normally pausing at each file end; On restores the previous
end-of-file policy. It does not fetch another online video. **Loop video** repeats
the current file and takes precedence over advancing. See
[MPV keep-open](https://mpv.io/manual/stable/#options-keep-open).

**Sleep timer:** Off, 10, 15, 20, 30, 45 or 60 minutes. It counts clock time,
including pauses and file changes. Expiry pauses playback with feedback and
leaves MPV/computer running. Off cancels; another duration restarts it.

**Video information:** read-only resolution, video codec, frame rate, audio codec
and duration, available in Settings or the top-right information button.
Fullscreen also shows the media title. `title=no` hides the top title/button;
the Settings entry remains.

## Tracks and audio files

| Control | Effect |
| --- | --- |
| Audio track | Select another loaded audio track/language |
| Video track | Select a loaded video track; page appears only with several tracks |
| Subtitles/CC | Select and show a track, or choose Off |
| Bottom CC / `c` | Toggle visibility; CC selects the first track if needed |

Titles/languages come from MPV; selected tracks have checkmarks. Off remembers
the selected subtitle track. CC is filled when visible, outlined when off, and
dimmed/non-actionable when unavailable. Add external `.srt`, `.vtt` or `.ass`
subtitles by dropping them onto MPV or using `sub-add`; menus update when tracks
are added/removed, including media without embedded subtitles.

Video tracks are loaded streams, not every YouTube resolution. The gear's HD
badge means at least 720 px high, 4K at least 2160; both are informational.

Audio-only media keeps playback, seeking, time, volume, speed and playlists.
Use `--force-window=yes` if MPV opens no window. Information shows **Audio only**;
CC needs an added subtitle track, and hover skips video thumbnails.

## Subtitle appearance

Open **Settings → Subtitles/CC → Options**. Changes apply immediately to MPV's
native text renderer, for both embedded and external captions.
Checkmarks and option labels follow the accepted setting, including changes made
through native MPV commands. Use Subtitles/CC → Off or the bottom CC button to hide captions.

| Option | Choices / purpose |
| --- | --- |
| Font family | Sans-serif, serif, monospace, cursive; system font resolution |
| Font/background color | White, yellow, green, cyan, blue, magenta, red, black |
| Font size | 50%, 75%, 100%, 150%, 200%, 300%, 400% of startup size |
| Font/background opacity | 0%, 25%, 50%, 75%, 100%; 0% background removes the visible box |
| Character edge | None, Drop shadow, Outline |
| Reset | Restore the settings captured when MPVTube started |

For white outlined captions without a box, choose White, 100% font opacity,
0% background opacity and Outline. Font opacity affects the fill, not its outline,
shadow or box. MPV has one backing layer; Drop shadow replaces the box. Separate
YouTube Window color and Raised/Depressed edge effects are not offered.
Bitmap/burned-in subtitles cannot be restyled as text. Changing appearance can
override authored ASS styles; Reset also restores the original override policy.

Startup subtitle styles are preserved. `raise_subtitles=yes` lifts ordinary
bottom captions above visible controls, then restores their position. Authored
layouts may position themselves. Appearance changes last for this session;
put native options in `mpv.conf` to keep them across launches, for example:

```ini
sub-color="#FFFFFFFF"
sub-border-style=outline-and-shadow
sub-border-color="#FF000000"
sub-border-size=1.65
sub-shadow-offset=0
```

This gives white text, a black outline and no box. Colors are alpha then RGB,
with `FF` fully opaque. See [MPV subtitle options](https://mpv.io/manual/stable/#subtitles).

## Appearance, responsiveness and motion

Bundled **Roboto** matches the player's fallback family and fullscreen titles.
Shared styles use 14 px Regular menus, 14 px Medium timers, about 13 px Medium
chapters/tooltips, 12 px headers, 18 px Black speed values, 19.25 px Regular
percentages, 20 px Bold titles and 24 px Bold seek labels. `font` changes UI text
separately from subtitle fonts; custom fonts/rasterization may alter appearance.

Pointer movement or controls reveal the UI. It hides after three seconds of
inactivity, but stays visible during pause, control hover, drags or menus.
Stable hovers show tooltips after 0.45 seconds; menus suppress tooltips.
Hover highlights share geometry: volume includes its slider, time/chapter follows
its capsule, right buttons use their slots. Disabled controls have no hover action.
CC/theater/fullscreen reflect actual state; opening menus rotates the gear 30°.
Autoplay uses a black play knob/white track when on, white pause/dim track when off.

Layout follows window size and DPI. Narrow windows shorten/hide time and extras;
compact **Expand/Close** replaces the time display with secondary controls.
The compact speaker has no expanding slider; use keys/wheel. Tall menus scroll.
The operating system's native cursor is retained, without cursor overlays.

Shared motion helpers retarget from the displayed value, avoiding jumps on
reversals. Hover, volume expansion, timeline, tooltips and switch knobs take
0.2 seconds; volume waves about 0.25, autoplay track 0.08, gear 0.1, compact arrow
0.3. Volume/play feedback pulses over one second; arrow feedback lasts about 1.2.
Menus fade over 0.1 seconds and slide/resize over 0.25, retaining edge margins.
Play/pause and CC glyphs switch immediately, as in the observed modern player.

`fade_duration=0.25` controls reveal; hiding takes 40% of that value.
`fade_duration=0` makes visibility instant without disabling other transitions.
Settled animations stop scheduling frames. Native window motion and bitmap
preview updates follow MPV/OS capabilities; decoding never waits for a UI fade.

## Settings, persistence and scope

| File | Purpose |
| --- | --- |
| `mpv.conf` | Player settings, `osc=no`, permanent subtitle style |
| `script-opts/mpvtube.conf` | Skin options, documented individually in the supplied file |
| `input.conf` | Custom keys; override normal skin shortcuts |

Restart after file edits. `keyboard=no` disables general skin remapping;
mouse/menu controls and MPV's own bindings remain. Public show/hide/toggle/menu
messages also work. A custom chapter key helps when its capsule does not fit:

```text
C script-message-to mpvtube menu chapters
```

Menus do not write configuration or edit media. Temporary window settings,
subtitle lifting and the autoplay override are restored on shutdown; the sleep
timer and pending input are cancelled. Native persistence options remain available.
MPV screenshots, subtitle delay and playback resumption have no dedicated skin menus.

MPVTube does not install helpers or download/translate subtitles. URL playback
uses separate yt-dlp; preview providers are optional. Accounts, recommendations,
casting, streaming quality selection and Ambient mode are outside this skin.
Native verification covers macOS/MPV 0.41; Linux/Windows still need testing.
