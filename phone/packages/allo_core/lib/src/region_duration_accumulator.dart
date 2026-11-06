/// Accumulates active time using caller-provided monotonic milliseconds.
class RegionDurationAccumulator {
  static const _regions = ['coast', 'mountain', 'city'];
  static const _holdMs = 5000;

  RegionDurationAccumulator({int startAtMs = 0}) : _cursorMs = startAtMs {
    if (startAtMs < 0) throw ArgumentError.value(startAtMs, 'startAtMs');
  }

  factory RegionDurationAccumulator.restore(
    Map<String, dynamic> checkpoint, {
    required int atMs,
  }) {
    final durations = checkpoint['durations'];
    final unknown = checkpoint['unknownMs'];
    if (durations is! Map ||
        durations.length != _regions.length ||
        !_regions
            .every((key) => durations[key] is int && durations[key] >= 0) ||
        unknown is! int ||
        unknown < 0) {
      throw const FormatException('Invalid region duration checkpoint');
    }
    final result = RegionDurationAccumulator(startAtMs: atMs);
    for (final region in _regions) {
      result._durations[region] = durations[region] as int;
    }
    result._unknownMs = unknown;
    return result;
  }

  final Map<String, int> _durations = {
    for (final region in _regions) region: 0
  };
  int _unknownMs = 0;
  int _cursorMs;
  int? _lastObservationMs;
  int? _expiresAtMs;
  String? _region;
  bool _finished = false;
  String? _result;

  Map<String, int> get durationMs => Map.unmodifiable(_durations);
  int get unknownMs => _unknownMs;
  int get activeMs =>
      _durations.values.fold(_unknownMs, (sum, value) => sum + value);

  void observe({required int atMs, required List<String> envTags}) {
    if (_finished ||
        atMs < _cursorMs ||
        (_lastObservationMs != null && atMs <= _lastObservationMs!)) {
      return;
    }
    _advance(atMs);
    final regions = envTags.where(_regions.contains).toSet();
    _region = regions.length == 1 ? regions.single : null;
    _expiresAtMs = atMs + _holdMs;
    _lastObservationMs = atMs;
  }

  void breakContinuity(int atMs) {
    if (_finished || atMs < _cursorMs) return;
    _advance(atMs);
    _region = null;
    _expiresAtMs = null;
  }

  String? finish(int atMs) {
    if (_finished) return _result;
    if (atMs >= _cursorMs) _advance(atMs);
    _finished = true;
    final sorted = _durations.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.first.value > sorted[1].value + _unknownMs) {
      _result = sorted.first.key;
    }
    return _result;
  }

  /// Closes the current interval and discards the open region for pausing.
  Map<String, Object?> checkpoint(int atMs) {
    breakContinuity(atMs);
    return {
      'durations': Map<String, int>.of(_durations),
      'unknownMs': _unknownMs
    };
  }

  void _advance(int atMs) {
    final elapsed = atMs - _cursorMs;
    var known = 0;
    if (_region != null && _expiresAtMs != null && _expiresAtMs! > _cursorMs) {
      final end = atMs < _expiresAtMs! ? atMs : _expiresAtMs!;
      known = end - _cursorMs;
      _durations[_region!] = _durations[_region!]! + known;
    }
    _unknownMs += elapsed - known;
    _cursorMs = atMs;
  }
}
