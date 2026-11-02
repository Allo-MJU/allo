import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../game/game_controller.dart';

/// QR 스캔 또는 6자리 코드. 이름·생년월일·연락처 입력란은 만들지 않는다.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, required this.controller});
  final GameController controller;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _sid = TextEditingController();
  final _code = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(title: const Text('알로')),
      body: ListenableBuilder(
        listenable: c,
        builder: (_, __) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('차 화면의 QR을 찍어 주세요', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  // TODO(B): mobile_scanner 로 "allo://pair?sid=...&code=..." 파싱 → c.pair(sid, pairCode: code)
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('QR 스캔'),
              ),
              const Divider(height: 48),
              const Text('QR이 안 되면 코드로'),
              TextField(controller: _sid, decoration: const InputDecoration(labelText: '세션 ID')),
              TextField(controller: _code, decoration: const InputDecoration(labelText: '6자리 코드'), keyboardType: TextInputType.number, maxLength: 6),
              FilledButton.tonal(
                onPressed: () => c.pair(_sid.text.trim(), pairCode: _code.text.trim()),
                child: const Text('연결'),
              ),
              if (c.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(c.error!, style: const TextStyle(color: Colors.red))),
              const Spacer(),
              OutlinedButton(
                onPressed: () async {
                  await c.startIncubating(EggTier.small);
                  if (context.mounted) context.go('/incubating');
                },
                child: const Text('연결 없이 시작 (fake feed)'),
              ),
              TextButton(onPressed: () => context.go('/dex'), child: const Text('도감 보기')),
            ],
          ),
        ),
      ),
    );
  }
}
