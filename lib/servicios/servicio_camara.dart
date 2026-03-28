import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class ServicioCamara {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initializing = false;

  /// Inicializa la cámara trasera (por defecto) con una resolución óptima.
  Future<void> initialize() async {
    if (_initializing) return;
    if (!_isCameraSupported()) {
      debugPrint('Cámara no soportada en esta plataforma.');
      return;
    }
    try {
      _initializing = true;
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception('No se encontraron cámaras disponibles en el dispositivo.');
      }

      // Buscar cámara trasera o usar la primera disponible
      final backCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      await _controller?.dispose();
      _controller = null;

      Future<void> initWithPreset(ResolutionPreset preset) async {
        _controller = CameraController(
          backCamera,
          preset,
          enableAudio: false,
        );
        await _controller!.initialize();
      }

      try {
        await initWithPreset(ResolutionPreset.high);
      } on CameraException {
        // Fallback para dispositivos con limitaciones de memoria/cámara.
        await initWithPreset(ResolutionPreset.medium);
      }
    } catch (e) {
      debugPrint('Error inicializando la cámara: $e');
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  /// Devuelve el controlador para conectarlo al CameraPreview.
  CameraController? get controller => _controller;

  /// Captura la imagen de alta calidad desde el lente de la cámara.
  Future<XFile?> takePicture() async {
    if (!_isCameraSupported()) return null;
    if (_controller == null || !_controller!.value.isInitialized) {
      try {
        await initialize();
      } catch (_) {}
    }

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

  bool _isCameraSupported() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Alterna el modo de flash entre Auto, Siempre y Apagado.
  Future<void> toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    FlashMode nextMode;
    switch (_controller!.value.flashMode) {
      case FlashMode.off: nextMode = FlashMode.auto; break;
      case FlashMode.auto: nextMode = FlashMode.always; break;
      case FlashMode.always: nextMode = FlashMode.off; break;
      default: nextMode = FlashMode.off;
    }
    
    await _controller!.setFlashMode(nextMode);
  }

  FlashMode get currentFlashMode => _controller?.value.flashMode ?? FlashMode.off;

  void dispose() {
    _controller?.dispose();
  }
}
