import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'engine.dart';
import 'tile_sound.dart';
import 'flowing_gradient.dart';
import 'circular_control.dart';
import 'hints.dart';
import 'telemetry.dart';
import 'star_celebration.dart';

void main() => runApp(const MathGameApp());

enum InputMode { touch, spatial }

enum InputKind { hover, select }

class GameInputEvent {
  final int index;
  final InputKind kind;
  const GameInputEvent(this.index, this.kind, {this.emittedAt});
  final DateTime? emittedAt;
}

abstract class InputProvider {
  Stream<GameInputEvent> get events;
  void dispose();
}

class LocalInputProvider implements InputProvider {
  final _controller = StreamController<GameInputEvent>.broadcast();
  @override
  Stream<GameInputEvent> get events => _controller.stream;
  void emit(GameInputEvent event) {
    if (!_controller.isClosed) {
      _controller.add(GameInputEvent(event.index, event.kind,
          emittedAt: event.emittedAt ?? DateTime.now()));
    }
  }

  @override
  void dispose() => _controller.close();
}

class MathGameApp extends StatelessWidget {
  const MathGameApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Spatial Math Grid',
        theme: ThemeData(
            useMaterial3: true, colorSchemeSeed: const Color(0xff4d70d3)),
        home: const GameScreen(),
      );
}

class GameScreen extends StatefulWidget {
  const GameScreen(
      {super.key, this.inputProvider, this.difficultyEngine, this.now});
  final DateTime Function()? now;

  /// The caller owns injected providers; the screen owns its local fallback.
  final InputProvider? inputProvider;
  final DifficultyEngine? difficultyEngine;
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  final generator = BoardGenerator();
  late final DifficultyEngine difficulty;
  late final InputProvider input;
  final localInput = LocalInputProvider();
  final tileSound = TileSound();
  final hintEngine = ProgressiveHints();
  final telemetry = GameTelemetry();
  int hintStage = 0;
  List<int> hintTargets = [];
  int? invalidTile;
  Timer? invalidTimer;
  DateTime _now() => widget.now?.call() ?? DateTime.now();
  int? pressed;
  bool soundEnabled = true;
  late Board board;
  late StreamSubscription<GameInputEvent> subscription;
  StreamSubscription<GameInputEvent>? localSubscription;
  late int boardLevel;
  late AnimationController celebration;
  late AnimationController gradientFlow;
  final List<int> path = [0];
  InputMode mode = InputMode.touch;
  int? hovered, hint;
  int errors = 0, stars = 0, hintsUsed = 0;
  bool debug = false;
  List<int>? solution;
  String message =
      'START is selected. Tap a multiple of 3 directly above, below, left, or right.';
  late DateTime started, lastInteraction;
  Timer? ticker;
  int elapsed = 0;

  @override
  void initState() {
    super.initState();
    difficulty = widget.difficultyEngine ?? DifficultyEngine();
    input = widget.inputProvider ?? localInput;
    board =
        generator.generate(size: difficulty.size, divisor: difficulty.divisor);
    boardLevel = difficulty.level;
    message =
        'START is selected. Tap a multiple of ${board.divisor} directly above, below, left, or right.';
    started = lastInteraction = _now();
    celebration = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    gradientFlow =
        AnimationController(vsync: this, duration: const Duration(seconds: 5))
          ..repeat();
    SchedulerBinding.instance.addTimingsCallback(telemetry.recordFrames);
    subscription = input.events.listen(_handleInput);
    if (input != localInput) {
      localSubscription = localInput.events.listen(_handleInput);
    }
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (stars > 0) {
        if (debug) setState(() {});
        return;
      }
      final now = _now();
      setState(() {
        elapsed = now.difference(started).inSeconds;
        final nextStage =
            (now.difference(lastInteraction).inSeconds ~/ 12).clamp(0, 3);
        if (nextStage > hintStage && solution == null) {
          _showHint(stage: nextStage);
        }
      });
    });
  }

  void _handleInput(GameInputEvent event) {
    if (!mounted || stars > 0) return;
    telemetry.inputEvents++;
    if (event.emittedAt != null) {
      telemetry.lastInputLatencyMs =
          DateTime.now().difference(event.emittedAt!).inMicroseconds / 1000;
    }
    if (event.kind == InputKind.hover) {
      telemetry.hoverFrames++;
      if (mode != InputMode.spatial) return;
      final next = event.index >= 0 && event.index < board.cells.length
          ? event.index
          : null;
      if (hovered != next) setState(() => hovered = next);
      return;
    }
    if (event.index < 0 || event.index >= board.cells.length) return;
    telemetry.selectionEvents++;
    setState(() {
      final current = path.last;
      if (path.length > 1 && event.index == path[path.length - 2]) {
        _clearHintProgress();
        if (soundEnabled) tileSound.play();
        path.removeLast();
        message = 'Moved back one block.';
        return;
      }
      if (!board.adjacent(current, event.index) ||
          !board.legal(event.index) ||
          path.contains(event.index)) {
        errors++;
        message = !board.adjacent(current, event.index)
            ? 'Invalid move! Choose a tile directly above, below, left, or right.'
            : !board.legal(event.index)
                ? 'Invalid move! ${board.cells[event.index].value} is not a multiple of ${board.divisor}.'
                : 'Invalid move! This tile is already visited. Tap the previous tile to backtrack.';
        invalidTile = event.index;
        invalidTimer?.cancel();
        invalidTimer = Timer(const Duration(milliseconds: 650), () {
          if (mounted) setState(() => invalidTile = null);
        });
        if (soundEnabled) tileSound.play(invalid: true);
        return;
      }
      _clearHintProgress();
      path.add(event.index);
      message = 'Good move!';
      if (soundEnabled) tileSound.play(celebration: event.index == board.goal);
      if (event.index == board.goal) {
        elapsed = _now().difference(started).inSeconds;
        final optimal = board.shortestDistance() ?? path.length - 1;
        stars =
            starsFor(moves: path.length - 1, optimal: optimal, errors: errors);
        difficulty.record(
            errors: errors,
            moves: path.length - 1,
            optimal: optimal,
            seconds: elapsed.toDouble());
        message = 'Puzzle solved! $stars star${stars == 1 ? '' : 's'} earned.';
        celebration.forward(from: 0);
      }
    });
  }

  void _clearHintProgress() {
    hintStage = 0;
    hint = null;
    hintTargets = [];
    lastInteraction = _now();
    invalidTimer?.cancel();
    invalidTile = null;
  }

  void _showHint({int? stage}) {
    if (stars > 0) return;
    final result = hintEngine.evaluate(board, path, stage ?? hintStage + 1);
    if (result.stage > hintStage) hintsUsed++;
    hintStage = result.stage;
    hintTargets = result.targets;
    hint = hintTargets.firstOrNull;
    message = result.message;
  }

  void _newBoard() {
    setState(() {
      board = generator.generate(
          size: difficulty.size, divisor: difficulty.divisor);
      boardLevel = difficulty.level;
      path
        ..clear()
        ..add(0);
      errors = stars = hintsUsed = elapsed = 0;
      hovered = hint = null;
      _clearHintProgress();
      solution = null;
      started = lastInteraction = _now();
      message = 'Find multiples of ${board.divisor} from START to FINISH.';
      celebration.reset();
    });
  }

  void _selectTile(int index) {
    if (stars > 0) return;
    localInput.emit(GameInputEvent(index, InputKind.select));
  }

  @override
  void dispose() {
    ticker?.cancel();
    invalidTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(telemetry.recordFrames);
    subscription.cancel();
    localSubscription?.cancel();
    localInput.dispose();
    tileSound.dispose();
    gradientFlow.dispose();
    celebration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(title: const Text('Spatial Math Grid'), actions: [
        IconButton(
            tooltip: soundEnabled ? 'Mute tile sounds' : 'Enable tile sounds',
            onPressed: () => setState(() => soundEnabled = !soundEnabled),
            icon: Icon(soundEnabled
                ? Icons.volume_up_outlined
                : Icons.volume_off_outlined)),
        IconButton(
            tooltip: 'Developer telemetry',
            onPressed: () => setState(() => debug = !debug),
            icon: const Icon(Icons.bug_report_outlined)),
      ]),
      body: Stack(children: [
        SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child:
                        ListView(padding: const EdgeInsets.all(16), children: [
                      Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Text('Select multiples of ${board.divisor}',
                                style: Theme.of(context).textTheme.titleLarge),
                            Wrap(spacing: 8, children: [
                              CircularControl(
                                  label: 'Touch',
                                  icon: Icons.touch_app,
                                  active: mode == InputMode.touch,
                                  onPressed: () => setState(() {
                                        mode = InputMode.touch;
                                        hovered = null;
                                      })),
                              CircularControl(
                                  label: 'Spatial demo',
                                  icon: Icons.pan_tool_alt,
                                  active: mode == InputMode.spatial,
                                  onPressed: () => setState(() {
                                        mode = InputMode.spatial;
                                        hovered = null;
                                      })),
                            ]),
                          ]),
                      const SizedBox(height: 12),
                      if (stars > 0)
                        StarCelebration(stars: stars, animation: celebration),
                      if (message.startsWith('Hint '))
                        Semantics(
                            liveRegion: true,
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xfffff3cd),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.lightbulb_rounded,
                                        color: Color(0xff624600), size: 26),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Text(message,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              height: 1.5,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xff382b00),
                                            ))),
                                  ]),
                            ))
                      else
                        Text(message,
                            style: TextStyle(
                                color: message.startsWith('Invalid')
                                    ? Colors.red.shade700
                                    : null)),
                      const SizedBox(height: 8),
                      Text(
                          'Difficulty level $boardLevel | ${board.size} × ${board.size} grid | Next puzzle: ${difficulty.size} × ${difficulty.size}, multiples of ${difficulty.divisor}'),
                      Text(
                          '3 stars: finish in ${board.shortestDistance()} moves with 0 invalid moves.'),
                      Text(
                          'Your path: ${path.length - 1} moves | Invalid moves: $errors'),
                      const SizedBox(height: 8),
                      Center(
                          child: CircularControl(
                              onPressed: () => setState(() {
                                    solution = solution == null
                                        ? board.shortestPath()
                                        : null;
                                    hint = null;
                                    hintTargets = [];
                                    hintStage = 0;
                                    lastInteraction = _now();
                                  }),
                              icon: Icons.route,
                              active: solution != null,
                              label: solution == null
                                  ? 'Show shortest path'
                                  : 'Hide shortest path')),
                      if (stars > 0 && stars < 3)
                        Text(
                          errors > 0
                              ? 'You made $errors invalid move${errors == 1 ? '' : 's'}. Restart and follow the shortest path without invalid moves for 3 stars.'
                              : 'Your final path used ${path.length - 1} moves; the shortest uses ${board.shortestDistance()}. Restart and follow the shortest path for 3 stars.',
                        ),
                      const SizedBox(height: 12),
                      Center(
                          child: ConstrainedBox(
                              constraints: BoxConstraints(
                                  maxWidth: min(width - 32, 580)),
                              child: AspectRatio(
                                  aspectRatio: 1,
                                  child: GridView.builder(
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: board.size,
                                            crossAxisSpacing: 5,
                                            mainAxisSpacing: 5),
                                    itemCount: board.cells.length,
                                    itemBuilder: (context, i) {
                                      final cell = board.cells[i];
                                      final selected = path.contains(i);
                                      final solutionStep =
                                          solution?.indexOf(i) ?? -1;
                                      final color = invalidTile == i
                                          ? const Color(0xffffb4ab)
                                          : selected
                                              ? const Color(0xff4b74cf)
                                              : solutionStep >= 0
                                                  ? const Color(0xffb4e7df)
                                                  : hintTargets.contains(i)
                                                      ? const Color(0xffffe083)
                                                      : hovered == i
                                                          ? const Color(
                                                              0xffb4e7df)
                                                          : Theme.of(context)
                                                              .colorScheme
                                                              .surfaceContainerHighest;
                                      return MouseRegion(
                                          onHover: (_) {
                                            if (mode == InputMode.spatial) {
                                              localInput.emit(GameInputEvent(
                                                  i, InputKind.hover));
                                            }
                                          },
                                          onExit: (_) {
                                            if (mode == InputMode.spatial) {
                                              localInput.emit(
                                                  const GameInputEvent(
                                                      -1, InputKind.hover));
                                            }
                                          },
                                          onEnter: (_) {
                                            if (mode == InputMode.spatial) {
                                              localInput.emit(GameInputEvent(
                                                  i, InputKind.hover));
                                            }
                                          },
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTapDown: (_) {
                                              if (stars == 0) {
                                                setState(() => pressed = i);
                                              }
                                            },
                                            onTapUp: (_) =>
                                                setState(() => pressed = null),
                                            onTapCancel: () =>
                                                setState(() => pressed = null),
                                            onTap: () => _selectTile(i),
                                            onLongPress: () {
                                              setState(() => pressed = null);
                                              if (mode == InputMode.spatial) {
                                                _selectTile(i);
                                              }
                                            },
                                            child: Semantics(
                                                key: ValueKey('tile-$i'),
                                                button: true,
                                                selected: selected,
                                                label:
                                                    '${cell.start ? 'Start' : cell.finish ? 'Finish' : 'Number'} ${cell.value}',
                                                child: AnimatedContainer(
                                                    duration: const Duration(
                                                        milliseconds: 220),
                                                    curve: Curves.easeOutCubic,
                                                    transformAlignment:
                                                        Alignment.center,
                                                    transform:
                                                        Matrix4.diagonal3Values(
                                                            pressed == i
                                                                ? .93
                                                                : 1,
                                                            pressed == i
                                                                ? .93
                                                                : 1,
                                                            1),
                                                    decoration: BoxDecoration(
                                                        color: color,
                                                        gradient: LinearGradient(
                                                            begin: pressed == i
                                                                ? Alignment
                                                                    .topRight
                                                                : Alignment
                                                                    .topLeft,
                                                            end: pressed == i
                                                                ? Alignment
                                                                    .bottomLeft
                                                                : Alignment
                                                                    .bottomRight,
                                                            colors: [
                                                              Color.lerp(
                                                                  color,
                                                                  Colors.white,
                                                                  pressed == i
                                                                      ? .08
                                                                      : .25)!,
                                                              Color.lerp(
                                                                  color,
                                                                  selected
                                                                      ? const Color(
                                                                          0xff663bc9)
                                                                      : Colors
                                                                          .black,
                                                                  selected
                                                                      ? .45
                                                                      : .08)!
                                                            ]),
                                                        boxShadow: [
                                                          BoxShadow(
                                                              color: color.withValues(
                                                                  alpha:
                                                                      pressed ==
                                                                              i
                                                                          ? .5
                                                                          : .24),
                                                              blurRadius:
                                                                  pressed == i
                                                                      ? 3
                                                                      : 7,
                                                              offset: Offset(
                                                                  0,
                                                                  pressed == i
                                                                      ? 1
                                                                      : 4))
                                                        ],
                                                        shape: BoxShape.circle),
                                                    child: FlowingGradient(
                                                        animation: gradientFlow,
                                                        color: color,
                                                        selected: selected &&
                                                            invalidTile != i,
                                                        index: i,
                                                        gridSize: board.size,
                                                        child: FittedBox(
                                                            fit: BoxFit
                                                                .scaleDown,
                                                            child: Column(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  if (invalidTile ==
                                                                      i)
                                                                    const Icon(
                                                                        Icons
                                                                            .close_rounded,
                                                                        size:
                                                                            18,
                                                                        color: Colors
                                                                            .red),
                                                                  if (hintTargets
                                                                      .contains(
                                                                          i))
                                                                    Icon(
                                                                        Icons
                                                                            .lightbulb,
                                                                        size:
                                                                            14,
                                                                        color: selected
                                                                            ? Colors.white
                                                                            : Colors.black87),
                                                                  if (hovered ==
                                                                          i &&
                                                                      !selected)
                                                                    const Icon(
                                                                        Icons
                                                                            .pan_tool_alt,
                                                                        size:
                                                                            14),
                                                                  if (selected &&
                                                                      !cell
                                                                          .start &&
                                                                      !cell
                                                                          .finish)
                                                                    const Icon(
                                                                        Icons
                                                                            .check,
                                                                        size:
                                                                            14,
                                                                        color: Colors
                                                                            .white),
                                                                  if (cell.start ||
                                                                      cell
                                                                          .finish)
                                                                    Text(
                                                                        cell.start
                                                                            ? 'START'
                                                                            : 'FINISH',
                                                                        style: TextStyle(
                                                                            fontSize: board.size == 6
                                                                                ? 9
                                                                                : 11,
                                                                            fontWeight: FontWeight
                                                                                .bold,
                                                                            color: selected
                                                                                ? Colors.white
                                                                                : null)),
                                                                  FittedBox(
                                                                      child: Padding(
                                                                          padding: const EdgeInsets
                                                                              .symmetric(
                                                                              horizontal:
                                                                                  3),
                                                                          child: Text(
                                                                              '${cell.value}',
                                                                              style: TextStyle(fontSize: board.size == 6 ? 19 : 24, fontWeight: FontWeight.bold, color: selected ? Colors.white : null)))),
                                                                  if (solutionStep >=
                                                                      0)
                                                                    Text(
                                                                        'Step $solutionStep',
                                                                        style: TextStyle(
                                                                            fontSize:
                                                                                10,
                                                                            fontWeight: FontWeight
                                                                                .bold,
                                                                            color: selected
                                                                                ? Colors.white
                                                                                : Colors.black87)),
                                                                ]))))),
                                          ));
                                    },
                                  )))),
                      const SizedBox(height: 12),
                      if (mode == InputMode.spatial)
                        const Text(
                            'Spatial demo: hover with a mouse; click, tap, or long-press a tile to select it.',
                            textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            CircularControl(
                                onPressed: _newBoard,
                                icon: Icons.refresh,
                                label:
                                    stars > 0 ? 'Next puzzle' : 'New puzzle'),
                            CircularControl(
                                onPressed: stars > 0
                                    ? null
                                    : () => setState(() => _showHint()),
                                icon: Icons.lightbulb_outline,
                                label: 'Hint'),
                            CircularControl(
                                onPressed: () => setState(() {
                                      path
                                        ..clear()
                                        ..add(0);
                                      errors = 0;
                                      stars = 0;
                                      _clearHintProgress();
                                      solution = null;
                                      hovered = null;
                                      hintsUsed = 0;
                                      celebration.reset();
                                      started = lastInteraction = _now();
                                      elapsed = 0;
                                      message = 'Try again!';
                                    }),
                                icon: Icons.replay,
                                label: 'Restart'),
                          ]),
                      if (solution != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'Shortest path: ${solution!.length - 1} moves from START to FINISH. '
                            'Highlighted tiles show the full solution. Your moves stay unchanged.\n'
                            '${solution!.map((i) => '(${i ~/ board.size + 1}, ${i % board.size + 1})').join(' → ')}\n'
                            'Coordinates are (row, column), starting at 1.',
                            key: const ValueKey('solution-description'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ])))),
        if (debug)
          Positioned(
              top: 12,
              right: 12,
              child: IgnorePointer(
                  child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: min(width - 24, 330),
                    maxHeight: MediaQuery.sizeOf(context).height * .45),
                child: Card(
                    elevation: 12,
                    color: Theme.of(context).colorScheme.surface,
                    child: SingleChildScrollView(
                        child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              'DEVELOPER TELEMETRY\n'
                              'Board: ${board.size} × ${board.size} | Level: $boardLevel → ${difficulty.level}\n'
                              'Mode: ${mode.name} | Hover: $hovered | Selected: ${path.last}\n'
                              'Inputs: ${telemetry.inputEvents} | Hover frames: ${telemetry.hoverFrames} | Select: ${telemetry.selectionEvents}\n'
                              'Dispatch latency: ${telemetry.lastInputLatencyMs?.toStringAsFixed(2) ?? "N/A"} ms\n'
                              'Build avg: ${telemetry.buildMs?.toStringAsFixed(2) ?? "N/A"} ms | Raster avg: ${telemetry.rasterMs?.toStringAsFixed(2) ?? "N/A"} ms\n'
                              'Moves: ${path.length - 1} / ${board.shortestDistance()} | Errors: $errors\n'
                              'Hints: $hintsUsed | Stage: $hintStage/3 | Elapsed: ${elapsed}s\n'
                              'Stalled: ${_now().difference(lastInteraction).inSeconds}s\n'
                              'Camera FPS / inference: N/A (provider not connected)',
                              key: const ValueKey('telemetry-overlay'),
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12),
                            )))),
              ))),
      ]),
    );
  }
}
