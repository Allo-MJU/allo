import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'chat_controller.dart';
import 'chat_service.dart';

class ChildChatButton extends StatelessWidget {
  const ChildChatButton({super.key});
  @override
  Widget build(BuildContext context) => kDebugMode
      ? FilledButton.icon(
          onPressed: () => context.push('/chat'),
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Talk in English'),
        )
      : const SizedBox.shrink();
}

class ChildChatScreen extends StatefulWidget {
  const ChildChatScreen(
      {super.key, required this.speciesId, required this.name, this.service});
  final String speciesId;
  final String name;
  final ChatService? service;
  @override
  State<ChildChatScreen> createState() => _ChildChatScreenState();
}

class _ChildChatScreenState extends State<ChildChatScreen> {
  late final chat = ChildChatController(
    speciesId: widget.speciesId,
    service: widget.service ??
        (kDebugMode && const String.fromEnvironment('CHAT_MODE') == 'local'
            ? LocalChatService()
            : DemoChatService()),
  );
  final input = TextEditingController();
  final scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    chat.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      }
    });
  }

  void _send() {
    if (input.text.trim().isEmpty || chat.busy) return;
    final message = input.text;
    input.clear();
    chat.send(message);
  }

  @override
  void dispose() {
    chat.removeListener(_changed);
    chat.dispose();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  bool get compactInput {
    final media = MediaQuery.of(context);
    return media.viewInsets.bottom > 0 &&
        media.size.height - media.viewInsets.bottom < 260;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: compactInput
            ? null
            : AppBar(
                title: Text('Talk with ${widget.name}'),
                actions: [
                  TextButton(
                      onPressed: () {
                        input.clear();
                        chat.clear();
                      },
                      child: const Text('Clear chat'))
                ],
              ),
        body: SafeArea(
          child: !chat.consented
              ? _intro()
              : Column(children: [
                  if (!compactInput)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Text(
                          chat.service.isDemo
                              ? 'Example mode · scripted replies, not live AI'
                              : 'Local AI prototype · AI can make mistakes',
                          style: Theme.of(context).textTheme.labelMedium),
                    ),
                  Expanded(
                      child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (chat.exchanges.isEmpty && !chat.busy) ...[
                        Text('What are you curious about?',
                            style: Theme.of(context).textTheme.titleLarge),
                        const Text(
                            'Type any question in English. These are optional examples.'),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final question in [
                            'Why is the sky blue?',
                            'How do fish breathe underwater?',
                            'I made a mistake at school.'
                          ])
                            ActionChip(
                                label: Text(question),
                                onPressed: () => input.text = question),
                        ]),
                      ],
                      for (final e in chat.exchanges) ...[
                        _bubble('You', e.question, false),
                        _bubble(
                            '${widget.name} · ${e.reply.source == 'ai' ? 'AI' : e.reply.source == 'demo' ? 'Example' : 'Connection / safety fallback'}',
                            e.reply.answer,
                            true),
                        if (e.reply.parentPrompt.isNotEmpty)
                          Card(
                            color: const Color(0xFFE9F4EF),
                            child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Talk together',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text(e.reply.parentPrompt),
                                    const Text(
                                        'Choose a trusted adult who is free. Do not interrupt someone who is driving.',
                                        style: TextStyle(fontSize: 12))
                                  ],
                                )),
                          ),
                        const SizedBox(height: 12),
                      ],
                      if (chat.busy) ...[
                        _bubble('You', chat.pendingQuestion ?? '', false),
                        const LinearProgressIndicator(),
                        const Text('Preparing a reply…'),
                      ],
                    ],
                  )),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: TextField(
                              controller: input,
                              enabled: !chat.busy,
                              maxLength: 600,
                              minLines: 1,
                              maxLines:
                                  MediaQuery.viewInsetsOf(context).bottom > 0
                                      ? 1
                                      : 3,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              decoration: InputDecoration(
                                  isDense: compactInput,
                                  counterText: compactInput ? '' : null,
                                  labelText: compactInput
                                      ? (chat.service.isDemo
                                          ? 'Example mode · Your question'
                                          : 'Local AI · Your question')
                                      : 'Your question',
                                  hintText: 'Ask in English…',
                                  border: const OutlineInputBorder()),
                            )),
                            const SizedBox(width: 8),
                            FilledButton(
                                onPressed: chat.busy ? null : _send,
                                child: const Text('Send')),
                          ])),
                ]),
        ),
      );

  Widget _intro() => ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.forum_outlined, size: 40),
        const SizedBox(height: 12),
        Text('Explore ideas together',
            style: Theme.of(context).textTheme.headlineSmall),
        const Text(
            'English conversations for ages 10–12, with a parent or trusted adult nearby. This character is an AI learning helper, not a person.'),
        const SizedBox(height: 12),
        Text(chat.service.isDemo
            ? 'You are trying scripted examples. Nothing you type is sent to an AI service.'
            : 'Your question and recent chat are sent to the local model on the connected development computer. This prototype does not save chat transcripts or send them to Firebase.'),
        const SizedBox(height: 8),
        const Text(
            'AI can be wrong. Check important answers together. Do not share names, addresses, school details, passwords or other private information. Clearing or leaving this screen removes the chat from this app.'),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: chat.allowSession,
            child: const Text('Start with an adult')),
      ]);

  Widget _bubble(String label, String text, bool assistant) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color:
                assistant ? const Color(0xFFEAF2FA) : const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SelectableText(text),
        ]),
      );
}
