# Technical documentation

## Architecture

The prototype keeps game rules separate from the Flutter screen:

- `lib/engine.dart`: board model, CSP generator, shortest path, scoring, and DDA.
- `lib/main.dart`: lifecycle, input stream, game state, and responsive UI.
- `lib/hints.dart`: three-stage reachability-aware hints.
- `lib/telemetry.dart`: session input counters and recent frame timings.
- `lib/flowing_gradient.dart`: shared animation for selected path tiles.
- `lib/tile_sound*.dart`: platform-specific sound and haptic feedback.
- `lib/star_celebration.dart`: completion rating animation.

`InputProvider` exposes a broadcast `Stream<GameInputEvent>`. Touch, mouse, and
stylus gestures use the local provider. A future camera tracker can implement the
same interface and emit hover/select events without changing board logic.

## Game rules

START is initially selected. A move is valid when its tile is orthogonally
adjacent, unvisited, and divisible by the board divisor. Selecting the previous
tile backtracks. The generator reserves a legal route before assigning
distractors, then verifies reachability with breadth-first search.

Three stars require the shortest route and no invalid moves. Two stars allow a
route up to 1.5 times the shortest distance; other completions receive one.

## Difficulty and hints

DDA considers completion error rate, route efficiency, and time. It changes
level only after two completions and applies the result to the next board.

Hints progress after 12, 24, and 36 seconds without a valid move: rule reminder,
viable next moves, then one shortest next move. Dead ends suggest backtracking.

## Verification

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release
flutter build web --no-tree-shake-icons
```

Tests cover narrow screens, pointer modes, stream input, overlays, animations,
hints, invalid moves, DDA, and generated route properties.

## CI and release artifacts

GitHub Actions and Codemagic run quality checks, build an Android release APK,
and compile an unsigned iOS app. `math-game-unsigned.ipa` is an archive of the
unsigned Runner.app for inspection. It is not installable or App Store-ready.

A distributable IPA requires Apple Developer membership, a unique bundle ID,
an Apple distribution certificate, a matching provisioning profile, and a
signed `flutter build ipa --release` run. Keep signing secrets out of Git and
upload them to Codemagic's encrypted code-signing settings. See the official
[Codemagic Flutter guide](https://docs.codemagic.io/yaml-quick-start/building-a-flutter-app/).

## Known limitations

- Spatial mode currently simulates tracking with mouse hover and selection.
- Camera FPS/inference metrics need a camera-backed InputProvider.
- DDA thresholds still need evaluation with target users.
- Production IDs, signing, store metadata, icons, privacy declarations, and
  physical-device acceptance testing remain release work.
