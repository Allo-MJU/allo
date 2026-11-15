/// Time offsets from the beginning of incubation. The trip has one egg.
class IncubationRound {
  const IncubationRound._(this.remainingEtaSec, this.hatchEndSec);

  final int remainingEtaSec;
  final int hatchEndSec;
  int get eggGrantedSec => 0;
  int get companionEndSec => remainingEtaSec;
  bool get grantsNextEgg => false;
}

/// The hatch plan waits for at least two minutes of ETA. Half of the ETA is
/// rounded down to whole minutes, up to a maximum of forty minutes.
IncubationRound incubationRound(int remainingEtaSec) {
  if (remainingEtaSec < 120) {
    throw RangeError.range(remainingEtaSec, 120, null, 'remainingEtaSec');
  }
  return IncubationRound._(remainingEtaSec,
      remainingEtaSec > 4800 ? 2400 : (remainingEtaSec ~/ 120) * 60);
}

List<IncubationRound> incubationSchedule(int initialEtaSec) =>
    List.unmodifiable([incubationRound(initialEtaSec)]);
