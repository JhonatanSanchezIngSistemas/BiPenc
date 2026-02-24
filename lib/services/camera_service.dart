import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  /// Inicializa la cámara trasera (por defecto) con una resolución óptima.
  Future<void> initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception('No se encontraron cámaras disponibles en el dispositivo.');
      }

      // Buscar cámara trasera o usar la primera disponible
      final backCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false, // No necesitamos audio para tomar fotos de productos
      );

      await _controller!.initialize();
    } catch (e) {
      debugPrint('Error inicializando la cámara: $e');
      rethrow;
    }
  }

  /// Devuelve el controlador para conectarlo al CameraPreview.
  CameraController? get controller => _controller;

  /// Captura la imagen de alta calidad desde el lente de la cámara.
  Future<XFile?> takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      debugPrint('Controlador de cámara no preparado.');
      return null;
    }

    if (_controller!.value.isTakingPicture) {
      return null;
    }

    try {
      final XFile picture = await _controller!.takePicture();
      return picture;
    } on CameraException catch (e) {
      debugPrint('Error nativo al capturar fotografía: $e');
      return null;
    }
  }

  void dispose() {
    _controller?.dispose();
  }
}
