import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class EscanerContinuo extends StatefulWidget {
  final void Function(String code) onCode;
  const EscanerContinuo({super.key, required this.onCode});

  @override
  State<EscanerContinuo> createState() => _EscanerContinuoState();
}

class _EscanerContinuoState extends State<EscanerContinuo> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (capture.barcodes.isEmpty) return;
            final code = capture.barcodes.first.rawValue;
            if (code == null) return;
            HapticFeedback.lightImpact();
            SystemSound.play(SystemSoundType.click);
            widget.onCode(code);
          },
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Modo continuo activo',
                  style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      ],
    );
  }
}
