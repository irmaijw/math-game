# Spatial Math Grid

Move from START to FINISH through orthogonally adjacent multiples of the displayed divisor. START is already selected. Select the previous tile to backtrack. Touch mode supports taps, mouse clicks, and stylus taps; Spatial demo also supports mouse hover and long-press selection. Camera input is not yet integrated.

This repository is a capstone prototype. Android and web builds are usable for
demonstration. iOS source compiles without signing, but producing an installable
IPA still requires Apple Developer credentials and a production bundle ID.

See [technical documentation](docs/TECHNICAL.md) for the architecture, rules,
verification commands, CI artifacts, and remaining release requirements.

## Board generation

The constructive CSP generator in lib/engine.dart reserves a random, non-repeating right/down route from START to FINISH. Route tiles receive positive multiples of the divisor. One random off-route tile is reserved as a non-multiple distractor; other off-route tiles receive non-multiples or optional legal multiples (27% chance). Breadth-first search verifies reachability before returning the board.

This guarantees a solvable route and distractors. Supported sizes are 4 through 6 and divisors are 2 through 6; invalid inputs throw ArgumentError. These constructed boards have a shortest route of 2 * (size - 1) moves. The generator does not currently create longer winding solutions.

## Show shortest path

Show shortest path highlights a minimum-move START-to-FINISH route and lists its ordered (row, column) coordinates, starting at 1. The full solution is shown even when you have already moved. Showing it does not change your selections or score. Hide shortest path, Restart, and New puzzle clear the display.

Board.shortestPath() uses breadth-first search and parent reconstruction, returning both endpoints or null if unreachable. It returns one route when several shortest solutions exist. Optional from and blocked arguments support searching from a current tile without revisiting blocked tiles.

## Run and verify

    flutter pub get
    flutter run
    flutter test
    flutter analyze

GitHub Actions runs these checks on pushes and pull requests, then builds an
Android APK and unsigned iOS artifact. `codemagic.yaml` provides an equivalent
macOS workflow for connecting this repository to Codemagic.

Tests cover 1,500 boards across every supported size/divisor combination, distractors, shortest paths, detours, blocked/unreachable routes, mouse/stylus puzzle completion, touch selection, hover, long press, solution visibility, restart/new-board clearing, and a 320-pixel-wide phone layout.

## InputProvider and input modes

GameScreen accepts an optional inputProvider. It subscribes to that provider's Dart stream and cancels the subscription when disposed; the caller retains ownership of an injected provider. Without one, it uses LocalInputProvider. Local touch/mouse/stylus gestures remain available with an external provider connected.

In Spatial demo, hover frames update the targeted tile without committing a move. An out-of-board hover index clears the target. Mouse enter, hover, and exit produce these stream events. Touch mode ignores hover frames. Selection events commit legal moves or backtrack. Switching modes clears the target and preserves the selected path. A real camera tracking provider still needs integration.

## Dynamic Difficulty Adjustment

The game starts at level 2: a 5 by 5 board with multiples of 3. Level 1 uses 4 by 4; levels 2 through 4 use 5 by 5; level 5 uses 6 by 6. Divisors increase from 2 through 6 with the level.

Completed puzzles contribute error rate, final-path efficiency, and elapsed seconds. DDA averages up to three recent results and requires at least two before changing level. It raises the level when mean error rate is below 15%, efficiency exceeds 85%, and time is below 80 seconds. It lowers the level when mean error rate exceeds 45%, efficiency is below 55%, or time exceeds 120 seconds. Levels stay within 1 through 5; a change clears the performance window. The adjustment applies to the next generated puzzle, preserving the current board.

These thresholds are prototype settings and still need evaluation with target users. Automated tests verify stream input, mode switching, difficulty increase/decrease, bounds, and application of a new divisor after completed puzzles.

## Tile feedback

Only selected path tiles show RGB animation. They sample one board-wide gradient moving diagonally on a five-second loop, so colors flow coherently between tiles instead of rotating separately. Unselected tiles have a static fill. Press/release also animates scale and shadow. A shared controller repaints the tile backgrounds without rebuilding the screen each frame. Tiles are borderless circles. Selected path tiles share the RGB flow and checkmarks; hints and hover use icons, and shortest-solution tiles show step numbers. Game controls are circular with readable labels. The app-bar speaker button toggles click feedback. Chrome synthesizes random piano-like tones from the C-major pentatonic scale, avoiding consecutive repeated notes. Each note uses stable pitch, three decaying harmonics, and a quick attack through Web Audio; native platforms use the system click and selection haptic. Browser audio starts on a user click. No audio files or package downloads are needed.

## Developer telemetry

Use the bug icon in the app bar to toggle a floating read-only overlay. Pointer input passes through the panel so it does not block game controls or page scrolling. It shows the current and next difficulty levels, input mode, hover/selection indices, total input/hover/selection events, stream dispatch latency when timestamps are provided, mean build and raster duration over the last 60 measured frames, moves versus optimal distance, errors, hints, hint stage, elapsed time, and stalled time. Input totals cover the screen session. Flutter frame timings may be unavailable on some platforms and are shown as N/A until measured. Camera FPS/inference are explicitly unavailable until camera tracking integration. Frame timing callbacks and input subscriptions are removed on disposal.

## Progressive hints and invalid feedback

After 12 seconds without a successful move, hint stage 1 reminds the player of the rules. At 24 seconds, stage 2 highlights unvisited legal neighbors that can still reach FINISH. At 36 seconds, stage 3 highlights one shortest remaining step with its row, column, and number. Hint presses advance the same stages manually, capped at stage 3. A dead end suggests the previous tile for backtracking. A successful move or backtrack resets the stages; invalid attempts and hover do not count as progress. Showing the full solution suppresses automatic hints. Restart and New puzzle clear the hint state. Hints do not change the existing star-rating rules.

Invalid moves show a specific reason (nonadjacent, wrong multiple, or already visited), briefly color the attempted tile red, and display an X. Chrome plays a lower descending tone; native platforms use an alert and medium haptic. Valid selections use the piano-like tone and finishing uses a brighter note. The speaker toggle mutes all these sounds.

## Star celebration

Completion displays the earned rating near the top of the screen with staggered star pop animations and a short confetti burst. Three stars require an optimal final path and zero invalid moves; two stars allow a final path at most 1.5 times optimal; longer paths receive one star. Restart/New puzzle reset the celebration. Tests cover all three ratings and animation completion.
