/// One egg cycle. All times are integer seconds from the initial egg grant.
class IncubationRound {
  const IncubationRound._({
    required this.remainingEtaSec,
    required this.eggGrantedSec,
    required this.hatchEndSec,
    required this.companionEndSec,
    required this.grantsNextEgg,
  });

  /// Remaining ETA in seconds when this egg is granted.
  final int remainingEtaSec;
  final int eggGrantedSec;
  final int hatchEndSec;
  final int companionEndSec;
  final bool grantsNextEgg;
}

/// Calculates one cycle with its egg granted at second zero.
///
/// [remainingEtaSec] must be at least 120 seconds; smaller inputs cause a
/// [RangeError]. Callers must defer new egg grants for shorter ETAs, as required
/// by the product policy. For a final cycle, half the exact ETA is rounded down
/// to whole minutes for incubation; all
/// remaining seconds belong to companionship.
IncubationRound incubationRound(int remainingEtaSec) =>
    _round(remainingEtaSec, 0);

IncubationRound _round(int etaSec, int startSec) {
  if (etaSec < 120) {
    throw RangeError.range(etaSec, 120, null, 'remainingEtaSec');
  }
  final repeats = etaSec > 80 * 60;
  final incubationSec = repeats ? 40 * 60 : (etaSec ~/ 120) * 60;
  final cycleSec = repeats ? 70 * 60 : etaSec;
  return IncubationRound._(
    remainingEtaSec: etaSec,
    eggGrantedSec: startSec,
    hatchEndSec: startSec + incubationSec,
    companionEndSec: startSec + cycleSec,
    grantsNextEgg: repeats,
  );
}

/// Calculates an immutable schedule assuming ETA decreases only with elapsed
/// time. All result times are offsets in seconds from the first egg grant.
/// [initialEtaSec] must be at least 120 seconds, as in [incubationRound].
List<IncubationRound> incubationSchedule(int initialEtaSec) {
  final rounds = <IncubationRound>[];
  var elapsedSec = 0;
  while (true) {
    final round = _round(initialEtaSec - elapsedSec, elapsedSec);
    rounds.add(round);
    if (!round.grantsNextEgg) return List.unmodifiable(rounds);
    elapsedSec = round.companionEndSec;
  }
}
