# MPVTube

Lua/ASS on-screen controller for MPV 0.40+, targeting macOS, Linux and Windows.

## UI and behavior

- Target almost pixel-perfect YouTube desktop **player** UI/UX. Use supplied screenshots; for UI changes, inspect the embedded-browser reference: https://www.youtube.com/watch?v=CMB5GCexb84 (Learn Linux TV, chapters/captions). Reference repositories guide code, not design.
- Verify affected icons' outlines/sizes/centering, text, margins, hovers, active/disabled states, tooltips and transitions in narrow, wide and fullscreen layouts. Measure; report MPV limitations honestly.
- Keep the bottom 72 logical pixels a safe area: background left/right clicks, double clicks and holds cannot toggle playback, fullscreen or 2×. One outside left/right click closes menus without pausing; left-clicked controls retain their actions.
- Share drawing/hit geometry. Volume hover includes its slider; time capsules fit changing/hour-long timestamps and toggle elapsed/remaining without seeking. Held sliders update continuously through reversals and out-of-bounds movement.
- Match font family, CSS size and weight through `ui.draw.text_styles`; use bundled Roboto and its CSS-to-ASS conversion. Keep timer measurements consistent with the rendered weight.
- Match YouTube's keyboard feedback, chapters, auto-hide and hold-to-2× behavior. Mouse volume controls do not start central feedback.
- Menus reflect accepted MPV values, including external changes; observe canonical properties and refresh labels/checkmarks immediately. Plain rows, including Reset, share one text inset; reserve columns only for icons/checkmarks. Unavailable features have no fake actions.
- Keep hover previews fast: asynchronous generation, latest-position priority, bounded caching and graceful fallback.
- Reuse `ui.motion` easing/timings and `ui.draw` hover/toggle/spacing helpers. Match measured reference animations; retarget smoothly and stop scheduling settled transitions.
- Support embedded and dynamically added external subtitles. Preserve existing styles; retain customization and white outlined captions without a background. CC states follow track availability/visibility.
- Use native cursors, never overlays; pointer only with native OS support. Window modes reuse MPV's window and restore settings.

## Code

- Keep code simple, robust, reusable, with few files/lines; readability wins over compression. Use meaningful names and brief comments explaining modules, major blocks and non-obvious reasons.
- Keep one script package, `scripts/mpvtube/main.lua`, with cohesive `core/` and `ui/` modules loaded through `require`. Avoid needless splits, abstractions or dependencies.
- Prefer MPV APIs; keep commands out of drawing modules. Minimize polling/redraws; clean up timers, workers and temporary files. Preserve user configuration and unrelated edits.

## Documentation and checks

- Update `README.md` for setup, `docs/FEATURES.md` for every changed feature/native effect, `docs/DEVELOPMENT.md` for architecture/tests. Read relevant sections only. Explain steps, options, dependencies and limitations concisely for beginners.
- No em dashes in comments/docs; use commas, semicolons or periods, consistent with es_ES punctuation.
- Lua changes: `luac -p` affected files; `luajit tests/regression.lua`. Interaction changes: `python3 tests/integration.py` and screenshot review. Network checks: optional `python3 tests/online.py`. Run from root; generated artifacts stay in ignored `tests/output/`.
- Test behavior/edge cases: held sliders, resizing, missing metadata, external subtitles and audio-only media. Keep fixture generators in Git, generated media ignored. Report checks and limitations; geometry tests do not prove pixel identity. Skip redundant tests and code tests for docs-only edits.
