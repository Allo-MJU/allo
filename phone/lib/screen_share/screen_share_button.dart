import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 개발 빌드 전용. 연결 정보와 캡처 동의는 Android 화면에서 처리한다.
class ScreenShareButton extends StatelessWidget {
  const ScreenShareButton({super.key});
  static const _channel = MethodChannel('ai.allo/screen_share');

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      tooltip: '화면 공유 시제품',
      icon: const Icon(Icons.screen_share_outlined),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'open', child: Text('화면 공유 시작')),
        PopupMenuItem(value: 'stop', child: Text('화면 공유 중지')),
      ],
      onSelected: (method) async {
        try {
          await _channel.invokeMethod<bool>(method);
          if (method == 'stop' && context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('화면 공유를 중지했어요.')));
          }
        } on PlatformException {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('화면 공유를 시작할 수 없어요. 연결 설정을 확인해 주세요.')));
        } on MissingPluginException {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('이 빌드에서는 화면 공유를 지원하지 않아요.')));
        }
      },
    );
  }
}
