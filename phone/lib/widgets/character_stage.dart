import 'dart:async';
import 'dart:math' as math;

import 'package:allo_core/allo_core.dart';
import 'package:flutter/material.dart';

import '../character/character_behavior.dart';
import '../game/game_controller.dart';
import '../theme/allo_colors.dart';
import 'species_art.dart';
import 'window_view.dart';

/// 동행 화면 안에서만 살아 있는 표현 상태. 게임 판정·서버 전송은 변경하지 않는다.
class CharacterStage extends StatefulWidget {
  const CharacterStage({super.key, required this.controller, this.nowMs});
  final GameController controller;
  final int Function()? nowMs;

  @override
  State<CharacterStage> createState() => _CharacterStageState();
}

class _CharacterStageState extends State<CharacterStage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _behavior = CharacterBehavior();
  final _clock = Stopwatch()..start();
  late final _feedback = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );
  Timer? _deadline;
  Offset _drag = Offset.zero;
  bool _dragging = false;
  bool _active = true;
  bool _reduceMotion = false;
  bool _awaitVehicleBaseline = false;
  int? _resumeVehicleTs;
  String? _eggId;
  int _feeds = 0, _plays = 0, _looks = 0;

  int get _now => widget.nowMs?.call() ?? _clock.elapsedMilliseconds;
  bool get _enabled =>
      _active &&
      widget.controller.game.stage == Stage.hatched &&
      !widget.controller.sessionEnded &&
      !widget.controller.endingSession;

  @override
  void initState() {
    super.initState();
    _active = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onController);
    _baseline();
  }

  void _baseline() {
    final c = widget.controller;
    _behavior.reset();
    _eggId = c.eggId;
    _feeds = c.feedCount;
    _plays = c.playCount;
    _looks = c.lookOutCount;
    _dragging = false;
    _drag = Offset.zero;
    _feedback.stop();
    _feedback.value = 1;
    if (_enabled) _observeVehicle();
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _feedback.stop();
      _feedback.value = 1;
    }
  }

  @override
  void didUpdateWidget(CharacterStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _awaitVehicleBaseline = false;
      _resumeVehicleTs = null;
      _baseline();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) {
      _awaitVehicleBaseline = true;
      _resumeVehicleTs = widget.controller.vehicle?.ts;
    }
    setState(_baseline);
  }

  void _observeVehicle() {
    final vehicle = widget.controller.vehicle;
    if (_awaitVehicleBaseline) {
      // 중단 전 캐시를 기준으로 삼으면 복귀 첫 신호가 과거 급변을 재생한다.
      if (vehicle == null ||
          (_resumeVehicleTs != null && vehicle.ts <= _resumeVehicleTs!)) {
        return;
      }
      _awaitVehicleBaseline = false;
    }
    _behavior.observe(vehicle, _now);
  }

  void _onController() {
    if (!mounted) return;
    setState(() {
      final c = widget.controller;
      if (!_enabled || _eggId != c.eggId) {
        if (_eggId != c.eggId) {
          _awaitVehicleBaseline = false;
          _resumeVehicleTs = null;
        }
        _baseline();
        return;
      }
      final revision = _behavior.revision;
      _behavior.advance(_now);
      // 차량 급변이 먹이·놀이 같은 낮은 우선순위 반응을 덮도록 먼저 처리한다.
      _observeVehicle();
      if (c.feedCount > _feeds) _behavior.interact(CharacterEvent.feed, _now);
      if (c.playCount > _plays) _behavior.interact(CharacterEvent.play, _now);
      if (c.lookOutCount > _looks) {
        _behavior.interact(CharacterEvent.lookOut, _now);
      }
      _feeds = c.feedCount;
      _plays = c.playCount;
      _looks = c.lookOutCount;
      if (_dragging && _behavior.event != CharacterEvent.dragStart) {
        _dragging = false;
        _drag = Offset.zero;
      }
      _refresh(revision);
    });
  }

  void _schedule() {
    _deadline?.cancel();
    _deadline = null;
    final deadline = _behavior.nextDeadlineMs;
    if (!_enabled || deadline == null) return;
    _deadline = Timer(Duration(milliseconds: math.max(1, deadline - _now)), () {
      if (!mounted || !_enabled) return;
      setState(() {
        final revision = _behavior.revision;
        _behavior.advance(_now);
        _refresh(revision);
      });
    });
  }

  void _refresh(int revision) {
    if (_behavior.revision != revision) {
      if (_behavior.event != null && !_reduceMotion && !_dragging) {
        _feedback.forward(from: 0);
      } else {
        _feedback.stop();
        _feedback.value = 1;
      }
    }
    _schedule();
  }

  bool _interact(CharacterEvent event) {
    if (!_enabled) return false;
    var accepted = false;
    setState(() {
      final revision = _behavior.revision;
      accepted = _behavior.interact(event, _now);
      _refresh(revision);
    });
    return accepted;
  }

  void _startDrag(DragStartDetails details) {
    if (_interact(CharacterEvent.dragStart)) {
      setState(() {
        _dragging = true;
        _feedback.value = 1;
      });
    }
  }

  void _endDrag() {
    if (!_dragging) return;
    setState(() {
      _dragging = false;
      _drag = Offset.zero;
    });
    _interact(CharacterEvent.dragEnd);
  }

  String get _message {
    final event = _behavior.event;
    if ((event == CharacterEvent.feed || event == CharacterEvent.play) &&
        widget.controller.companionMessage != null) {
      return widget.controller.companionMessage!;
    }
    return _behavior.message ??
        switch (_behavior.pose) {
          CharacterPose.move => '같이 달리는 중이야.',
          CharacterPose.sleep => '잠깐 쉬고 있을게.',
          _ => '캐릭터를 누르거나 움직여 보세요.',
        };
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final pose = _behavior.pose;
    final (label, icon) = switch (pose) {
      CharacterPose.idle => ('기본', Icons.sentiment_neutral),
      CharacterPose.move => ('이동', Icons.directions_run),
      CharacterPose.happy => ('기쁨', Icons.sentiment_very_satisfied),
      CharacterPose.surprised => ('놀람', Icons.priority_high),
      CharacterPose.sleep => ('휴식', Icons.bedtime),
    };
    return Column(children: [
      WindowView(
          vehicle: c.vehicle,
          child: SizedBox(
            height: 184,
            width: double.infinity,
            child: LayoutBuilder(builder: (context, constraints) {
              final size =
                  math.min(112.0, math.max(56.0, constraints.maxWidth - 32));
              final horizontal =
                  math.max(0.0, (constraints.maxWidth - size) / 2 - 12);
              final top = -(constraints.maxHeight - size - 20);
              final offset = Offset(_drag.dx.clamp(-horizontal, horizontal),
                  _drag.dy.clamp(top, 0.0));
              return Stack(clipBehavior: Clip.hardEdge, children: [
                AnimatedPositioned(
                  duration: _dragging || _reduceMotion
                      ? Duration.zero
                      : AlloPresentation.fadeDuration,
                  curve: AlloPresentation.standardCurve,
                  left: (constraints.maxWidth - size) / 2 + offset.dx,
                  bottom: 12 - offset.dy,
                  width: size,
                  height: size,
                  child: Semantics(
                    button: true,
                    enabled: _enabled,
                    label: '${c.hatched?.nameKo ?? "캐릭터"}, $label',
                    hint: '누르면 반응해요. 길게 끌어 이동하고 놓아 보세요.',
                    onTap:
                        _enabled ? () => _interact(CharacterEvent.tap) : null,
                    child: GestureDetector(
                      key: const ValueKey('character-touch-target'),
                      behavior: HitTestBehavior.opaque,
                      excludeFromSemantics: true,
                      onTap:
                          _enabled ? () => _interact(CharacterEvent.tap) : null,
                      onPanStart: _enabled ? _startDrag : null,
                      onPanUpdate: _enabled
                          ? (details) {
                              if (!_dragging) return;
                              setState(() {
                                _drag = Offset(
                                    (_drag.dx + details.delta.dx)
                                        .clamp(-horizontal, horizontal),
                                    (_drag.dy + details.delta.dy)
                                        .clamp(top, 0.0));
                              });
                            }
                          : null,
                      onPanEnd: _enabled ? (_) => _endDrag() : null,
                      onPanCancel: _enabled ? _endDrag : null,
                      child: ExcludeSemantics(
                          child: AnimatedBuilder(
                        animation: _feedback,
                        builder: (_, child) {
                          final wave = _reduceMotion || _dragging
                              ? 0.0
                              : math.sin(_feedback.value * math.pi * 2) *
                                  (1 - _feedback.value);
                          return Transform.translate(
                            offset: Offset(
                                pose == CharacterPose.surprised ? wave * 5 : 0,
                                pose == CharacterPose.happy
                                    ? -wave.abs() * 10
                                    : pose == CharacterPose.move
                                        ? -wave.abs() * 5
                                        : 0),
                            child: Transform.rotate(
                                angle: pose == CharacterPose.surprised
                                    ? wave * .08
                                    : 0,
                                child: Transform.scale(
                                    scale: pose == CharacterPose.happy
                                        ? 1 + wave.abs() * .06
                                        : 1,
                                    child: child)),
                          );
                        },
                        child: Stack(children: [
                          Center(
                              child: c.hatched == null
                                  ? Icon(Icons.pets,
                                      size: size * .85,
                                      color: AlloColors.actionPrimary)
                                  : SpeciesArt(
                                      species: c.hatched!, size: size * .85)),
                          Positioned(
                              right: 2,
                              bottom: 2,
                              child: DecoratedBox(
                                  decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle),
                                  child: Padding(
                                      padding: const EdgeInsets.all(5),
                                      child: Icon(icon,
                                          size: 22,
                                          color: AlloColors.actionPrimary)))),
                        ]),
                      )),
                    ),
                  ),
                ),
              ]);
            }),
          )),
      const SizedBox(height: 12),
      Semantics(
          liveRegion: true,
          child: Text(_enabled ? _message : '캐릭터 반응을 쉬고 있어요.',
              key: const ValueKey('character-reaction-message'),
              textAlign: TextAlign.center)),
    ]);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    WidgetsBinding.instance.removeObserver(this);
    _deadline?.cancel();
    _feedback.dispose();
    _clock.stop();
    super.dispose();
  }
}
