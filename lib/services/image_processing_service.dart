import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bipenc/services/ml_kit_service.dart';

/// Motor de Recorte de Fondo — 100% Local, 100% Gratis.
/// Version mejorada con múltiples estrategias de detección.
class ImageProcessingService {
  final _mlKit = MLKitService();

  /// Paso 1: Comprime la foto WebP para optimizar memoria RAM.
  Future<XFile?> comprimirImagen(XFile file) async {
    try {
      final appDir = await getTemporaryDirectory();
      final targetPath =
          '${appDir.path}/${DateTime.now().millisecondsSinceEpoch}.webp';
      return await FlutterImageCompress.compressAndGetFile(
        file.path,
        targetPath,
        quality: 80,
        minWidth: 800,
        minHeight: 800,
        format: CompressFormat.webp,
      );
    } catch (e) {
      debugPrint('[ImgService] Error compresión: $e');
      return null;
    }
  }

  /// Paso 2: Recorte de fondo local con múltiples estrategias.
  /// Mejorado para manejar fondos no uniformes.
  Future<File?> recorteFondo(
    String inputPath, {
    int tolerance = 60,
    bool fondoBlanco = false,
    Point<int>? touchPoint,
    bool useMLKit = false,
  }) async {
    if (useMLKit) {
      final res = await _mlKit.segmentarProducto(inputPath);
      if (res != null) return res;
      debugPrint(
          '[ImgService] ML Kit no disponible, usando algoritmo manual...');
    }

    try {
      final bytes = await File(inputPath).readAsBytes();
      img.Image? original = img.decodeImage(bytes);
      if (original == null) {
        debugPrint('[ImgService] No se pudo decodificar la imagen');
        return null;
      }

      // Redimensionar si es muy grande (optimización)
      if (original.width > 800 || original.height > 800) {
        original = img.copyResize(original,
            width: 800, height: 800, interpolation: img.Interpolation.linear);
      }

      // Estrategia 1: Si hay punto tactil, usarlo como referencia de fondo
      // Estrategia 2: Detectar esquinas y bordes
      // Estrategia 3: Usar color dominante de esquinas

      // Obtener color de fondo de las 4 esquinas
      final cornerColors = _getCornerColors(original);

      // Probar con múltiples tolerancias
      final tolerancias = [
        tolerance,
        tolerance + 20,
        tolerance - 20,
        tolerance + 35
      ];
      img.Image? bestResult;
      var mejorTolerancia = tolerance;

      for (final tol in tolerancias) {
        final processed = img.Image.from(original);

        // Usar el punto táctil o detectar automáticamente
        final bgColors = <img.Color>[];

        if (touchPoint != null &&
            touchPoint.x < original.width &&
            touchPoint.y < original.height) {
          bgColors.add(original.getPixel(touchPoint.x, touchPoint.y));
        }

        // Agregar colores de esquinas
        bgColors.addAll(cornerColors);

        // Eliminar duplicados y aplicar flood fill con cada color
        final uniqueBgColors = <img.Color>[];
        for (final c in bgColors) {
          bool dup = false;
          for (final u in uniqueBgColors) {
            if (_colorSimilar(c, u, 30)) {
              dup = true;
              break;
            }
          }
          if (!dup) uniqueBgColors.add(c);
        }

        // Aplicar eliminación con cada color de fondo
        for (final bgColor in uniqueBgColors) {
          _removeBackgroundSmart(processed, bgColor, tol);
        }

        // Verificar calidad
        final calidad = _evaluarCalidadRecorte(processed);
        debugPrint(
            '[ImgService] Tolerancia $tol: calidad=${calidad.toStringAsFixed(2)}');

        if (calidad > 0.1) {
          bestResult = processed;
          mejorTolerancia = tol;
          break;
        }
      }

      // Si ninguna tolerancia funcionó bien, usar la imagen original
      final finalImg = bestResult ?? img.Image.from(original);
      debugPrint(
          '[ImgService] Mejor tolerancia seleccionada: $mejorTolerancia');

      // Suavizar bordes
      _suavizarContornos(finalImg);

      // Si se requiere fondo blanco, reemplazar transparencias
      if (fondoBlanco) {
        _fillTransparency(finalImg, img.ColorRgba8(255, 255, 255, 255));
      }

      // Guardar resultado
      final outDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outPath = '${outDir.path}/producto_$timestamp.png';
      final outFile = File(outPath);
      await outFile.writeAsBytes(img.encodePng(finalImg, level: 6));

      debugPrint('[ImgService] Imagen guardada en: $outPath');
      return outFile;
    } catch (e) {
      debugPrint('[ImgService] Error recorte: $e');
      return null;
    }
  }

  /// Alias para compatibilidad
  Future<File?> recorteFondo_(
    String inputPath, {
    int tolerance = 70,
    bool fondoBlanco = false,
    Point<int>? touchPoint,
    bool useMLKit = false,
  }) =>
      recorteFondo(inputPath,
          tolerance: tolerance,
          fondoBlanco: fondoBlanco,
          touchPoint: touchPoint,
          useMLKit: useMLKit);

  /// Alias legacy para mantener compatibilidad con tests y código viejo.
  Future<File?> recortarFondo(
    String inputPath, {
    int tolerance = 70,
    bool fondoBlanco = false,
    Point<int>? touchPoint,
    bool useMLKit = false,
  }) =>
      recorteFondo(
        inputPath,
        tolerance: tolerance,
        fondoBlanco: fondoBlanco,
        touchPoint: touchPoint,
        useMLKit: useMLKit,
      );

  /// Obtiene los colores de las 4 esquinas de la imagen
  List<img.Color> _getCornerColors(img.Image image) {
    final corners = <img.Color>[];
    final cornerSize = (image.width * 0.15).toInt().clamp(10, 50);

    // Esquina superior izquierda
    corners.add(_getAverageColor(image, 0, 0, cornerSize, cornerSize));
    // Esquina superior derecha
    corners.add(_getAverageColor(
        image, image.width - cornerSize, 0, cornerSize, cornerSize));
    // Esquina inferior izquierda
    corners.add(_getAverageColor(
        image, 0, image.height - cornerSize, cornerSize, cornerSize));
    // Esquina inferior derecha
    corners.add(_getAverageColor(image, image.width - cornerSize,
        image.height - cornerSize, cornerSize, cornerSize));
    // Centro de cada borde
    corners.add(_getAverageColor(
        image, image.width ~/ 2 - cornerSize ~/ 2, 0, cornerSize, cornerSize));
    corners.add(_getAverageColor(image, image.width ~/ 2 - cornerSize ~/ 2,
        image.height - cornerSize, cornerSize, cornerSize));

    return corners;
  }

  /// Obtiene el color promedio de una región
  img.Color _getAverageColor(img.Image image, int x, int y, int w, int h) {
    int r = 0, g = 0, b = 0, count = 0;

    for (int py = y; py < y + h && py < image.height; py++) {
      for (int px = x; px < x + w && px < image.width; px++) {
        final p = image.getPixel(px, py);
        r += p.r.toInt();
        g += p.g.toInt();
        b += p.b.toInt();
        count++;
      }
    }

    if (count == 0) return img.ColorRgba8(255, 255, 255, 255);

    return img.ColorRgba8(r ~/ count, g ~/ count, b ~/ count, 255);
  }

  /// Eliminación de fondo inteligente con flood fill desde múltiples puntos
  void _removeBackgroundSmart(
      img.Image image, img.Color targetColor, int tolerance) {
    // Puntos de inicio en los bordes
    final starts = <Point<int>>[];

    // Esquinas
    starts.add(const Point(0, 0));
    starts.add(Point(image.width - 1, 0));
    starts.add(const Point(0, 1));
    starts.add(Point(image.width - 1, 1));

    // Puntos intermedios en bordes
    for (int i = 0; i < image.width; i += 20) {
      starts.add(Point(i, 0));
      starts.add(Point(i, image.height - 1));
    }
    for (int i = 0; i < image.height; i += 20) {
      starts.add(Point(0, i));
      starts.add(Point(image.width - 1, i));
    }

    // Aplicar flood fill desde cada punto no visitado
    final visited = <String>{};
    final transparent = img.ColorRgba8(0, 0, 0, 0);

    for (final start in starts) {
      final key = '${start.x},${start.y}';
      if (visited.contains(key)) continue;

      final px = image.getPixel(start.x, start.y);
      if (px.a == 0) {
        visited.add(key);
        continue;
      }

      if (_colorWithinTolerance(px, targetColor, tolerance)) {
        _floodFillSmart(image, start.x, start.y, targetColor, transparent,
            tolerance, visited);
      }
    }
  }

  /// Flood fill con límites de profundidad para evitarstack overflow
  void _floodFillSmart(
      img.Image image,
      int startX,
      int startY,
      img.Color targetColor,
      img.Color fillColor,
      int tolerance,
      Set<String> visited,
      {int maxDepth = 10000}) {
    final queue = <Point<int>>[Point(startX, startY)];
    int processed = 0;

    while (queue.isNotEmpty && processed < maxDepth) {
      final p = queue.removeAt(0);
      if (p.x < 0 || p.y < 0 || p.x >= image.width || p.y >= image.height) {
        continue;
      }

      final key = '${p.x},${p.y}';
      if (visited.contains(key)) continue;

      final px = image.getPixel(p.x, p.y);
      if (px.a == 0) {
        visited.add(key);
        continue;
      }

      if (!_colorWithinTolerance(px, targetColor, tolerance)) continue;

      visited.add(key);
      image.setPixel(p.x, p.y, fillColor);
      processed++;

      queue.add(Point(p.x + 1, p.y));
      queue.add(Point(p.x - 1, p.y));
      queue.add(Point(p.x, p.y + 1));
      queue.add(Point(p.x, p.y - 1));
    }
  }

  /// Evalúa la calidad del recorte (retorna valor entre 0 y 1)
  double _evaluarCalidadRecorte(img.Image image) {
    int transparentes = 0;
    int opacos = 0;
    final total = image.width * image.height;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);

        // Contar píxeles transparentes
        if (p.a < 50) {
          transparentes++;
        } else if (p.a > 200) {
          opacos++;
        }
      }
    }

    // Calcular porcentajes
    final pctTrans = transparentes / total;
    final pctOpaco = opacos / total;

    // Un buen recorte tiene:
    // - Algo de transparente (al menos 10%)
    // - Algo de opaco (al menos 20%)
    // - Bordes suaves (al menos 1%)
    if (pctTrans > 0.1 && pctOpaco > 0.2) {
      return pctTrans * pctOpaco;
    }

    return 0.0;
  }

  void _fillTransparency(img.Image image, img.Color color) {
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        if (p.a == 0) {
          image.setPixel(x, y, color);
        }
      }
    }
  }

  /// Suaviza los bordes para mejorar la estética visual
  void _suavizarContornos(img.Image image) {
    final copy = img.Image.from(image);
    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        final p = copy.getPixel(x, y);
        if (p.a > 0 && p.a < 255) {
          num avgA = 0;
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              avgA += copy.getPixel(x + dx, y + dy).a;
            }
          }
          image.setPixel(
              x,
              y,
              img.ColorRgba8(
                  p.r.toInt(), p.g.toInt(), p.b.toInt(), (avgA / 9).toInt()));
        }
      }
    }
  }

  bool _colorWithinTolerance(img.Color a, img.Color b, int tol) {
    return (a.r.toInt() - b.r.toInt()).abs() <= tol &&
        (a.g.toInt() - b.g.toInt()).abs() <= tol &&
        (a.b.toInt() - b.b.toInt()).abs() <= tol;
  }

  bool _colorSimilar(img.Color a, img.Color b, int tol) {
    return _colorWithinTolerance(a, b, tol);
  }
}
