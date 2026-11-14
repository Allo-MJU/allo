import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:allo_core/allo_core.dart';
import '../affinity/egg_demo_api.dart';
import '../feed/fake_feed.dart';
import '../fishing/fishing_store.dart';
import '../storage/dex_store.dart';
import '../storage/pairing_store.dart';
import '../pairing/pairing_credentials.dart';

/// Explicit synthetic adapter for the debug entrypoint only. No network or raw text storage.
class LocalAffinityApi implements EggDemoApi {
  final Map<String, UploadedEggPhoto> _receipts = {};
  bool closed = false;
  @override
  Future<SpeechSentiment> evaluate(
      {required String eggId,
      required String requestId,
      required String text}) async {
    if (closed) throw StateError('Demo closed');
    return SpeechSentiment.positive;
  }

  @override
  Future<UploadedEggPhoto> uploadPhoto(
      {required String eggId,
      required String requestId,
      required Uint8List bytes,
      required String mimeType}) async {
    if (closed) throw StateError('Demo closed');
    return _receipts.putIfAbsent(
        eggId,
        () => UploadedEggPhoto(
            eggId: eggId,
            requestId: requestId,
            photoId: '00000000000000000000000000000000',
            uploadedAtMs: DateTime.now().millisecondsSinceEpoch));
  }

  @override
  Future<UploadedEggPhoto?> findPhotoForEgg(String eggId) async =>
      _receipts[eggId];
  @override
  Future<List<UploadedEggPhoto>> listPhotos() async =>
      _receipts.values.toList();
  @override
  Future<Uint8List> downloadPhoto(String photoId) async => Uint8List(0);
  @override
  void close() {
    closed = true;
    _receipts.clear();
  }
}

/// In-memory stores never touch the normal collection, pairing or fishing keys.
class LocalAffinityDex extends DexStore {
  LocalAffinityDex() : super(namespace: 'local.affinity.');
  final List<DexEntry> entries = [];
  final Map<EggTier, IncubationProgress> _progress = {};
  @override
  Future<List<DexEntry>> all() async => List.of(entries);
  @override
  Future<void> add(DexEntry e) async {
    if (!entries
        .any((old) => jsonEncode(old.toJson()) == jsonEncode(e.toJson()))) {
      entries.add(e);
    }
  }

  @override
  Future<IncubationProgress> incubationProgress(EggTier tier) async =>
      _progress[tier] ?? const IncubationProgress();
  @override
  Future<void> saveIncubationProgress(
      EggTier tier, IncubationProgress progress) async {
    _progress[tier] = progress;
  }
}

class LocalAffinityFishing extends FishingStore {
  String? _value;
  @override
  Future<Map<String, dynamic>?> read() async =>
      _value == null ? null : jsonDecode(_value!) as Map<String, dynamic>;
  @override
  Future<void> write(Map<String, dynamic> profile) async {
    _value = jsonEncode(profile);
  }
}

class LocalAffinityPairing extends PairingStore {
  @override
  Future<PairingCredentials?> read() async => null;
  @override
  Future<void> save(PairingCredentials credentials) async {}
  @override
  Future<void> clear() async {}
}

/// Stable parked vehicle signal; time skipping affects the real controller's injected clock.
class LocalAffinityFeed extends FakeVehicleFeed {
  LocalAffinityFeed()
      : super(scenario: FakeScenario.rainyHighway, timeScale: 1) {
    _watch.start();
    _pulse = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }
  final _watch = Stopwatch();
  int _offset = 0, _sequence = 0;
  int get now => _watch.elapsedMilliseconds + _offset;
  final _signals = StreamController<VehicleState>.broadcast();
  final _carEvents = StreamController<Map<String, Object?>>.broadcast();
  Timer? _pulse;
  GameState? latestGame;
  VehicleState? _vehicle;
  bool _closed = false;
  bool _tripEnded = false;
  void advance(int milliseconds) {
    _offset += milliseconds;
    tick();
  }

  void tick() {
    if (_closed || _tripEnded) return;
    final fishing = latestGame?.toJson()['fishing'] as Map?;
    _vehicle = VehicleState.fromJson({
      'ts': DateTime.now().millisecondsSinceEpoch + ++_sequence,
      'gear': 'P',
      'speedKph': 0,
      'distanceM': 0,
      'etaSec': 5400,
      'envTags': ['city'],
      if (fishing != null)
        'fishingPresence': {
          'version': 1,
          'leaseId': fishing['leaseId'],
          'epoch': 'local-affinity',
          'sequence': _sequence,
          'active': true,
          'parkedAllowed': true,
        }
    });
    _signals.add(_vehicle!);
  }

  @override
  Stream<VehicleState> watch() {
    _tripEnded = false;
    scheduleMicrotask(tick);
    return _signals.stream;
  }

  @override
  Future<VehicleState?> readLatestVehicle() async => _vehicle;
  @override
  Future<void> publishGame(GameState state) async {
    latestGame = state;
  }

  @override
  Future<void> emitEvent(String type,
      {Map<String, Object?> payload = const {}}) async {}
  @override
  Stream<Map<String, Object?>> events() => _carEvents.stream;
  @override
  void endTrip() {
    if (_closed || _tripEnded) return;
    _tripEnded = true;
    _carEvents.add({
      'ts': DateTime.now().millisecondsSinceEpoch,
      'type': 'sessionEnd',
      'by': 'car'
    });
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _pulse?.cancel();
    _watch.stop();
    await _signals.close();
    await _carEvents.close();
    await super.dispose();
  }
}
