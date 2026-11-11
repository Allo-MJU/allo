import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:allo_core/allo_core.dart';

class EggDemoApiException implements Exception {
  const EggDemoApiException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'EggDemoApiException($code): $message';
}

const _invalidResponse = EggDemoApiException(
    'invalid_response', 'The demo server returned an invalid response.');
final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
final _photoPattern = RegExp(r'^[a-f0-9]{32}$');

class UploadedEggPhoto {
  const UploadedEggPhoto(
      {required this.eggId,
      required this.requestId,
      required this.photoId,
      required this.uploadedAtMs});
  final String eggId;
  final String requestId;
  final String photoId;
  final int uploadedAtMs;

  factory UploadedEggPhoto.fromJson(Map<String, dynamic> json) {
    final eggId = json['eggId'];
    final requestId = json['requestId'];
    final photoId = json['photoId'];
    final uploadedAtMs = json['uploadedAtMs'];
    if (json.length != 4 ||
        eggId is! String ||
        !_idPattern.hasMatch(eggId) ||
        requestId is! String ||
        !_idPattern.hasMatch(requestId) ||
        photoId is! String ||
        !_photoPattern.hasMatch(photoId) ||
        uploadedAtMs is! int ||
        uploadedAtMs < 0) {
      throw _invalidResponse;
    }
    return UploadedEggPhoto(
        eggId: eggId,
        requestId: requestId,
        photoId: photoId,
        uploadedAtMs: uploadedAtMs);
  }
}

abstract class EggDemoApi {
  Future<SpeechSentiment> evaluate(
      {required String eggId, required String requestId, required String text});
  Future<UploadedEggPhoto> uploadPhoto(
      {required String eggId,
      required String requestId,
      required Uint8List bytes,
      required String mimeType});
  Future<UploadedEggPhoto?> findPhotoForEgg(String eggId);
  Future<List<UploadedEggPhoto>> listPhotos();
  Future<Uint8List> downloadPhoto(String photoId);
  void close();
}

class HttpEggDemoApi implements EggDemoApi {
  HttpEggDemoApi(
      {required Uri baseUri,
      required String token,
      this.timeout = const Duration(seconds: 25),
      bool allowInsecureLoopback = false})
      : _baseUri = baseUri,
        _token = token {
    final local = {'localhost', '127.0.0.1', '::1', '[::1]', '10.0.2.2'}
        .contains(baseUri.host);
    if (baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        (baseUri.path.isNotEmpty && baseUri.path != '/') ||
        (baseUri.scheme != 'https' &&
            !(baseUri.scheme == 'http' && allowInsecureLoopback && local)) ||
        token.trim().isEmpty ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(token) ||
        timeout <= Duration.zero) {
      throw const EggDemoApiException(
          'configuration', 'Configure a secure demo API URL and demo token.');
    }
  }

  factory HttpEggDemoApi.fromEnvironment() {
    const url = String.fromEnvironment('ALLO_DEMO_API_URL');
    const token = String.fromEnvironment('ALLO_DEMO_TOKEN');
    const insecure = bool.fromEnvironment('ALLO_DEMO_ALLOW_INSECURE_LOOPBACK');
    try {
      return HttpEggDemoApi(
          baseUri: Uri.parse(url),
          token: token,
          allowInsecureLoopback: insecure);
    } catch (_) {
      throw const EggDemoApiException(
          'configuration', 'Configure ALLO_DEMO_API_URL and ALLO_DEMO_TOKEN.');
    }
  }

  static const _maxPhoto = 5 * 1024 * 1024;
  final Uri _baseUri;
  final String _token;
  final Duration timeout;
  final HttpClient _client = HttpClient();
  bool _closed = false;

  void _validateIds(String eggId, String requestId) {
    if (!_idPattern.hasMatch(eggId) || !_idPattern.hasMatch(requestId)) {
      throw const EggDemoApiException(
          'invalid_input', 'Invalid egg or request identifier.');
    }
  }

  @override
  Future<SpeechSentiment> evaluate(
      {required String eggId,
      required String requestId,
      required String text}) async {
    _validateIds(eggId, requestId);
    if (text.trim().isEmpty || text.runes.length > 500) {
      throw const EggDemoApiException(
          'invalid_input', 'Speech must contain 1 to 500 characters.');
    }
    final data = await _json('POST', '/v1/egg/evaluate',
        {'eggId': eggId, 'requestId': requestId, 'text': text});
    if (data['eggId'] != eggId || data['requestId'] != requestId) {
      throw _invalidResponse;
    }
    return switch (data['sentiment']) {
      'positive' => SpeechSentiment.positive,
      'negative' => SpeechSentiment.negative,
      'neutral' => SpeechSentiment.neutral,
      _ => throw _invalidResponse,
    };
  }

  @override
  Future<UploadedEggPhoto> uploadPhoto(
      {required String eggId,
      required String requestId,
      required Uint8List bytes,
      required String mimeType}) async {
    _validateIds(eggId, requestId);
    if (bytes.isEmpty ||
        bytes.length > _maxPhoto ||
        !{'image/jpeg', 'image/png'}.contains(mimeType)) {
      throw const EggDemoApiException(
          'invalid_input', 'Provide a JPEG or PNG photo up to 5 MiB.');
    }
    final data = await _json('POST', '/v1/egg/photo', {
      'eggId': eggId,
      'requestId': requestId,
      'imageBase64': base64Encode(bytes),
      'mimeType': mimeType
    });
    final photo = UploadedEggPhoto.fromJson(data);
    if (photo.eggId != eggId || photo.requestId != requestId) {
      throw _invalidResponse;
    }
    return photo;
  }

  @override
  Future<UploadedEggPhoto?> findPhotoForEgg(String eggId) async {
    if (!_idPattern.hasMatch(eggId)) {
      throw const EggDemoApiException(
          'invalid_input', 'Invalid egg identifier.');
    }
    try {
      final bytes = await _request('GET', '/v1/egg/photos/by-egg/$eggId',
          maxBytes: 64 * 1024, mime: 'application/json', allowNotFound: true);
      final photo = UploadedEggPhoto.fromJson(_decodeJson(bytes));
      if (photo.eggId != eggId) throw _invalidResponse;
      return photo;
    } on EggDemoApiException catch (error) {
      if (error.code == 'not_found') return null;
      rethrow;
    }
  }

  @override
  Future<List<UploadedEggPhoto>> listPhotos() async {
    final data = await _json('GET', '/v1/egg/photos');
    final photos = data['photos'];
    if (photos is! List || photos.length > 100) throw _invalidResponse;
    return List.unmodifiable(photos.map((photo) {
      if (photo is! Map<String, dynamic>) throw _invalidResponse;
      return UploadedEggPhoto.fromJson(photo);
    }));
  }

  @override
  Future<Uint8List> downloadPhoto(String photoId) async {
    if (!_photoPattern.hasMatch(photoId)) {
      throw const EggDemoApiException(
          'invalid_input', 'Invalid photo identifier.');
    }
    return _request('GET', '/v1/egg/photos/$photoId',
        maxBytes: _maxPhoto, mime: 'image/jpeg');
  }

  Future<Map<String, dynamic>> _json(String method, String path,
      [Map<String, dynamic>? body]) async {
    final bytes = await _request(method, path,
        body: body, maxBytes: 64 * 1024, mime: 'application/json');
    return _decodeJson(bytes);
  }

  Map<String, dynamic> _decodeJson(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) throw _invalidResponse;
      return decoded;
    } catch (_) {
      throw _invalidResponse;
    }
  }

  Future<Uint8List> _request(String method, String path,
      {Map<String, dynamic>? body,
      required int maxBytes,
      required String mime,
      bool allowNotFound = false}) async {
    if (_closed) {
      throw const EggDemoApiException(
          'closed', 'The demo API client is closed.');
    }
    HttpClientRequest? request;
    StreamSubscription<List<int>>? subscription;
    var expired = false;
    Future<Uint8List> run() async {
      request = await _client.openUrl(method, _baseUri.resolve(path));
      if (expired || _closed) {
        request!.abort();
        throw const EggDemoApiException(
            'closed', 'The demo API request was cancelled.');
      }
      request!.followRedirects = false;
      request!.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      request!.headers.set(HttpHeaders.acceptHeader, mime);
      if (body != null) {
        final payload = utf8.encode(jsonEncode(body));
        request!.headers.contentType = ContentType.json;
        request!.contentLength = payload.length;
        request!.add(payload);
      }
      final response = await request!.close();
      if (allowNotFound && response.statusCode == HttpStatus.notFound) {
        request!.abort();
        throw const EggDemoApiException('not_found', 'Photo not found.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        request!.abort();
        throw const EggDemoApiException(
            'http_error', 'The demo server could not complete the request.');
      }
      if (response.headers.contentType?.mimeType != mime ||
          response.contentLength > maxBytes) {
        request!.abort();
        throw _invalidResponse;
      }
      final bytes = BytesBuilder(copy: false);
      final result = Completer<Uint8List>();
      subscription = response.listen((chunk) {
        if (bytes.length + chunk.length > maxBytes) {
          subscription?.cancel();
          request!.abort();
          if (!result.isCompleted) result.completeError(_invalidResponse);
          return;
        }
        bytes.add(chunk);
      }, onError: (Object error) {
        if (!result.isCompleted) result.completeError(error);
      }, onDone: () {
        if (!result.isCompleted) result.complete(bytes.takeBytes());
      }, cancelOnError: true);
      return result.future;
    }

    try {
      return await run().timeout(timeout, onTimeout: () {
        expired = true;
        subscription?.cancel();
        request?.abort();
        throw const EggDemoApiException(
            'timeout', 'The demo server took too long to respond.');
      });
    } on EggDemoApiException {
      rethrow;
    } catch (_) {
      throw const EggDemoApiException(
          'network', 'Could not connect to the demo server.');
    }
  }

  @override
  void close() {
    _closed = true;
    _client.close(force: true);
  }
}
