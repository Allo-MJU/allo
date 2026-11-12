enum SpeechSentiment { positive, negative, neutral }

enum AffinityPhase { incubating, photoRequired, hatched, failed, discarded }

enum EggFeedback {
  none,
  positive,
  negative,
  neutral,
  vibration,
  photoRequired,
  hatched,
  fled
}

class AffinityRound {
  AffinityRound._(
      this.eggId, this._preferredZone, this._currentZone, this.deadlineMs);

  factory AffinityRound.start(
      {required String eggId,
      required int preferredZone,
      int? deadlineMs,
      int currentZone = 0}) {
    if (eggId.trim().isEmpty ||
        !_zone(preferredZone) ||
        !_zone(currentZone) ||
        (deadlineMs != null && deadlineMs < 0)) {
      throw ArgumentError('Invalid round parameters');
    }
    return AffinityRound._(eggId, preferredZone, currentZone, deadlineMs);
  }

  final String eggId;
  final int? deadlineMs;
  int _preferredZone;
  int _currentZone;
  AffinityPhase _phase = AffinityPhase.incubating;
  int _scoreMilli = 0;
  int _elapsedMs = 0;
  bool _photoCompleted = false;
  String? _photoId;
  int? _hatchedAtMs;

  int get preferredZone => _preferredZone;
  int get currentZone => _currentZone;
  AffinityPhase get phase => _phase;
  int get scoreMilli => _scoreMilli;
  int get elapsedMs => _elapsedMs;
  bool get photoCompleted => _photoCompleted;
  String? get photoId => _photoId;
  int? get hatchedAtMs => _hatchedAtMs;
  int? _speechAt, _petAt, _moveAt, _rampAt;
  int _rampCredited = 0;
  final Set<String> _requestIds = {};

  double get score => scoreMilli / 1000;
  bool get isTerminal =>
      phase == AffinityPhase.hatched ||
      phase == AffinityPhase.failed ||
      phase == AffinityPhase.discarded;
  int get speechRemainingMs => _remaining(_speechAt, 180000);
  int get petRemainingMs => _remaining(_petAt, 10000);
  int get moveRemainingMs => _remaining(_moveAt, 15000);
  int _remaining(int? at, int duration) =>
      at == null ? 0 : (duration - (elapsedMs - at)).clamp(0, duration);
  static bool _zone(int n) => n >= 0 && n <= 3;

  EggFeedback advanceTo(int atMs, {bool distanceDeadlineReached = false}) {
    if (atMs < 0) throw ArgumentError.value(atMs, 'atMs');
    if (atMs < elapsedMs || isTerminal) return EggFeedback.none;
    final limit =
        deadlineMs != null && deadlineMs! <= atMs ? deadlineMs! : atMs;
    // A distance deadline is observed at the supplied boundary; a crossing at it loses.
    final expiry =
        (deadlineMs != null && deadlineMs! <= atMs) || distanceDeadlineReached;
    if (_rampAt != null && phase == AffinityPhase.incubating) {
      final milestone = photoCompleted ? 100000 : 50000;
      final needed = milestone - scoreMilli;
      final crossing = _rampAt! + ((_rampCredited + needed) * 5);
      if (crossing <= _rampAt! + 60000 &&
          crossing <= limit &&
          (!expiry || crossing < limit)) {
        _elapsedMs = crossing;
        _scoreMilli = milestone;
        _rampAt = null;
        _rampCredited = 0;
        if (photoCompleted) {
          _phase = AffinityPhase.hatched;
          _hatchedAtMs = crossing;
          return EggFeedback.hatched;
        }
        _phase = AffinityPhase.photoRequired;
        if (!expiry) {
          _elapsedMs = atMs;
          return EggFeedback.photoRequired;
        }
      } else {
        final earned = ((limit - _rampAt!).clamp(0, 60000)) ~/ 5;
        _scoreMilli += earned - _rampCredited;
        _rampCredited = earned;
        if (earned == 12000) {
          _rampAt = null;
          _rampCredited = 0;
        }
      }
    }
    _elapsedMs = limit;
    if (expiry) {
      _phase = AffinityPhase.failed;
      _rampAt = null;
      _rampCredited = 0;
      return EggFeedback.fled;
    }
    return EggFeedback.none;
  }

  EggFeedback _add(int amount) {
    _scoreMilli += amount;
    final threshold = photoCompleted ? 100000 : 50000;
    if (scoreMilli >= threshold) {
      _scoreMilli = threshold;
      _rampAt = null;
      _rampCredited = 0;
      if (photoCompleted) {
        _phase = AffinityPhase.hatched;
        _hatchedAtMs = elapsedMs;
        return EggFeedback.hatched;
      }
      _phase = AffinityPhase.photoRequired;
      return EggFeedback.photoRequired;
    }
    return EggFeedback.none;
  }

  EggFeedback speak(
      {required int atMs,
      required String requestId,
      required SpeechSentiment sentiment}) {
    if (atMs < elapsedMs ||
        requestId.trim().isEmpty ||
        _requestIds.contains(requestId)) {
      return EggFeedback.none;
    }
    final event = advanceTo(atMs);
    if (event != EggFeedback.none ||
        phase != AffinityPhase.incubating ||
        speechRemainingMs > 0) {
      return event;
    }
    _requestIds.add(requestId);
    _speechAt = atMs;
    switch (sentiment) {
      case SpeechSentiment.positive:
        _rampAt = atMs;
        _rampCredited = 0;
        return EggFeedback.positive;
      case SpeechSentiment.negative:
        _scoreMilli = (scoreMilli - 12000).clamp(0, 100000);
        return EggFeedback.negative;
      case SpeechSentiment.neutral:
        return EggFeedback.neutral;
    }
  }

  EggFeedback pet({required int atMs}) {
    if (atMs < elapsedMs) return EggFeedback.none;
    final event = advanceTo(atMs);
    if (event != EggFeedback.none || phase != AffinityPhase.incubating) {
      return event;
    }
    if (petRemainingMs > 0) return EggFeedback.vibration;
    _petAt = atMs;
    final milestone = _add(3000);
    return milestone == EggFeedback.none ? EggFeedback.positive : milestone;
  }

  EggFeedback place(
      {required int atMs, required int zone, required int nextPreferredZone}) {
    if (atMs < elapsedMs ||
        !_zone(zone) ||
        !_zone(nextPreferredZone) ||
        zone == nextPreferredZone) {
      return EggFeedback.none;
    }
    final event = advanceTo(atMs);
    if (event != EggFeedback.none || phase != AffinityPhase.incubating) {
      return event;
    }
    if (zone == currentZone || moveRemainingMs > 0) {
      return EggFeedback.vibration;
    }
    _currentZone = zone;
    _moveAt = atMs;
    if (zone != preferredZone) return EggFeedback.vibration;
    _preferredZone = nextPreferredZone;
    final milestone = _add(7000);
    return milestone == EggFeedback.none ? EggFeedback.positive : milestone;
  }

  EggFeedback confirmPhoto(
      {required int atMs, required String eggId, required String photoId}) {
    if (atMs < elapsedMs) return EggFeedback.none;
    final event = advanceTo(atMs);
    if (event != EggFeedback.none ||
        phase != AffinityPhase.photoRequired ||
        eggId != this.eggId ||
        photoId.trim().isEmpty) {
      return event;
    }
    _photoId = photoId;
    _photoCompleted = true;
    _scoreMilli = 65000;
    _phase = AffinityPhase.incubating;
    return EggFeedback.positive;
  }

  EggFeedback discard({required int atMs}) {
    if (atMs < elapsedMs) return EggFeedback.none;
    final event = advanceTo(atMs);
    if (event != EggFeedback.none || isTerminal) return event;
    _phase = AffinityPhase.discarded;
    _rampAt = null;
    _rampCredited = 0;
    return EggFeedback.none;
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'eggId': eggId,
        'preferredZone': preferredZone,
        'currentZone': currentZone,
        'deadlineMs': deadlineMs,
        'phase': phase.name,
        'scoreMilli': scoreMilli,
        'elapsedMs': elapsedMs,
        'photoCompleted': photoCompleted,
        'photoId': photoId,
        'hatchedAtMs': hatchedAtMs,
        'speechAtMs': _speechAt,
        'petAtMs': _petAt,
        'moveAtMs': _moveAt,
        'rampAtMs': _rampAt,
        'rampCredited': _rampCredited,
        'requestIds': _requestIds.toList(),
      };

  factory AffinityRound.fromJson(Map<String, dynamic> json) {
    try {
      int integer(String k) => json[k] as int;
      int? optionalInt(String k) => json[k] as int?;
      const keys = {
        'version',
        'eggId',
        'preferredZone',
        'currentZone',
        'deadlineMs',
        'phase',
        'scoreMilli',
        'elapsedMs',
        'photoCompleted',
        'photoId',
        'hatchedAtMs',
        'speechAtMs',
        'petAtMs',
        'moveAtMs',
        'rampAtMs',
        'rampCredited',
        'requestIds'
      };
      if (!json.keys.toSet().containsAll(keys)) {
        throw const FormatException('Missing field');
      }
      if (integer('version') != 1) {
        throw const FormatException('Unsupported version');
      }
      final r = AffinityRound.start(
          eggId: json['eggId'] as String,
          preferredZone: integer('preferredZone'),
          currentZone: integer('currentZone'),
          deadlineMs: optionalInt('deadlineMs'));
      r._phase = AffinityPhase.values.byName(json['phase'] as String);
      r._scoreMilli = integer('scoreMilli');
      r._elapsedMs = integer('elapsedMs');
      r._photoCompleted = json['photoCompleted'] as bool;
      r._photoId = json['photoId'] as String?;
      r._hatchedAtMs = optionalInt('hatchedAtMs');
      r._speechAt = optionalInt('speechAtMs');
      r._petAt = optionalInt('petAtMs');
      r._moveAt = optionalInt('moveAtMs');
      r._rampAt = optionalInt('rampAtMs');
      r._rampCredited = integer('rampCredited');
      final ids = (json['requestIds'] as List).cast<String>();
      if (ids.any((id) => id.trim().isEmpty) ||
          ids.toSet().length != ids.length) {
        throw const FormatException('Invalid request IDs');
      }
      r._requestIds.addAll(ids);
      if (r.elapsedMs < 0 ||
          r.scoreMilli < 0 ||
          r.scoreMilli > 100000 ||
          [r._speechAt, r._petAt, r._moveAt, r._rampAt]
              .any((v) => v != null && (v < 0 || v > r.elapsedMs)) ||
          (r.deadlineMs != null && r.elapsedMs > r.deadlineMs!) ||
          (r.photoCompleted
              ? (r.photoId == null || r.photoId!.trim().isEmpty)
              : r.photoId != null) ||
          (!r.photoCompleted && r.scoreMilli > 50000) ||
          (r._rampAt != null && r.scoreMilli < r._rampCredited) ||
          (r.phase == AffinityPhase.photoRequired &&
              (r.photoCompleted || r.scoreMilli != 50000)) ||
          (!r.photoCompleted &&
              r.phase == AffinityPhase.incubating &&
              r.scoreMilli >= 50000) ||
          (r.phase == AffinityPhase.hatched &&
              (!r.photoCompleted ||
                  r.scoreMilli != 100000 ||
                  r.hatchedAtMs != r.elapsedMs)) ||
          (r.phase != AffinityPhase.hatched && r.hatchedAtMs != null) ||
          (r.phase == AffinityPhase.incubating && r.scoreMilli >= 100000) ||
          (r.deadlineMs != null &&
              r.elapsedMs == r.deadlineMs &&
              r.phase != AffinityPhase.failed &&
              !(r.deadlineMs == 0 &&
                  r.phase == AffinityPhase.incubating &&
                  r.scoreMilli == 0 &&
                  r._speechAt == null &&
                  r._petAt == null &&
                  r._moveAt == null &&
                  r._requestIds.isEmpty &&
                  !r.photoCompleted)) ||
          (r._rampAt == null && r._rampCredited != 0) ||
          (r._rampAt != null &&
              (r.phase != AffinityPhase.incubating ||
                  r._speechAt != r._rampAt ||
                  r._rampCredited !=
                      ((r.elapsedMs - r._rampAt!).clamp(0, 60000) ~/ 5) ||
                  r._rampCredited >= 12000))) {
        throw const FormatException('Inconsistent round');
      }
      return r;
    } catch (e) {
      if (e is FormatException) rethrow;
      throw FormatException('Invalid round: $e');
    }
  }
}
