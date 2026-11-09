import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'explore_screen.dart';

/// 안드로이드 호스트(Kotlin `ExploreBridge`)를 통한 Unity 연결.
/// Unity 는 별도 전체 화면(Activity)으로 뜨고, 이 위젯은 그 뒤에 남는 자리 표시다.
const _channel = MethodChannel('allo/explore');

Future<bool> unityExploreAvailable() async {
  try {
    return await _channel.invokeMethod<bool>('available') ?? false;
  } on MissingPluginException {
    return false; // iOS·테스트 등 호스트가 없는 곳
  } on PlatformException {
    return false;
  }
}

/// [ExploreScreen.unityView] 로 넘기는 안드로이드용 Unity 화면.
Widget androidUnityView({
  required void Function(void Function(String json) send,
          [VoidCallback? resume])
      onCreated,
  required void Function(String json) onMessage,
}) =>
    _UnityLauncher(onCreated: onCreated, onMessage: onMessage);

class _UnityLauncher extends StatefulWidget {
  const _UnityLauncher({required this.onCreated, required this.onMessage});

  final void Function(void Function(String json) send, [VoidCallback? resume])
      onCreated;
  final void Function(String json) onMessage;

  @override
  State<_UnityLauncher> createState() => _UnityLauncherState();
}

/// Unity 메시지를 받을 현재 탐험 화면. 없으면 메시지를 버린다.
void Function(String json)? _listener;
bool _hooked = false;

/// 처리기는 앱이 살아 있는 동안 한 번만 등록하고 해제하지 않는다.
/// 해제하면 그사이 온 메시지(예: 지난 회차의 close)를 엔진이 보관했다가
/// 다음 탐험 화면에 넘겨, 새 화면이 열리자마자 닫힌다.
void _hook() {
  if (_hooked) return;
  _hooked = true;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'fromUnity') {
      _listener?.call(call.arguments as String);
    }
  });
}

class _UnityLauncherState extends State<_UnityLauncher> {
  void _mine(String json) => widget.onMessage(json);

  @override
  void initState() {
    super.initState();
    _hook();
    _listener = _mine;
    // resume 은 넘기지 않는다. Unity 는 별도 화면이라, 홈에 다녀오면 안드로이드가 알아서 되살린다.
    // Flutter 화면이 앞에 올 때마다 Unity 를 다시 열면 닫자마자 다시 열린다.
    widget.onCreated((json) => _channel.invokeMethod<void>('send', json));
    _channel.invokeMethod<bool>('open');
  }

  @override
  void dispose() {
    if (_listener == _mine) _listener = null; // 같은 State 의 tear-off 는 == 로 같다
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text('차 안으로 들어가는 중…', style: TextStyle(color: Colors.white70)),
        ),
      );
}
