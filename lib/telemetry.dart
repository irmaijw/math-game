import 'dart:ui';

class GameTelemetry {
  int inputEvents = 0, hoverFrames = 0, selectionEvents = 0;
  final List<double> _build = [], _raster = [];
  double? lastInputLatencyMs;
  void recordFrames(List<FrameTiming> frames) {
    for (final frame in frames) {
      _build.add(frame.buildDuration.inMicroseconds / 1000);
      _raster.add(frame.rasterDuration.inMicroseconds / 1000);
    }
    if (_build.length > 60) _build.removeRange(0, _build.length - 60);
    if (_raster.length > 60) _raster.removeRange(0, _raster.length - 60);
  }

  double? get buildMs =>
      _build.isEmpty ? null : _build.reduce((a, b) => a + b) / _build.length;
  double? get rasterMs =>
      _raster.isEmpty ? null : _raster.reduce((a, b) => a + b) / _raster.length;
}
