import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../pairing/pairing_credentials.dart';

class QrPairingScreen extends StatefulWidget {
  const QrPairingScreen({super.key});

  @override
  State<QrPairingScreen> createState() => _QrPairingScreenState();
}

class _QrPairingScreenState extends State<QrPairingScreen> {
  bool _completed = false;
  String? _error;

  void _onDetect(BarcodeCapture capture) {
    if (_completed || !mounted) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      try {
        final credentials = PairingCredentials.fromQr(raw);
        _completed = true;
        Navigator.of(context).pop(credentials);
        return;
      } on PairingException catch (e) {
        if (_error != e.message) setState(() => _error = e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('차량 QR 스캔')),
        body: Column(children: [
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text('차량 화면의 QR을 사각형 안에 맞춰 주세요.')),
          Expanded(
              child: MobileScanner(
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        '카메라를 사용할 수 없어요. 설정에서 카메라 권한을 허용하거나 돌아가서 연결 정보를 입력해 주세요.'))),
          )),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          SafeArea(
              top: false,
              child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('돌아가서 직접 입력'))),
        ]),
      );
}
