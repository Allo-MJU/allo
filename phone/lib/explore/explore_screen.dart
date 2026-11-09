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

/// Unity 탐험 화면이 앞에 떠 있는지. Unity 는 별도 안드로이드 화면이라, 이때 Flutter 는
/// 백그라운드로 보이지만 아이는 같은 앱에서 놀고 있다. 앱 활성 판단([appActiveFor])에 쓴다.
final unityExploreOpen = ValueNotifier<bool>(false);

/// 게임 진행(알 성장·주행 신호 처리)을 할지. 평소에는 Flutter 화면이 보일 때만,
/// Unity 탐험 화면이 열려 있으면 Flutter 가 가려져 있어도 진행한다.
/// 단 앱이 끝나는 중(detached)이면 멈춘다.
bool appActiveFor(AppLifecycleState state, {required bool unityOpen}) =>
    state == AppLifecycleState.resumed ||
    (unityOpen && state != AppLifecycleState.detached);

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

  /// Unity 가 close 를 보냈다. 닫히는 동안 앱 복귀가 와도 Unity 를 다시 열지 않는다.
  bool _closing = false;
  late final _link = ExploreLink((json) => _send?.call(json));

  bool get _useUnity =>
      (widget.unityAvailable ?? exploreUnityEnabled) &&
      widget.unityView != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_publish);
    if (_useUnity) unityExploreOpen.value = true;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_publish);
    if (_useUnity) unityExploreOpen.value = false;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 홈에 다녀오면 Unity 화면이 멈춘 채 남지 않게 다시 그린다
    if (state == AppLifecycleState.resumed && !_closing) _resume?.call();
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
    if (msg is Map && msg['type'] == 'close') {
      // 뒤로 가기는 Unity(close)와 Flutter(시스템 뒤로 가기) 양쪽에 들어올 수 있다.
      // 탐험 화면이 아직 맨 위일 때 한 번만 닫는다. 두 번 닫으면 아래 화면까지 닫힌다.
      final wasClosing = _closing;
      _closing = true;
      unityExploreOpen.value = false;
      if (!wasClosing &&
          mounted &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        Navigator.of(context).pop();
      }
      return;
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
