import 'dart:io';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class ImageProcessingService {
  late SelfieSegmenter _segmenter;

  ImageProcessingService() {
    // Configuramos en modo estático (streamMode: false) pues tomaremos fotos fijas,
    // y pedimos la máscara cruda para recorte de alta precisión.
    final options = SelfieSegmenterOptions(
      streamMode: false,
      enableRawSizeMask: true,
    );
    _segmenter = SelfieSegmenter(options: options);
  }

  /// Recibe la imagen capturada por la cámara y genera la máscara de segmentación
  /// que distingue el producto en primer plano del fondo a remover/blanquear.
  Future<SegmentationMask?> processImageBackground(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      
      // La IA analiza la imagen y retorna la máscara de probabilidades
      final mask = await _segmenter.processImage(inputImage);
      
      // La máscara devuelta tiene las mismas dimensiones que la imagen original,
      // donde cada valor float (confidence) representa la probabilidad 
      // de que el pixel corresponda al objeto en primer plano (el producto).
      return mask;
    } catch (e) {
      debugPrint('Error en IA de Segmentación Visual: $e');
      return null;
    }
  }

  /// Escudo de Compresión Visual: Comprime la foto original pesada
  /// a un archivo WebP optimizado de 800x800 a 80% de calidad.
  /// Esto ahorra masivamente la banda ancha al subir a Supabase.
  Future<XFile?> comprimirImagen(XFile file) async {
    try {
      final appDir = await getTemporaryDirectory();
      // Renombramos la extensión a .webp
      final targetPath = '${appDir.path}/${DateTime.now().millisecondsSinceEpoch}.webp';

      final result = await FlutterImageCompress.compressAndGetFile(
        file.path,
        targetPath,
        quality: 80,
        minWidth: 800,
        minHeight: 800,
        format: CompressFormat.webp,
      );
      
      return result;
    } catch (e) {
      debugPrint('Error en la compresión de imagen: $e');
      return null;
    }
  }

  /// Limpieza de recursos nativos del modelo ML Kit.
  void close() {
    _segmenter.close();
  }
}
