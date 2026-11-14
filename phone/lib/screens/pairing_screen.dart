import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../game/game_controller.dart';
import '../pairing/pairing_credentials.dart';
import 'qr_pairing_screen.dart';
import '../screen_share/screen_share_button.dart';

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
  void dispose() {
    _sid.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      appBar:
          AppBar(title: const Text('알로'), actions: const [ScreenShareButton()]),
      body: ListenableBuilder(
        listenable: c,
        builder: (_, __) => Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            children: [
              Text(c.isFake ? '차 없이 알로를 체험해 보세요' : '차 화면의 QR을 찍어 주세요',
                  style: const TextStyle(fontSize: 20)),
              if (c.isFake) const Text('가상 주행으로 알을 품고 도감에 모아요.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => context.go('/dex'),
                icon: const Icon(Icons.auto_stories_outlined),
                label: Text(c.paired ? '도감에서 함께할 친구 고르기' : '내 친구 도감 보기'),
              ),
              if (c.baseCamp != null)
                OutlinedButton.icon(
                    onPressed: () => context.go('/base-camp'),
                    icon: const Icon(Icons.cottage_outlined),
                    label: const Text('우리 거점')),
              if (c.paired)
                const Text('차량과 연결됐어요. 도감의 획득 기록에서 동행할 친구를 골라 주세요.'),
              if (!c.isFake) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: c.busy
                      ? null
                      : () async {
                          final credentials = await Navigator.of(context)
                              .push<PairingCredentials>(MaterialPageRoute(
                                  builder: (_) => const QrPairingScreen()));
                          if (!mounted || credentials == null) return;
                          _sid.text = credentials.sessionId;
                          _code.text = credentials.code;
                          await c.pair(credentials.sessionId,
                              pairCode: credentials.code);
                        },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('QR 스캔'),
                ),
                const Divider(height: 48),
                const Text('QR이 안 되면 연결 정보 직접 입력'),
                TextField(
                    controller: _sid,
                    enabled: !c.busy,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: '세션 ID')),
                TextField(
                    controller: _code,
                    enabled: !c.busy,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: '6자리 코드'),
                    keyboardType: TextInputType.number,
                    maxLength: 6),
                FilledButton.tonal(
                  onPressed: c.busy
                      ? null
                      : () =>
                          c.pair(_sid.text.trim(), pairCode: _code.text.trim()),
                  child: const Text('연결'),
                ),
              ],
              if (c.paired) const Text('차량과 연결됐어요'),
              if (c.pairingNotice != null) Text(c.pairingNotice!),
              if (c.error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(c.error!,
                        style: const TextStyle(color: Colors.red))),
              const SizedBox(height: 24),
              if (c.isFake || c.paired)
                OutlinedButton(
                  onPressed: !c.canStart &&
                          !(c.isFake && c.sessionEnded && c.sessionSaved)
                      ? null
                      : () async {
                          if (c.isFake && c.sessionEnded && c.sessionSaved) {
                            c.prepareNextFakeTrip();
                          }
                          final ready = await c.ensureTripEgg();
                          if (ready && context.mounted) {
                            context.go('/incubating');
                          }
                        },
                  child: Text(c.busy
                      ? '준비 중…'
                      : c.isFake
                          ? c.sessionSaved && c.sessionEnded
                              ? '다음 체험 여행'
                              : '체험 시작'
                          : '차 안으로 가기'),
                ),
              TextButton(
                  onPressed: () => context.go('/dex'),
                  child: const Text('도감 보기')),
            ],
          ),
        ),
      ),
    );
  }
}
