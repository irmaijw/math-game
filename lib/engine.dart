import 'dart:math';

class Cell {
  final int value;
  final bool start;
  final bool finish;
  const Cell(this.value, {this.start = false, this.finish = false});
}

class Board {
  final int size;
  final List<Cell> cells;
  final List<int> guaranteedPath;
  final int divisor;
  const Board(this.size, this.cells, this.guaranteedPath, this.divisor);
  int get goal => cells.length - 1;
  bool legal(int index) =>
      index >= 0 && index < cells.length && (cells[index].value % divisor == 0);
  bool adjacent(int a, int b) =>
      (a ~/ size == b ~/ size && (a - b).abs() == 1) ||
      (a % size == b % size && (a - b).abs() == size);
  List<int> neighbors(int index) => [
        index - size,
        index + size,
        if (index % size > 0) index - 1,
        if (index % size < size - 1) index + 1
      ].where((n) => n >= 0 && n < cells.length).toList();
  int? shortestDistance({int from = 0, Set<int> blocked = const {}}) {
    final route = shortestPath(from: from, blocked: blocked);
    return route == null ? null : route.length - 1;
  }

  /// Breadth-first search returns a minimum-move route, including both ends.
  /// The current tile may be in [blocked]; all other blocked tiles are avoided.
  List<int>? shortestPath({int from = 0, Set<int> blocked = const {}}) {
    if (!legal(from)) return null;
    final q = <int>[from];
    final parents = <int, int?>{from: null};
    for (var head = 0; head < q.length; head++) {
      final current = q[head];
      if (current == goal) {
        final route = <int>[];
        int? cursor = current;
        while (cursor != null) {
          route.add(cursor);
          cursor = parents[cursor];
        }
        return route.reversed.toList();
      }
      for (final next in neighbors(current)) {
        if (!blocked.contains(next) &&
            legal(next) &&
            !parents.containsKey(next)) {
          parents[next] = current;
          q.add(next);
        }
      }
    }
    return null;
  }
}

/// Constructive CSP: first assign a guaranteed satisfying route, then assign
/// distractors and optional alternate satisfying cells. Validate with BFS.
class BoardGenerator {
  final Random random;
  BoardGenerator([Random? random]) : random = random ?? Random();
  Board generate({int size = 5, int divisor = 3}) {
    if (size < 4 || size > 6) {
      throw ArgumentError.value(size, 'size', 'Must be between 4 and 6');
    }
    if (divisor < 2 || divisor > 6) {
      throw ArgumentError.value(divisor, 'divisor', 'Must be between 2 and 6');
    }
    for (var attempt = 0; attempt < 100; attempt++) {
      final path = <int>[0];
      final visited = <int>{0};
      var cursor = 0;
      // A monotonic path always reaches the opposite corner without revisits.
      while (cursor != size * size - 1) {
        final row = cursor ~/ size, col = cursor % size;
        final choices = <int>[
          if (row < size - 1) cursor + size,
          if (col < size - 1) cursor + 1
        ];
        cursor = choices[random.nextInt(choices.length)];
        visited.add(cursor);
        path.add(cursor);
      }
      // Reserve an off-route nonmultiple so distractors are guaranteed rather
      // than only probable. Remaining off-route domains may contain multiples.
      final offRoute = List<int>.generate(size * size, (i) => i)
          .where((i) => !visited.contains(i))
          .toList()
        ..shuffle(random);
      final distractor = offRoute.first;
      final cells = List<Cell>.generate(size * size, (i) {
        final valid = visited.contains(i) ||
            (i != distractor && random.nextDouble() < 0.27);
        final value =
            valid ? divisor * (1 + random.nextInt(9)) : 1 + random.nextInt(30);
        final corrected = valid ? value : _nonMultiple(value, divisor);
        return Cell(corrected, start: i == 0, finish: i == size * size - 1);
      });
      final board = Board(size, cells, path, divisor);
      if (board.shortestDistance() != null) return board;
    }
    throw StateError('Could not generate a solvable board');
  }

  int _nonMultiple(int value, int divisor) =>
      value % divisor == 0 ? value + 1 : value;
}

class DifficultyEngine {
  DifficultyEngine({int initialLevel = 2}) : level = initialLevel {
    if (initialLevel < 1 || initialLevel > 5) {
      throw ArgumentError.value(
          initialLevel, 'initialLevel', 'Must be between 1 and 5');
    }
  }
  int level;
  final List<double> _errors = [], _efficiency = [], _seconds = [];
  int get size => level == 1
      ? 4
      : level <= 4
          ? 5
          : 6;
  int get divisor => [2, 3, 4, 5, 6][(level - 1).clamp(0, 4)];
  void record(
      {required int errors,
      required int moves,
      required int optimal,
      required double seconds}) {
    _errors.add(errors / max(1, moves + errors));
    _efficiency.add(optimal / max(1, moves));
    _seconds.add(seconds);
    if (_errors.length > 3) {
      _errors.removeAt(0);
      _efficiency.removeAt(0);
      _seconds.removeAt(0);
    }
    if (_errors.length < 2) return;
    final error = _errors.reduce((a, b) => a + b) / _errors.length;
    final efficiency = _efficiency.reduce((a, b) => a + b) / _efficiency.length;
    final latency = _seconds.reduce((a, b) => a + b) / _seconds.length;
    if (error < .15 && efficiency > .85 && latency < 80 && level < 5) {
      level++;
      _clear();
    } else if ((error > .45 || efficiency < .55 || latency > 120) &&
        level > 1) {
      level--;
      _clear();
    }
  }

  void _clear() {
    _errors.clear();
    _efficiency.clear();
    _seconds.clear();
  }
}

int starsFor({required int moves, required int optimal, required int errors}) {
  final ratio = moves / max(1, optimal);
  if (ratio <= 1.001 && errors == 0) return 3;
  if (ratio <= 1.5) return 2;
  return 1;
}
