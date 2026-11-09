import 'dart:convert';

import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../scene/window_scene.dart';
import '../widgets/window_view.dart';
import 'explore_link.dart';
import 'explore_messages.dart';

/// Unity 화면을 만드는 함수. [onCreated] 로 Unity 에 보낼 통로(와 앱 복귀 때 부를 resume)를 넘기고,
/// Unity 가 보낸 메시지는 [onMessage] 로 받는다. 실제 앱은 flutter_unity_widget 으로 만든다.
typedef UnityViewBuilder = Widget Function({
  required void Function(void Function(String json) send,
          [VoidCallback? resume])
      onCreated,
  required void Function(String json) onMessage,
});

/// Unity 를 쓸지. `--dart-define=EXPLORE_UNITY=true` 로 켠다 (Unity 내보내기 결과가 있을 때만).
const exploreUnityEnabled = bool.fromEnvironment('EXPLORE_UNITY');

/// 차 안·밖 탐험 화면 (가로). Unity 가 없으면 기존 차 안 뷰([WindowView])로 대체한다.
///
/// 판정은 하지 않는다. [GameController] 의 차 신호·캐릭터를 메시지로 옮겨 보낼 뿐이다.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.controller,
    this.unityAvailable,
    this.unityView,
  });

  final GameController controller;
  final bool? unityAvailable;
  final UnityViewBuilder? unityView;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen>
    with WidgetsBindingObserver {
  final _stabilizer = SceneStabilizer();
  final _jolts = JoltDetector();
  void Function(String)? _send;
  VoidCallback? _resume;
  late final _link = ExploreLink((json) => _send?.call(json));

  bool get _useUnity =>
      (widget.unityAvailable ?? exploreUnityEnabled) &&
      widget.unityView != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_publish);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_publish);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 홈에 다녀오면 Unity 화면이 멈춘 채 남지 않게 다시 그린다
    if (state == AppLifecycleState.resumed) _resume?.call();
  }

  void _publish() {
    final c = widget.controller;
    final scene = _stabilizer.update(WindowScene.fromVehicle(c.vehicle),
        DateTime.now().millisecondsSinceEpoch);
    _link.post('scene', sceneMessage(scene));
    _link.post(
        'cast', castMessage(companion: c.hatched, friends: c.collectedSpecies));
    final v = c.vehicle;
    if (v != null) {
      for (final kind in _jolts.update(v)) {
        _link.post('jolt', joltMessage(kind));
      }
    }
  }

  void _onUnityMessage(String json) {
    Object? msg;
    try {
      msg = jsonDecode(json);
    } on FormatException {
      return; // 깨진 메시지는 무시한다
    }
    if (msg is Map && msg['type'] == 'ready') {
      _publish();
      _link.post(
          'settings',
          settingsMessage(
              gyro: true,
              reducedMotion:
                  MediaQuery.maybeDisableAnimationsOf(context) ?? false));
      _link.onReady();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        if (_useUnity)
          widget.unityView!(
            onCreated: (send, [resume]) {
              _send = send;
              _resume = resume;
            },
            onMessage: _onUnityMessage,
          )
        else
          LayoutBuilder(
            builder: (context, box) => ListenableBuilder(
              listenable: c,
              builder: (context, _) => WindowView(
                vehicle: c.vehicle,
                height: box.maxHeight,
                friends: c.collectedSpecies,
              ),
            ),
          ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton.filledTonal(
              tooltip: '돌아가기',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ]),
    );
  }
}
