import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:allo_core/allo_core.dart';
import 'package:flutter/foundation.dart';
import '../feed/vehicle_feed.dart';

/// Debug-only local transport. The phone's production game/fishing controllers
/// still own progress and rewards; this bridge only carries JSON.
class LocalFishingFeed extends VehicleFeed {
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  final status = ValueNotifier<String>('로컬 연결 준비 중');
  final game = ValueNotifier<Map<String, dynamic>>({});
  final _vehicles = StreamController<VehicleState>.broadcast();
  final _events = StreamController<Map<String, Object?>>.broadcast();
  Timer? _timer;
  int _cursor = 0;
  int? _lastTs;
  bool _polling = false;
  bool _closed = false;

  Future<dynamic> _request(String path,
      {String method = 'GET', Object? body}) async {
    final request =
        await _client.openUrl(method, Uri.parse('http://10.0.2.2:8765$path'));
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close().timeout(const Duration(seconds: 3));
    final raw = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 3));
    if (response.statusCode >= 300) {
      throw HttpException('Local bridge ${response.statusCode}');
    }
    return raw.isEmpty ? null : jsonDecode(raw);
  }

  @override
  Future<void> pair(String sessionId, {String? pairCode}) async {
    await _request('/vehicle');
    _timer ??=
        Timer.periodic(const Duration(milliseconds: 400), (_) => _poll());
    status.value = '로컬 연결 · 모의 주차 신호';
  }

  Future<void> _poll() async {
    if (_polling || _closed) return;
    _polling = true;
    try {
      final vehicle = await readLatestVehicle();
      if (_closed) return;
      if (vehicle != null && vehicle.ts != _lastTs) {
        _lastTs = vehicle.ts;
        _vehicles.add(vehicle);
      }
      final data =
          await _request('/events?after=$_cursor') as Map<String, dynamic>;
      if (_closed) return;
      for (final envelope in data['events'] as List) {
        final event = Map<String, Object?>.from(envelope['event'] as Map);
        if (event['by'] == 'car') _events.add(event);
      }
      _cursor = (data['cursor'] as num).toInt();
      status.value = '로컬 연결 · 모의 주차 신호';
    } catch (_) {
      if (!_closed) status.value = '로컬 연결 끊김 · 자동 재연결 중';
    } finally {
      _polling = false;
    }
  }

  @override
  Stream<VehicleState> watch() => _vehicles.stream;
  @override
  Future<VehicleState?> readLatestVehicle() async {
    final data = await _request('/vehicle');
    return data == null
        ? null
        : VehicleState.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<void> publishGame(GameState state) async {
    final value = state.toJson();
    await _request('/game', method: 'PUT', body: value);
    if (!_closed) game.value = value;
  }

  @override
  Future<void> emitEvent(String type,
      {Map<String, Object?> payload = const {}}) async {
    await _request('/events', method: 'POST', body: {
      'by': 'phone',
      'type': type,
      'payload': payload,
      'ts': DateTime.now().millisecondsSinceEpoch
    });
  }

  @override
  Stream<Map<String, Object?>> events() => _events.stream;
  @override
  Future<void> dispose() async {
    _closed = true;
    _timer?.cancel();
    _client.close(force: true);
    await _vehicles.close();
    await _events.close();
  }
}
