import 'package:flutter_test/flutter_test.dart';
import 'package:math_game/engine.dart';

void main() {
  void record(DifficultyEngine engine,
      {int errors = 0, int moves = 8, double seconds = 30}) {
    engine.record(errors: errors, moves: moves, optimal: 8, seconds: seconds);
  }

  test('initial level matches the 5 by 5 multiples of 3 board', () {
    final engine = DifficultyEngine();
    expect(engine.level, 2);
    expect(engine.size, 5);
    expect(engine.divisor, 3);
  });
  test('two strong performances raise difficulty; a new window is required',
      () {
    final engine = DifficultyEngine();
    record(engine);
    expect(engine.level, 2);
    record(engine);
    expect(engine.level, 3);
    expect(engine.divisor, 4);
    record(engine);
    expect(engine.level, 3);
  });
  for (final reason in ['errors', 'inefficiency', 'time']) {
    test('repeated $reason lower difficulty', () {
      final engine = DifficultyEngine();
      for (var i = 0; i < 2; i++) {
        record(engine,
            errors: reason == 'errors' ? 10 : 0,
            moves: reason == 'inefficiency' ? 20 : 8,
            seconds: reason == 'time' ? 150 : 30);
      }
      expect(engine.level, 1);
      expect(engine.size, 4);
      expect(engine.divisor, 2);
    });
  }
  test('moderate performance holds level and bounds are respected', () {
    final engine = DifficultyEngine();
    for (var i = 0; i < 10; i++) {
      record(engine, errors: 2, seconds: 90);
    }
    expect(engine.level, 2);
    final easy = DifficultyEngine(initialLevel: 1);
    final hard = DifficultyEngine(initialLevel: 5);
    for (var i = 0; i < 10; i++) {
      record(easy, errors: 20);
      record(hard);
    }
    expect(easy.level, 1);
    expect(hard.level, 5);
    expect(hard.size, 6);
    expect(() => DifficultyEngine(initialLevel: 0), throwsArgumentError);
  });
}
