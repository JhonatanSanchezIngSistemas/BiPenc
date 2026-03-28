import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ModalEscaner extends StatefulWidget {
  final String title;
  const ModalEscaner({super.key, this.title = 'Escanear Código'});

  @override
  State<ModalEscaner> createState() => _ModalEscanerState();
}

class _ModalEscanerState extends State<ModalEscaner> {
  final MobileScannerController controller = MobileScannerController(
    formats: [BarcodeFormat.all],
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
  );

  bool _popped = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {
            if (!_popped) {
              _popped = true;
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, state, child) {
              final torchIcon = state.torchState == TorchState.on
                  ? Icons.flash_on
                  : Icons.flash_off;
              return IconButton(
                icon: Icon(torchIcon, color: Colors.white),
                onPressed: () => controller.toggleTorch(),
              );
            },
          ),
          ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, state, child) {
              final cameraIcon = controller.facing == CameraFacing.front
                  ? Icons.camera_front
                  : Icons.camera_rear;
              return IconButton(
                icon: Icon(cameraIcon, color: Colors.white),
                onPressed: () => controller.switchCamera(),
              );
            },
          ),
        ],
      ),
      body: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Stack(
          children: [
            MobileScanner(
              controller: controller,
              onDetect: (capture) {
                if (_popped) return;
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final String? code = barcodes.first.rawValue;
                  if (code != null) {
                    _popped = true;
                    Navigator.pop(context, code);
                  }
                }
              },
            ),
            // Máscara de escaneo
            Center(
              child: Container(
                width: 250,
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.teal, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Text(
                'Apunta al código de barras',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Función auxiliar para abrir el escáner
Future<String?> openScanner(BuildContext context, {String title = 'Escanear Código'}) async {
  return await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.black,
    builder: (context) => ModalEscaner(title: title),
  );
}
