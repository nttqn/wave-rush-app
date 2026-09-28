# Promo video pipeline

This folder rebuilds `store/promo/wave-rush-promo-1920x1080.mp4` and `-1080x1920.mp4`. Those files are gitignored.

1. **Capture frames.** Apply a temporary, never-committed patch with two parts:
   - **Autopilot:** `?demo&level=N` flies `LevelBuilder.safePathYAt`.
   - **Lockstep stepping:** when `window.__waveCapture` is set, game time advances 1/30 s only when the recorder grants a `window.__waveAdvance` token.

   Then drive a `flutter build web` with Playwright at viewport 960x540 @2x and screenshot one JPEG per granted frame. Headless rendering is too slow for real-time capture (about 7 fps), so lockstep capture is what keeps the output smooth. Revert the patch afterwards with `git checkout`.
2. **Render the overlays:** `powershell -File make_overlays.ps1` draws the neon captions and cards using Segoe UI Black.
3. **Assemble:** `bash build.sh`. This needs a full ffmpeg build (BtbN win64 gpl-shared); put its path in `../ffmpeg/ffpath.txt` relative to this folder.

Captured segments: L3 0.5–4.5s, L9 5.0–9.5s, L5 6.0–9.0s and L12 5.5–9.5s, plus an editor stop-motion and the home menu. The music is `m_ig1.mp3` looped, with `m_win.mp3` on the end card.
