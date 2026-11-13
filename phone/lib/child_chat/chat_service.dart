import 'dart:convert';
import 'dart:io';

class ChatTurn {
  const ChatTurn(this.role, this.content);
  final String role;
  final String content;
  Map<String, String> toJson() => {'role': role, 'content': content};
}

class ChatReply {
  const ChatReply(this.answer, this.parentPrompt, this.source);
  final String answer;
  final String parentPrompt;
  final String source;

  static const unavailable = ChatReply(
    'I could not prepare an answer just now. We can try again later.',
    'You could explore this question with a parent or another trusted adult when they are free.',
    'fallback',
  );

  factory ChatReply.fromJson(Map<String, dynamic> json) {
    final answer = json['answer'];
    final prompt = json['parentPrompt'];
    final source = json['source'];
    if (answer is! String ||
        answer.trim().isEmpty ||
        answer.length > 900 ||
        prompt is! String ||
        prompt.length > 250 ||
        !const ['ai', 'fallback'].contains(source)) {
      throw const FormatException('Invalid chat response');
    }
    return ChatReply(answer, prompt, source as String);
  }
}

abstract interface class ChatService {
  bool get isDemo;
  Future<ChatReply> reply(
      String message, String speciesId, List<ChatTurn> history);
  void close();
}

/// Reviewed examples for exercising the UI, never presented as generated AI.
class DemoChatService implements ChatService {
  @override
  bool get isDemo => true;

  @override
  Future<ChatReply> reply(
      String message, String speciesId, List<ChatTurn> history) async {
    final q = message.toLowerCase().trim();
    if (q == 'why is the sky blue?') {
      return const ChatReply(
          'Sunlight contains many colors. Tiny molecules in the air scatter blue light more strongly than red light. That scattered blue light reaches our eyes from across the sky.',
          'When a parent is free, ask: “What colors have you noticed in the sky at sunset?”',
          'demo');
    }
    if (q == 'how do fish breathe underwater?') {
      return const ChatReply(
          'Fish use gills to take in oxygen dissolved in water. As water flows over the gills, oxygen moves into the blood. Fish need oxygen just as we do, but they get it in a different way.',
          'Ask a parent or trusted adult: “How are gills different from our lungs?”',
          'demo');
    }
    if (q == 'i made a mistake at school.') {
      return const ChatReply(
          'Making a mistake can feel frustrating. It does not mean you cannot learn. You could work out which step was confusing and try one small change next time.',
          'If you feel comfortable, tell a trusted adult what happened and ask how they learned from a mistake.',
          'demo');
    }
    return const ChatReply(
        'This is example mode, so I cannot generate an answer to that question. A local AI connection is needed for open-ended replies.',
        'You can still discuss your question with a parent or another trusted adult when they are free.',
        'demo');
  }

  @override
  void close() {}
}

/// Debug local adapter only. Android uses adb reverse tcp:8766 tcp:8766.
/// No provider keys, Firebase session IDs, location or game mutations.
class LocalChatService implements ChatService {
  LocalChatService({HttpClient? client}) : _client = client ?? HttpClient();
  final HttpClient _client;
  @override
  bool get isDemo => false;

  @override
  Future<ChatReply> reply(
      String message, String speciesId, List<ChatTurn> history) async {
    HttpClientRequest? request;
    try {
      return await (() async {
        request =
            await _client.postUrl(Uri.parse('http://127.0.0.1:8766/chat'));
        request!.followRedirects = false;
        request!.headers.contentType = ContentType.json;
        final body = utf8.encode(jsonEncode({
          'message': message,
          'speciesId': speciesId,
          'history': history.map((t) => t.toJson()).toList(),
        }));
        request!.contentLength = body.length;
        request!.add(body);
        final response = await request!.close();
        if (response.statusCode != 200) {
          throw const HttpException('Chat unavailable');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 16384) {
            throw const FormatException('Chat response too large');
          }
          bytes.addAll(chunk);
        }
        return ChatReply.fromJson(
            jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
      })()
          .timeout(const Duration(seconds: 150));
    } catch (_) {
      request?.abort();
      return ChatReply.unavailable;
    }
  }

  @override
  void close() => _client.close(force: true);
}
