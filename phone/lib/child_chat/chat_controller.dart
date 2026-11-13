import 'package:flutter/foundation.dart';
import 'chat_service.dart';

class ChatExchange {
  const ChatExchange(this.question, this.reply);
  final String question;
  final ChatReply reply;
}

/// Ephemeral conversation: no preferences, database, analytics, or transcript logs.
class ChildChatController extends ChangeNotifier {
  ChildChatController({required this.service, required this.speciesId});
  final ChatService service;
  final String speciesId;
  final List<ChatExchange> _exchanges = [];
  List<ChatExchange> get exchanges => List.unmodifiable(_exchanges);
  bool busy = false;
  bool consented = false;
  String? pendingQuestion;
  int _generation = 0;
  bool _disposed = false;

  void allowSession() {
    consented = true;
    notifyListeners();
  }

  Future<bool> send(String text) async {
    final message = text.trim();
    if (_disposed ||
        !consented ||
        busy ||
        message.isEmpty ||
        message.length > 600) {
      return false;
    }
    final aiTurns = _exchanges.where((e) => e.reply.source == 'ai').toList();
    final recent =
        aiTurns.length > 6 ? aiTurns.sublist(aiTurns.length - 6) : aiTurns;
    final history = <ChatTurn>[
      for (final e in recent) ...[
        ChatTurn('user', e.question),
        ChatTurn('assistant', '${e.reply.answer}\n${e.reply.parentPrompt}'),
      ],
    ];
    final generation = _generation;
    busy = true;
    pendingQuestion = message;
    notifyListeners();
    ChatReply reply;
    try {
      reply = await service.reply(message, speciesId, history);
    } catch (_) {
      reply = ChatReply.unavailable;
    }
    if (_disposed || generation != _generation) return false;
    _exchanges.add(ChatExchange(message, reply));
    pendingQuestion = null;
    busy = false;
    notifyListeners();
    return true;
  }

  void clear() {
    _generation++;
    _exchanges.clear();
    pendingQuestion = null;
    busy = false;
    consented = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _exchanges.clear();
    service.close();
    super.dispose();
  }
}
