import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../game/game_controller.dart';
import '../theme/allo_colors.dart';
import '../widgets/character_stage.dart';

class CompanionScreen extends StatefulWidget {
  const CompanionScreen({super.key, required this.controller});
  final GameController controller;

  @override
  State<CompanionScreen> createState() => _CompanionScreenState();
}

class _CompanionScreenState extends State<CompanionScreen> {
  GameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]));
  }

  @override
  void dispose() {
    // 진입/이탈 요청을 순서대로 전송한다. 다른 화면의 방향을 잠그지 않는다.
    unawaited(SystemChrome.setPreferredOrientations(const []));
    super.dispose();
  }

  Future<void> _arrive() async {
    final saved = await controller.endSession();
    if (saved && mounted) context.go('/dex');
  }

  Widget _menu() => PopupMenuButton<String>(
        tooltip: '동행 메뉴',
        constraints: const BoxConstraints(minWidth: 180),
        style: IconButton.styleFrom(minimumSize: const Size.square(56)),
        onSelected: (action) {
          if (action == 'arrive') unawaited(_arrive());
          if (action == 'end') controller.endFakeTrip();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'arrive', height: 56, child: Text('도착')),
          if (controller.isFake)
            const PopupMenuItem(value: 'end', height: 56, child: Text('주행 종료')),
        ],
      );

  Widget _details(Widget message) {
    final prompt = controller.lookOutPrompt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.error != null) ...[
          Semantics(liveRegion: true, child: Text(controller.error!)),
          const SizedBox(height: 8),
        ],
        message,
        const SizedBox(height: 12),
        Text(prompt.$1, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 4),
        Text(prompt.$2,
            style: const TextStyle(
                color: AlloColors.actionPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('먹이 ${controller.feedCount}회 · 놀이 ${controller.playCount}회'),
        Text('발견 ${controller.lookOutCount}회'),
      ],
    );
  }

  Widget _careButtons() => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                    minimumSize: const Size(56, 56),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                onPressed: controller.feedCompanion,
                child: const Text('먹이', textAlign: TextAlign.center)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                    minimumSize: const Size(56, 56),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                onPressed: controller.playWithCompanion,
                child: const Text('놀아주기', textAlign: TextAlign.center)),
          ),
        ],
      );

  Widget _lookButton() => FilledButton(
        style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 72),
            backgroundColor: AlloColors.actionPrimary,
            foregroundColor: AlloColors.textInverse),
        onPressed: controller.lookOut,
        child: const Text('봤어!'),
      );

  Widget _portrait(Widget scene, Widget message) => ListView(
        children: [
          const Text('휴대폰을 가로로 돌리면 장면과 버튼을 함께 볼 수 있어요.',
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          scene,
          const SizedBox(height: 12),
          _details(message),
          const SizedBox(height: 16),
          _careButtons(),
          const SizedBox(height: 8),
          _lookButton(),
          OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(56, 56)),
              onPressed: _arrive,
              child: const Text('도착')),
        ],
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, screen) {
            final landscape = screen.maxWidth >= screen.maxHeight &&
                screen.maxWidth >= 560 &&
                screen.maxHeight >= 300;
            return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                toolbarHeight: 56,
                title: Text(controller.hatched?.nameKo ?? '동행',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                actions: [
                  IconButton(
                      tooltip: '도감',
                      style: IconButton.styleFrom(
                          minimumSize: const Size.square(56)),
                      onPressed: () => context.go('/dex'),
                      icon: const Icon(Icons.grid_view_rounded)),
                  if (!landscape && controller.isFake)
                    TextButton(
                        style: TextButton.styleFrom(
                            minimumSize: const Size(56, 56)),
                        onPressed: controller.endFakeTrip,
                        child: const Text('주행 종료')),
                  _menu(),
                ],
              ),
              body: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: LayoutBuilder(builder: (context, body) {
                    final panelWidth =
                        (body.maxWidth * .28).clamp(192.0, 256.0);
                    final useLandscape = landscape &&
                        body.maxHeight >= 200 &&
                        body.maxWidth - panelWidth - 12 >= 220;
                    return CharacterStage(
                      controller: controller,
                      sceneSize: useLandscape
                          ? Size(
                              body.maxWidth - panelWidth - 12, body.maxHeight)
                          : null,
                      layoutBuilder: (scene, message) {
                        if (!useLandscape) return _portrait(scene, message);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: SizedBox.expand(
                                key: const ValueKey('companion-game-scene'),
                                child: scene,
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              key: const ValueKey('companion-controls'),
                              width: panelWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                      child: SingleChildScrollView(
                                          child: _details(message))),
                                  const SizedBox(height: 8),
                                  _careButtons(),
                                  const SizedBox(height: 8),
                                  _lookButton(),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  }),
                ),
              ),
            );
          },
        ),
      );
}
