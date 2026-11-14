import 'dart:async';
import 'package:flutter/material.dart';
import '../explore/explore_screen.dart';
import '../explore/unity_channel.dart';
import '../pairing/pairing_credentials.dart';
import '../screens/qr_pairing_screen.dart';
import 'unity_app_controller.dart';

/// Invisible Flutter host; Unity owns application navigation and visible UI.
class UnityAppScreen extends StatefulWidget {
  const UnityAppScreen({
    super.key,
    required this.controller,
    required this.unityView,
    this.pairingScannerBuilder,
  });
  final UnityAppController controller;
  final UnityViewBuilder unityView;
  final WidgetBuilder? pairingScannerBuilder;
  @override
  State<UnityAppScreen> createState() => _UnityAppScreenState();
}

class _UnityAppScreenState extends State<UnityAppScreen>
    with WidgetsBindingObserver {
  VoidCallback? _resume;
  Completer<PairingCredentials?>? _scanCancellation;
  MaterialPageRoute<PairingCredentials>? _scannerRoute;
  NavigatorState? _scannerNavigator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unityExploreOpen.value = true;
    _registerScanner();
  }

  void _registerScanner() {
    widget.controller.pairingScanner ??= _scanPairingQr;
  }

  void _unregisterScanner(UnityAppController controller) {
    if (controller.pairingScanner == _scanPairingQr) {
      controller.pairingScanner = null;
    }
  }

  @override
  void didUpdateWidget(UnityAppScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _unregisterScanner(oldWidget.controller);
      _cancelScanner();
      _registerScanner();
    }
  }

  Future<PairingCredentials?> _scanPairingQr() async {
    if (!mounted || _scanCancellation != null) return null;
    final cancellation = Completer<PairingCredentials?>();
    _scanCancellation = cancellation;
    try {
      // Disposal must settle the controller request even if native close is late.
      return await Future.any([
        _showScanner(cancellation),
        cancellation.future,
      ]);
    } finally {
      if (_scanCancellation == cancellation) _scanCancellation = null;
    }
  }

  bool _scanIsCurrent(Completer<PairingCredentials?> cancellation) =>
      mounted && _scanCancellation == cancellation && !cancellation.isCompleted;

  Future<PairingCredentials?> _showScanner(
      Completer<PairingCredentials?> cancellation) async {
    await closeUnityExplore(requireHost: true);
    if (!mounted || !_scanIsCurrent(cancellation)) return null;
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute<PairingCredentials>(
      builder: widget.pairingScannerBuilder ?? (_) => const QrPairingScreen(),
    );
    _scannerRoute = route;
    _scannerNavigator = navigator;
    try {
      final credentials = await navigator.push(route);
      if (!_scanIsCurrent(cancellation)) return null;
      final opened = await openUnityExplore();
      if (!_scanIsCurrent(cancellation)) return null;
      if (!opened) {
        throw const PairingException('차 안 화면으로 돌아갈 수 없어요. 다시 시도해 주세요.');
      }
      return credentials;
    } finally {
      if (_scannerRoute == route) {
        _scannerRoute = null;
        _scannerNavigator = null;
      }
    }
  }

  void _cancelScanner() {
    final cancellation = _scanCancellation;
    _scanCancellation = null;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete(null);
    }
    final route = _scannerRoute;
    final navigator = _scannerNavigator;
    _scannerRoute = null;
    _scannerNavigator = null;
    // Navigator can be locked while the host is being removed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route != null && navigator?.mounted == true && route.isActive) {
        navigator!.removeRoute(route);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _scanCancellation == null) {
      _resume?.call();
    }
  }

  @override
  void dispose() {
    _unregisterScanner(widget.controller);
    _cancelScanner();
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
