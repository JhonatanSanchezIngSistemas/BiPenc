part of '../servicio_impresion.dart';

mixin _ImpresionImagen on ServicioImpresion {
  /// Convierte un logo a monocromo (dithering Floyd-Steinberg) para ticket térmico.
  /// Devuelve bytes PNG listos para esc_pos.
  Future<List<int>?> logoMonocromo(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final src = img.decodeImage(bytes);
      if (src == null) return null;

      // Escala a 384px (impresora 58mm) para evitar buffer overflow
      final resized = img.copyResize(src,
          width: 384, interpolation: img.Interpolation.linear);
      final gray = img.grayscale(resized);
      final dithered = _applyDitherOrThreshold(gray);
      return img.encodePng(dithered, level: 6);
    } catch (e) {
      RegistroApp.warn('Logo monocromo falló: $e', tag: 'BT');
      return null;
    }
  }

  /// Usa dithering de la librería `image` si está disponible; si no, aplica
  /// un simple umbral binario para garantizar compatibilidad hacia atrás.
  img.Image _applyDitherOrThreshold(img.Image gray) {
    try {
      return img.ditherImage(gray, kernel: img.DitherKernel.floydSteinberg);
    } catch (e, st) {
      RegistroApp.warn('Dither no disponible, aplicando umbral',
          tag: 'BT', error: e, stackTrace: st);
      // Fallback robusto: threshold manual a 128
      final clone = img.Image.from(gray);
      for (int y = 0; y < clone.height; y++) {
        for (int x = 0; x < clone.width; x++) {
          final pixel = clone.getPixel(x, y);
          final luma = img.getLuminance(pixel);
          final value = luma < 128 ? 0 : 255;
          clone.setPixelRgba(x, y, value, value, value, 255);
        }
      }
      return clone;
    }
  }

  /// Imprime una imagen (ej. foto de lista) en la térmica BT.
  Future<bool> imprimirImagenLista(String pathOrUrl) async {
    try {
      final conectado = await _ensureConnected();
      if (!conectado) return false;

      final prefs = await SharedPreferences.getInstance();
      final paperSize = (prefs.getString('thermal_paper_size') ?? '80').trim();
      final is80mm = paperSize == '80';
      final maxWidthPx = is80mm ? 576 : 384;

      // Descargar o leer archivo
      final bytes = await (pathOrUrl.startsWith('http')
          ? (() async {
              final resp = await http
                  .get(Uri.parse(pathOrUrl))
                  .timeout(const Duration(seconds: 8));
              if (resp.statusCode != 200) {
                throw Exception(
                    'HTTP ${resp.statusCode} al descargar imagen (${resp.reasonPhrase})');
              }
              return resp.bodyBytes;
            })()
          : File(pathOrUrl).readAsBytes());
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('Imagen inválida');

      final resized = img.copyResize(
        decoded,
        width: maxWidthPx,
        interpolation: img.Interpolation.average,
      );
      final gray = img.grayscale(resized);
      final mono = _applyDitherOrThreshold(gray);

      final profile = await CapabilityProfile.load();
      final generator =
          Generator(is80mm ? PaperSize.mm80 : PaperSize.mm58, profile);
      List<int> data = [];
      data += generator.imageRaster(mono, align: PosAlign.center);
      data += generator.feed(2);

      return await PrintBluetoothThermal.writeBytes(
        Uint8List.fromList(data),
      );
    } catch (e) {
      RegistroApp.error('Error imprimiendo imagen: $e', tag: 'PRINT', error: e);
      return false;
    }
  }
}
