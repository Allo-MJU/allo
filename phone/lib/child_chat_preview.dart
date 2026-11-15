import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'child_chat/chat_screen.dart';

/// Standalone debug entry for adult prototype evaluation without a vehicle/hatch.
/// flutter run -t lib/child_chat_preview.dart [--dart-define=CHAT_MODE=local]
void main() {
  if (!kDebugMode) throw UnsupportedError('Chat preview is debug-only');
  runApp(MaterialApp(
    title: 'Allo English Chat Preview',
    theme:
        ThemeData(colorSchemeSeed: const Color(0xFF4FB3A9), useMaterial3: true),
    home: const ChildChatScreen(speciesId: 'road_sprout', name: 'Road Sprout'),
  ));
}
