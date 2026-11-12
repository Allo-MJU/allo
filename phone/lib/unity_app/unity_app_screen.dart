import 'dart:async';
import 'package:flutter/material.dart';
import '../explore/explore_screen.dart';
import 'unity_app_controller.dart';

/// Invisible Flutter host; Unity owns application navigation and visible UI.
class UnityAppScreen extends StatefulWidget {
  const UnityAppScreen(
      {super.key, required this.controller, required this.unityView});
  final UnityAppController controller;
  final UnityViewBuilder unityView;
  @override
  State<UnityAppScreen> createState() => _UnityAppScreenState();
}

class _UnityAppScreenState extends State<UnityAppScreen>
    with WidgetsBindingObserver {
  VoidCallback? _resume;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unityExploreOpen.value = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resume?.call();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unityExploreOpen.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: Colors.black,
      child: widget.unityView(
        onCreated: (send, [resume]) {
          _resume = resume;
          widget.controller.attach(send);
        },
        onMessage: (message) {
          unawaited(widget.controller.handleMessage(message));
        },
      ));
}
