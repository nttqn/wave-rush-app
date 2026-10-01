# Wave Rush

Hold to rise, release to fall. You steer a neon arrow through zig-zag tunnels, spike caves and saw fields.
Built with Flutter. Android first, landscape only. The idea comes from "wave dash" style games, but all
code and art here are original, and the graphics are drawn in code. Music and most sound effects are files supplied by
the project owner; `tool/gen_audio.js` synthesizes the portal sound.

## Features
- 12 levels, from Easy to Insane. Each level's geometry is generated from a fixed seed, so it is the same on every device.
- Every level can be beaten. The generator first lays down a safe zig-zag path, then places every hazard
  away from it. The tests run `LevelSolver` on all levels to check this again.
- **Slide surfaces**: floors and ceilings (flat, or sloped up to 2.5:1) are safe. Diving into one diagonally just makes the wave slide along it. Only spikes, saws and the vertical side of a step kill. Tunnels are entered through sloped funnels, and small spikes on their walls keep them challenging.
- Speed portals (0.8x / 1x / 1.25x / 1.5x) and mini-wave portals, which give a steeper 63° flight and a smaller hitbox.
- Instant restarts, an attempt counter, a progress bar, and the best % saved for each level.
- Endless mode. Difficulty goes up with distance, and every run is a new random course.
- 8 wave skins, unlocked by beating levels.
- **Level editor** (CREATE): tap to place floor/ceiling points, spikes, saws and portals, and drag to scroll. It has undo and per-level settings (length, speed, colours, music). Test-play any time. **Verify** runs the solver: it either proves the level is beatable or marks the spot where no timing gets through with a red line. Beating your own level in a test run also verifies it. Verified levels can be shared as a text code (`WAVE1:…`, copied to the clipboard), and friends can import that code.
- Menu music, 6 in-game tracks (one picked at random per run and restarted with every attempt), a win jingle, and crash, click and back sound effects. Music and SFX have separate toggles.
- AdMob banner on the menus only, never during play. Interstitials only at natural breaks.
- The Android back button pauses during play. It never quits in the middle of an attempt.

## Run locally
```
flutter pub get
flutter run -d chrome     # web preview (ads are no-ops on web); Space / ↑ / W = hold
flutter test
```

## CI build (GitHub Actions)
`android/`, `ios/` and `web/` are not committed; CI regenerates them. Each push to `main` builds the Android APK/AAB, and an iOS build on a macOS runner (a signed `.ipa` once the Apple secrets are set, otherwise a compile check). Run the workflow manually with **upload_ios** ticked to send the `.ipa` to TestFlight. See CLAUDE.md for the iOS secrets. Secrets:
- `ADMOB_APP_ID` (optional): overrides the real AdMob App ID, which is already set in the workflow.
- `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`: release signing. These are optional;
  without them the build is debug-signed.

AdMob uses real IDs on both platforms. The Android App ID is in the workflow, the iOS App ID is in the `ADMOB_APP_ID_IOS` secret, and the real banner and interstitial unit IDs for both are in `lib/services/ads_service.dart`.

## Regenerating audio
```
node tool/gen_audio.js
```
