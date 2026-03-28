import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bipenc/servicios/servicio_mlkit.dart';

/// Motor de procesamiento de imágenes — 100% Local, 100% Gratuito.
/// Pipeline de calidad tipo CamScanner / Adobe Scan para documentos y listas.
class ServicioProcesamientoImagen {
  final _mlKit = ServicioMlkit();

  // ─────────────────────────────────────────────────────────────────────────
  // PASO 0: Comprimir foto a WebP para optimizar memoria RAM
  // ─────────────────────────────────────────────────────────────────────────

  /// Comprime la foto WebP para optimizar memoria RAM.
  Future<XFile?> comprimirImagen(XFile file) async {
    try {
      final appDir = await getTemporaryDirectory();
      final targetPath =
          '${appDir.path}/${DateTime.now().millisecondsSinceEpoch}.webp';
      return await FlutterImageCompress.compressAndGetFile(
        file.path,
        targetPath,
        quality: 85, // subido de 70 → 85 para preservar detalles del texto
        minWidth: 1200,
        minHeight: 1200,
        format: CompressFormat.webp,
      );
    } catch (e) {
      debugPrint('[ImgService] Error compresión: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PIPELINE COMPLETO DE DOCUMENTO (tipo CamScanner)
  // ─────────────────────────────────────────────────────────────────────────

  /// Pipeline ligero para fotos tomadas con cámara estándar (fallback).
  /// Diseñado para funcionar bien tanto con documentos escritos como con
  /// objetos con color (lápices, borradores, cuadernos, etc.).
  ///
  /// Aplica en orden:
  ///   1. Glare removal  → reduce destellos/reflejos de luz/flash
  ///   2. Contraste suave → mejora legibilidad sin destruir colores
  ///   3. Sharpening ligero → texto y bordes más nítidos
  ///
  /// NO convierte a blanco/negro (no grayscale, no binarización).
  /// Mantiene los colores originales de la foto.
  Future<File?> procesarDocumentoCompleto(File input) async {
    try {
      debugPrint('[ImgService] Iniciando pipeline ligero (color kept)...');
      final bytes = await input.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      // Limitar tamaño máximo para no agotar RAM
      if (image.width > 1600 || image.height > 1600) {
        image = img.copyResize(
          image,
          width: image.width > image.height ? 1600 : -1,
          height: image.height >= image.width ? 1600 : -1,
          interpolation: img.Interpolation.cubic,
        );
        debugPrint(
            '[ImgService] Redimensionado a ${image.width}x${image.height}');
      }

      // █ Paso 1: Eliminar destellos / glare (preserva color)
      image = _aplicarGlareRemoval(image, threshold: 235, radius: 3);
      debugPrint('[ImgService] ✓ Glare removal');

      // █ Paso 2: Contraste y brillo ligeros — no agresivos
      // Solo realza levemente para mejorar legibilidad.
      image = img.adjustColor(image, contrast: 1.2, brightness: 6);
      debugPrint('[ImgService] ✓ Contraste suave');

      // █ Paso 3: Sharpening ligero para texto y bordes más nítidos
      image = _aplicarSharpening(image, amount: 0.3);
      debugPrint('[ImgService] ✓ Sharpening');

      final outPath =
          '${(await getTemporaryDirectory()).path}/doc_${DateTime.now().millisecondsSinceEpoch}.png';
      final outFile = File(outPath);
      await outFile.writeAsBytes(img.encodePng(image, level: 3));
      debugPrint('[ImgService] ✓ Pipeline ligero → $outPath');
      return outFile;
    } catch (e, st) {
      debugPrint('[ImgService] Error pipeline ligero: $e\n$st');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PASO 1 INTERNO: Eliminación de destellos / Glare Removal
  // ─────────────────────────────────────────────────────────────────────────

  /// Detecta píxeles sobreexpuestos (R,G,B > umbral simultáneamente)
  /// y los rellena con el promedio de sus vecinos válidos.
  /// Reduce los "quemados blancos" por flash o luz artificial directa.
  Future<File?> eliminarDestellos(File input,
      {int threshold = 230, int radius = 3}) async {
    try {
      final bytes = await input.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      final result = _aplicarGlareRemoval(image,
          threshold: threshold, radius: radius);

      final outPath =
          '${(await getTemporaryDirectory()).path}/glare_${DateTime.now().millisecondsSinceEpoch}.png';
      final outFile = File(outPath);
      await outFile.writeAsBytes(img.encodePng(result, level: 3));
      return outFile;
    } catch (e) {
      debugPrint('[ImgService] Error glare removal: $e');
      return null;
    }
  }

  img.Image _aplicarGlareRemoval(img.Image src,
      {int threshold = 230, int radius = 2}) {
    final result = img.Image.from(src);
    final w = src.width;
    final h = src.height;

    // Detectar máscara de píxeles sobreexpuestos
    final isGlare = List.generate(h, (_) => List.filled(w, false));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        if (p.r >= threshold && p.g >= threshold && p.b >= threshold) {
          isGlare[y][x] = true;
        }
      }
    }

    // Rellenar píxeles de destello con promedio de vecinos no-destello
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (!isGlare[y][x]) continue;

        int rSum = 0, gSum = 0, bSum = 0, count = 0;
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            if (isGlare[ny][nx]) continue;
            final np = src.getPixel(nx, ny);
            rSum += np.r.toInt();
            gSum += np.g.toInt();
            bSum += np.b.toInt();
            count++;
          }
        }

        if (count > 0) {
          result.setPixel(
            x,
            y,
            img.ColorRgba8(
              rSum ~/ count,
              gSum ~/ count,
              bSum ~/ count,
              255,
            ),
          );
        }
        // Si todos los vecinos también son destello, dejar como está
      }
    }

    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PASO 4 INTERNO: Binarización Adaptativa (Sauvola simplificado)
  // ─────────────────────────────────────────────────────────────────────────

  /// Binarización adaptativa local: el umbral varía por región de la imagen.
  /// Mucho mejor que un umbral global para documentos con iluminación irregular.
  ///
  /// [blockSize]: tamaño del bloque local (impar, ej: 31)
  /// [c]: constante restada al umbral local (ej: 10–15)
  Future<File?> binarizarAdaptativo(File input,
      {int blockSize = 31, int c = 12}) async {
    try {
      final bytes = await input.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      // Asegurar escala de grises
      image = img.grayscale(image);
      final result = _binarizarAdaptativo(image, blockSize: blockSize, c: c);

      final outPath =
          '${(await getTemporaryDirectory()).path}/bin_${DateTime.now().millisecondsSinceEpoch}.png';
      final outFile = File(outPath);
      await outFile.writeAsBytes(img.encodePng(result, level: 3));
      return outFile;
    } catch (e) {
      debugPrint('[ImgService] Error binarización adaptativa: $e');
      return null;
    }
  }

  img.Image _binarizarAdaptativo(img.Image gray,
      {int blockSize = 31, int c = 12}) {
    // Calcular tabla de suma integral para promedios locales rápidos
    final w = gray.width;
    final h = gray.height;

    // integral[y][x] = suma de todos los píxeles en rect (0,0)→(x-1,y-1)
    final integral = List.generate(h + 1, (_) => List.filled(w + 1, 0.0));

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final lum = gray.getPixel(x, y).r.toDouble(); // gris = R=G=B
        integral[y + 1][x + 1] = lum +
            integral[y][x + 1] +
            integral[y + 1][x] -
            integral[y][x];
      }
    }

    final result = img.Image(width: w, height: h);
    final half = blockSize ~/ 2;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final x1 = max(0, x - half);
        final y1 = max(0, y - half);
        final x2 = min(w - 1, x + half);
        final y2 = min(h - 1, y + half);

        final area = (x2 - x1 + 1) * (y2 - y1 + 1);
        // Suma usando integral: S(tl,br) = I[br] - I[tr-1] - I[bl-1] + I[tl-1]
        final sum = integral[y2 + 1][x2 + 1] -
            integral[y1][x2 + 1] -
            integral[y2 + 1][x1] +
            integral[y1][x1];

        final mean = sum / area;
        final threshold = mean - c;

        final pixel = gray.getPixel(x, y).r.toDouble();
        final out = pixel < threshold ? 0 : 255;
        result.setPixel(x, y, img.ColorRgba8(out, out, out, 255));
      }
    }

    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PASO 5 INTERNO: Sharpening
  // ─────────────────────────────────────────────────────────────────────────

  img.Image _aplicarSharpening(img.Image src, {double amount = 0.4}) {
    // Unsharp mask: sharpened = original + amount * (original - blurred)
    try {
      final blurred = img.gaussianBlur(src, radius: 1);
      final result = img.Image.from(src);
      final w = src.width;
      final h = src.height;

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final o = src.getPixel(x, y);
          final b = blurred.getPixel(x, y);

          int sharpen(int orig, int blur) {
            final val = orig + (amount * (orig - blur)).round();
            return val.clamp(0, 255);
          }

          result.setPixel(
            x,
            y,
            img.ColorRgba8(
              sharpen(o.r.toInt(), b.r.toInt()),
              sharpen(o.g.toInt(), b.g.toInt()),
              sharpen(o.b.toInt(), b.b.toInt()),
              255,
            ),
          );
        }
      }
      return result;
    } catch (_) {
      return src;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MEJORA DE CONTRASTE SUAVE (para imágenes desde escáner nativo)
  // ─────────────────────────────────────────────────────────────────────────

  /// Mejora contraste y brillo suave para facilitar lectura al imprimir/compartir.
  /// Usar cuando la imagen ya viene del escáner nativo (ya recortada y corregida).
  Future<File?> mejorarContraste(
    File input, {
    double contraste = 1.25,
    double brillo = 6,
  }) async {
    try {
      final bytes = await input.readAsBytes();
      final img.Image? original = img.decodeImage(bytes);
      if (original == null) return null;

      final adjusted = img.adjustColor(
        original,
        contrast: contraste,
        brightness: brillo,
      );
      final outPath =
          '${(await getTemporaryDirectory()).path}/contrast_${DateTime.now().millisecondsSinceEpoch}.png';
      final outFile = File(outPath);
      await outFile.writeAsBytes(img.encodePng(adjusted, level: 3));
      return outFile;
    } catch (e) {
      debugPrint('[ImgService] Error mejorarContraste: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LEGACY: Recorte de fondo (para productos, no documentos)
  // ─────────────────────────────────────────────────────────────────────────

  /// Recorte de fondo local con múltiples estrategias.
  /// Útil principalmente para fotos de productos, NO para documentos.
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

      if (original.width > 800 || original.height > 800) {
        original = img.copyResize(original,
            width: 800, height: 800, interpolation: img.Interpolation.linear);
      }

      // Asegurar canal alpha para poder volver transparente el fondo
      original = _asegurarRgba(original);

      final cornerColors = _getCornerColors(original);

      final tolerancias = <int>{
        tolerance,
        tolerance + 20,
        (tolerance - 20).clamp(20, 255),
        tolerance + 35,
        35,
      }.toList()
        ..sort();
      img.Image? bestResult;
      var mejorTolerancia = tolerance;
      var mejorCalidad = 0.0;

      for (final tol in tolerancias) {
        final processed = img.Image.from(original);
        final bgColors = <img.Color>[];

        if (touchPoint != null &&
            touchPoint.x < original.width &&
            touchPoint.y < original.height) {
          bgColors.add(original.getPixel(touchPoint.x, touchPoint.y));
        }

        bgColors.addAll(cornerColors);

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

        for (final bgColor in uniqueBgColors) {
          _removeBackgroundSmart(processed, bgColor, tol);
        }

        final calidad = _evaluarCalidadRecorte(processed);
        debugPrint(
            '[ImgService] Tolerancia $tol: calidad=${calidad.toStringAsFixed(2)}');

        if (calidad > mejorCalidad) {
          bestResult = processed;
          mejorTolerancia = tol;
          mejorCalidad = calidad;
        }
      }

      final finalImg =
          (bestResult != null && mejorCalidad > 0) ? bestResult : img.Image.from(original);
      debugPrint(
          '[ImgService] Mejor tolerancia seleccionada: $mejorTolerancia');

      _suavizarContornos(finalImg);

      if (fondoBlanco) {
        _fillTransparency(finalImg, img.ColorRgba8(255, 255, 255, 255));
      }

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

  /// Recorta automáticamente al bounding box del contenido (no blanco).
  Future<File?> autoCropContenido(String inputPath) async {
    try {
      final bytes = await File(inputPath).readAsBytes();
      final img.Image? original = img.decodeImage(bytes);
      if (original == null) return null;

      int minX = original.width, minY = original.height, maxX = 0, maxY = 0;
      final bg = img.ColorRgba8(255, 255, 255, 255);
      for (int y = 0; y < original.height; y++) {
        for (int x = 0; x < original.width; x++) {
          final c = original.getPixel(x, y);
          if (!_colorSimilar(c, bg, 6)) {
            if (x < minX) minX = x;
            if (y < minY) minY = y;
            if (x > maxX) maxX = x;
            if (y > maxY) maxY = y;
          }
        }
      }
      if (minX >= maxX || minY >= maxY) return File(inputPath);
      final cropped = img.copyCrop(original,
          x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
      final outPath =
          '${(await getTemporaryDirectory()).path}/crop_${DateTime.now().millisecondsSinceEpoch}.png';
      final outFile = File(outPath);
      await outFile.writeAsBytes(img.encodePng(cropped, level: 6));
      return outFile;
    } catch (e) {
      debugPrint('[ImgService] Error auto-crop: $e');
      return null;
    }
  }

  /// Limpia un documento: escala de grises + contraste fuerte + ligero blur.
  Future<File?> limpiarDocumento(File input) async {
    try {
      final bytes = await input.readAsBytes();
      final img.Image? original = img.decodeImage(bytes);
      if (original == null) return null;

      var gray = img.grayscale(original);
      gray = img.gaussianBlur(gray, radius: 1);
      final cleaned = img.adjustColor(
        gray,
        contrast: 2.2,
        brightness: 15,
      );

      final outPath =
          '${(await getTemporaryDirectory()).path}/docclean_${DateTime.now().millisecondsSinceEpoch}.png';
      final outFile = File(outPath);
      await outFile.writeAsBytes(img.encodePng(cleaned, level: 6));
      return outFile;
    } catch (e) {
      debugPrint('[ImgService] Error limpiarDocumento: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS INTERNOS
  // ─────────────────────────────────────────────────────────────────────────

  List<img.Color> _getCornerColors(img.Image image) {
    final corners = <img.Color>[];
    final cornerSize = (image.width * 0.15).toInt().clamp(10, 50);

    corners.add(_getAverageColor(image, 0, 0, cornerSize, cornerSize));
    corners.add(_getAverageColor(
        image, image.width - cornerSize, 0, cornerSize, cornerSize));
    corners.add(_getAverageColor(
        image, 0, image.height - cornerSize, cornerSize, cornerSize));
    corners.add(_getAverageColor(image, image.width - cornerSize,
        image.height - cornerSize, cornerSize, cornerSize));
    corners.add(_getAverageColor(
        image, image.width ~/ 2 - cornerSize ~/ 2, 0, cornerSize, cornerSize));
    corners.add(_getAverageColor(image, image.width ~/ 2 - cornerSize ~/ 2,
        image.height - cornerSize, cornerSize, cornerSize));

    return corners;
  }

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

  void _removeBackgroundSmart(
      img.Image image, img.Color targetColor, int tolerance) {
    final starts = <Point<int>>[];

    starts.add(const Point(0, 0));
    starts.add(Point(image.width - 1, 0));
    starts.add(const Point(0, 1));
    starts.add(Point(image.width - 1, 1));

    for (int i = 0; i < image.width; i += 20) {
      starts.add(Point(i, 0));
      starts.add(Point(i, image.height - 1));
    }
    for (int i = 0; i < image.height; i += 20) {
      starts.add(Point(0, i));
      starts.add(Point(image.width - 1, i));
    }

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

  double _evaluarCalidadRecorte(img.Image image) {
    int transparentes = 0;
    int opacos = 0;
    final total = image.width * image.height;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        if (p.a < 50) {
          transparentes++;
        } else if (p.a > 200) {
          opacos++;
        }
      }
    }

    final pctTrans = transparentes / total;
    final pctOpaco = opacos / total;

    if (pctTrans > 0.02 && pctOpaco > 0.02) {
      return pctTrans * (0.5 + pctOpaco);
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

  img.Image _asegurarRgba(img.Image image) {
    if (image.hasAlpha) return image;
    final out = img.Image(width: image.width, height: image.height, numChannels: 4);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        out.setPixel(
          x,
          y,
          img.ColorRgba8(p.r.toInt(), p.g.toInt(), p.b.toInt(), 255),
        );
      }
    }
    return out;
  }
}
