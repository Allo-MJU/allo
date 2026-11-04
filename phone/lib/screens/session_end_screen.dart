import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../game/game_controller.dart';

/// 차량 종료 후 로컬 저장을 확인하고 다음 연결을 안내한다.
class SessionEndScreen extends StatelessWidget {
  const SessionEndScreen({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final saved = controller.sessionSaved;
          final saving = controller.endingSession;
          final title = saved
              ? '기록을 저장했어요'
              : saving
                  ? '기록을 저장하고 있어요'
                  : '기록을 저장하지 못했어요';
          return PopScope(
            canPop: false,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('주행 종료'),
                automaticallyImplyLeading: false,
              ),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 24),
                          if (saving && !saved) ...[
                            const Center(
                              child: CircularProgressIndicator(
                                semanticsLabel: '주행 기록 저장 중',
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                          Semantics(
                            liveRegion: true,
                            header: true,
                            child: Text(title,
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                          ),
                          const SizedBox(height: 12),
                          Text(saved
                              ? '다음 주행은 차량의 새 QR로 연결해 주세요.'
                              : saving
                                  ? '이번 주행의 기록을 저장하고 있어요. 잠시 기다려 주세요.'
                                  : '저장 중 문제가 생겼어요. 다시 저장해 주세요.'),
                          const SizedBox(height: 24),
                          if (saved) ...[
                            FilledButton(
                              onPressed: () => context.go('/pairing'),
                              child: const Text('새 차량 연결'),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () => context.go('/dex'),
                              child: const Text('도감 보기'),
                            ),
                          ] else if (!saving)
                            FilledButton(
                              onPressed: () async {
                                await controller.endSession();
                              },
                              child: const Text('다시 저장'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}
