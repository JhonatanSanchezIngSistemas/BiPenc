import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:bipenc/servicios/servicio_camara.dart';

class ModalCamaraProducto extends StatelessWidget {
  final ServicioCamara cameraService;
  const ModalCamaraProducto({super.key, required this.cameraService});

  @override
  Widget build(BuildContext context) {
    if (cameraService.controller == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(cameraService.controller!),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.teal, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const Positioned(
          top: 60,
          left: 0,
          right: 0,
          child: Text(
            'Centra el producto en el recuadro\nsobre fondo liso para mejor resultado',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Positioned(
          bottom: 50,
          left: 0,
          right: 0,
          child: Center(
            child: FloatingActionButton.large(
              backgroundColor: Colors.white,
              onPressed: () async {
                final file = await cameraService.takePicture();
                if (context.mounted) Navigator.pop(context, file);
              },
              child: const Icon(Icons.camera, color: Colors.black, size: 40),
            ),
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ],
    );
  }
}
