import 'dart:async';
import 'dart:convert';

import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../child_chat/chat_screen.dart';
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

/// 탐험 화면이 떠 있는지 (Unity·대체 화면 모두). 품기 화면이 이 동안 부화 화면으로 넘기지 않는다
final exploreScreenOpen = ValueNotifier<bool>(false);

/// 마지막으로 닫힌 탐험 화면에서 품던 알이 깨어나는 연출을 Unity 가 보여 줬는지.
/// [exploreScreenOpen] 이 꺼지기 전에 정해 둔다
bool exploreHatchShown = false;

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
/// 판정은 하지 않는다. [GameController] 의 차 신호·캐릭터를 메시지로 옮겨 보내고,
/// Unity 가 보낸 의도(tap·feed·endTrip·spotted)를 컨트롤러의 같은 동작으로 넘길 뿐이다.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.controller,
    this.unityAvailable,
    this.unityView,
    this.closeUnity,
  });

  final GameController controller;
  final bool? unityAvailable;
  final UnityViewBuilder? unityView;

  /// Flutter 쪽에서 Unity 화면을 내릴 때 (주행 종료·도착으로 이 화면이 닫힐 때). 없으면 아무것도 안 한다
  final Future<void> Function()? closeUnity;

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
  int _toastSeq = 0;
  (int, int)? _careKey; // (feedCount, playCount) — 바뀔 때만 동행 반응 문구를 보낸다

  /// 이 화면이 열린 동안 품던 알이 깨어났다 (Unity 가 둥지에서 깨어나는 연출을 했다).
  /// 닫을 때 결과로 돌려줘서, 품기 화면이 부화 화면을 다시 보여 주지 않고 동행 화면으로 가게 한다
  bool _hatchShown = false;
  bool _unityReady = false;
  bool _sawIncubating = false;
  String? _incubatingEggId;

  bool get _useUnity =>
      (widget.unityAvailable ?? exploreUnityEnabled) &&
      widget.unityView != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_publish);
    if (_useUnity) unityExploreOpen.value = true;
    exploreHatchShown = false;
    exploreScreenOpen.value = true;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_publish);
    exploreHatchShown = _hatchShown;
    exploreScreenOpen.value = false;
    if (_useUnity) {
      unityExploreOpen.value = false;
      // Flutter 가 먼저 이 화면을 떠나면(주행 종료 → 종료 화면) 앞에 떠 있는 Unity 도 내린다
      if (!_closing) {
        _closing = true;
        unawaited(widget.closeUnity?.call());
      }
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _settings() => settingsMessage(
        gyro: true,
        reducedMotion:
            mounted && (MediaQuery.maybeDisableAnimationsOf(context) ?? false),
        canEndTrip: widget.controller.isFake &&
            !widget.controller.sessionEnded &&
            !widget.controller.endingSession,
      );

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
        'route',
        routeMessage(c.vehicle?.turns ?? const [],
            headingDeg: c.vehicle?.headingDeg,
            cornering: c.vehicle?.cornering));
    final g = c.game;
    if (g.stage == Stage.incubating) {
      _hatchShown = false;
      _sawIncubating = true;
      _incubatingEggId = c.eggId;
    }
    final born = g.stage == Stage.hatched &&
        _sawIncubating &&
        _incubatingEggId == c.eggId;
    // 알을 먼저 보낸다: 같은 알이 깨어났다는 걸 Unity 가 알아야 새 동행을 둥지에서 꺼낸다
    _link.post(
        'egg',
        eggMessage(
            stage: g.stage,
            progress: g.progress,
            eggId: c.eggId,
            tier: g.eggTier,
            bornText: born ? bornToast(c.hatched?.nameKo) : null));
    _link.post(
        'cast', castMessage(companion: c.hatched, friends: c.collectedSpecies));
    final v = c.vehicle;
    if (v != null) {
      for (final kind in _jolts.update(v)) {
        _link.post('jolt', joltMessage(kind));
      }
    }
    _link.post('settings', _settings());
    // 동행 반응 문구(먹이·놀이)는 횟수가 바뀔 때 한 번
    final key = (c.feedCount, c.playCount);
    if (_careKey != null && key != _careKey && c.companionMessage != null) {
      _link.post('toast', toastMessage(c.companionMessage!, ++_toastSeq));
    }
    _careKey = key;
    // 주행이 끝나면(체험 종료·도착) Unity 를 내린다. 어느 화면으로 갈지는 앱 라우팅이 정한다
    if (c.sessionEnded && _useUnity && !_closing) {
      _closing = true;
      unityExploreOpen.value = false;
      unawaited(widget.closeUnity?.call());
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        Navigator.of(context).pop();
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
        Navigator.of(context).pop(_hatchShown);
      }
      return;
    }
    if (msg is Map && msg['type'] == 'ready') {
      _unityReady = true;
      _publish();
      _link.post('settings', _settings());
      _link.onReady();
      return;
    }
    if (msg is! Map) return;
    final c = widget.controller;
    switch (msg['type']) {
      case 'hatchShown':
        // 상태 발행/ready 는 연출 완료가 아니다. 현재 화면에서 품던 같은 알의
        // Unity 완료 확인만 인정한다. 구 Unity export 는 확인을 안 보내므로
        // 닫을 때 기존 Flutter 부화 화면으로 안전하게 돌아간다.
        if (_useUnity &&
            _unityReady &&
            mounted &&
            !_closing &&
            (ModalRoute.of(context)?.isCurrent ?? false) &&
            !c.sessionEnded &&
            c.game.stage == Stage.hatched &&
            _sawIncubating &&
            _incubatingEggId == c.eggId &&
            msg['eggId'] == (c.eggId ?? '')) {
          _hatchShown = true;
        }

      case 'care': // 품는 알 돌보기 (kind: tap·rub·sing·blanket). 품기 화면의 감싸기·노래와 같다
        c.care();
      case 'tap': // 동행 캐릭터와 놀기 (kind: pet·ball·plush·cushion·blanket·draw·bobble·toycar·music·book·bubble·tissue·nest, 없으면 탭)
        c.playWithCompanion(msg['kind'] as String?);
      case 'feed': // kind: apple·shell·acorn·fishbun
        c.feedCompanion(msg['kind'] as String?);
      case 'drink':
        c.feedCompanion('water');
      case 'lookTogether': // 동행이 가리킨 창밖을 아이가 같이 봄 = 창밖 보기
        c.lookOut();
        _link.post('toast', toastMessage('같이 봤어요!', ++_toastSeq));
      case 'endTrip': // 체험 주행에서만 (Unity 는 settings.canEndTrip 일 때만 버튼을 보인다)
        c.endFakeTrip();
      case 'spotted': // 창밖 친구 발견 = "봤어!"
        final id = msg['id'];
        c.lookOut();
        final name = c.collectedSpecies
            .where((s) => s.id == id)
            .map((s) => s.nameKo)
            .firstOrNull;
        _link.post('toast', toastMessage(spottedToast(name), ++_toastSeq));
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
        if (!_useUnity && c.hatched != null)
          const SafeArea(
              child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                      padding: EdgeInsets.all(16), child: ChildChatButton()))),
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
