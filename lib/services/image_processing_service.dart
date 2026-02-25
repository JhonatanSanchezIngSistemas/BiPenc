import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:camera/camera.dart';

/// Motor de Recorte de Fondo — 100% Local, 100% Gratis.
class ImageProcessingService {

  /// Paso 1: Comprime la foto WebP para optimizar memoria RAM.
  Future<XFile?> comprimirImagen(XFile file) async {
    try {
      final appDir = await getTemporaryDirectory();
      final targetPath = '${appDir.path}/${DateTime.now().millisecondsSinceEpoch}.webp';
      return await FlutterImageCompress.compressAndGetFile(
        file.path, targetPath,
        quality: 85,
        minWidth: 800,
        minHeight: 800,
        format: CompressFormat.webp,
      );
    } catch (e) {
      debugPrint('[ImgService] Error compresión: $e');
      return null;
    }
  }

  /// Paso 2: Recorte de fondo local.
  /// Implementa FloodFill BFS de alta precisión + Umbralización (Thresholding) veloz.
  Future<File?> recortarFondo(String inputPath, {int tolerance = 65}) async {
    try {
      final bytes = await File(inputPath).readAsBytes();
      final original = img.decodeImage(bytes);
      if (original == null) return null;

      // Trabajamos en copia optimizada
      final processed = img.Image.from(original);

      // 1. Muestrear color de fondo
      final bgColor = _promediarEsquinas(original);

      // 2. Ejecutar procesamiento basado en tamaño
      // Si la imagen es muy grande (> 1000px), usamos Thresholding (O(n)) 
      // Si es manejable, usamos FloodFill (O(n) pero con más saltos de memoria)
      if (processed.width * processed.height > 1000 * 1000) {
        _applyThresholding(processed, bgColor, tolerance);
      } else {
        final transparent = img.ColorRgba8(0, 0, 0, 0);
        _floodFill(processed, 0, 0, bgColor, transparent, tolerance);
        _floodFill(processed, processed.width - 1, processed.height - 1, bgColor, transparent, tolerance);
      }

      // 3. Guardar resultado 
      final outDir = await getApplicationDocumentsDirectory();
      final outPath = '${outDir.path}/recorte_${DateTime.now().millisecondsSinceEpoch}.png';
      final outFile = File(outPath);
      await outFile.writeAsBytes(img.encodePng(processed));
      return outFile;
    } catch (e) {
      debugPrint('[ImgService] Error recorte: $e');
      return null;
    }
  }

  /// Umbralización global (O(n)): Extremadamente rápida para el A36.
  void _applyThresholding(img.Image image, img.Color targetRed, int tol) {
    final transparent = img.ColorRgba8(0, 0, 0, 0);
    for (final pixel in image) {
      if ((pixel.r - targetRed.r).abs() <= tol &&
          (pixel.g - targetRed.g).abs() <= tol &&
          (pixel.b - targetRed.b).abs() <= tol) {
        pixel.r = transparent.r;
        pixel.g = transparent.g;
        pixel.b = transparent.b;
        pixel.a = transparent.a;
      }
    }
  }

  /// Muestreo de esquinas para detectar el fondo.
  img.Color _promediarEsquinas(img.Image image) {
    int r = 0, g = 0, b = 0, n = 0;
    final corners = [
      [0, 0], [image.width - 6, 0],
      [0, image.height - 6], [image.width - 6, image.height - 6],
    ];
    for (final corner in corners) {
      for (int dx = 0; dx < 5; dx++) {
        for (int dy = 0; dy < 5; dy++) {
          final px = image.getPixel(corner[0] + dx, corner[1] + dy);
          r += px.r.toInt();
          g += px.g.toInt();
          b += px.b.toInt();
          n++;
        }
      }
    }
    return img.ColorRgba8(r ~/ n, g ~/ n, b ~/ n, 255);
  }

  /// FloodFill iterativo (BFS).
  void _floodFill(img.Image image, int startX, int startY,
      img.Color targetColor, img.Color fillColor, int tolerance) {
    final queue = <Point<int>>[Point(startX, startY)];
    final visited = <String>{};

    while (queue.isNotEmpty) {
      final p = queue.removeAt(0);
      final key = '${p.x},${p.y}';
      if (visited.contains(key)) continue;
      if (p.x < 0 || p.y < 0 || p.x >= image.width || p.y >= image.height) continue;

      final px = image.getPixel(p.x, p.y);
      if (!_colorDentroTolerancia(px, targetColor, tolerance)) continue;

      visited.add(key);
      image.setPixel(p.x, p.y, fillColor);

      queue.add(Point(p.x + 1, p.y));
      queue.add(Point(p.x - 1, p.y));
      queue.add(Point(p.x, p.y + 1));
      queue.add(Point(p.x, p.y - 1));
    }
  }

  bool _colorDentroTolerancia(img.Color a, img.Color b, int tol) {
    return (a.r - b.r).abs() <= tol &&
        (a.g - b.g).abs() <= tol &&
        (a.b - b.b).abs() <= tol;
  }
}
