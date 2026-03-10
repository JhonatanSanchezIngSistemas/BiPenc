import 'dart:io';

import 'package:bipenc/services/ml_kit_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => '.';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _MockPathProviderPlatform();

  group('MLKitService', () {
    final service = MLKitService();

    test('retorna null cuando el archivo no existe', () async {
      final out = await service.segmentarProducto('no_existe.png');
      expect(out, isNull);
    });

    test('retorna null cuando la imagen es inválida', () async {
      const badPath = 'mlkit_invalid.bin';
      await File(badPath).writeAsBytes([1, 2, 3, 4, 5]);

      final out = await service.segmentarProducto(badPath);
      expect(out, isNull);

      await File(badPath).delete();
    });

    test('vuelve transparente el fondo y mantiene el producto', () async {
      final source = img.Image(width: 40, height: 40);
      img.fill(source, color: img.ColorRgba8(255, 255, 255, 255));
      img.fillRect(
        source,
        x1: 12,
        y1: 12,
        x2: 27,
        y2: 27,
        color: img.ColorRgba8(0, 0, 255, 255),
      );

      const inputPath = 'mlkit_input.png';
      await File(inputPath).writeAsBytes(img.encodePng(source));

      final outFile = await service.segmentarProducto(inputPath);
      expect(outFile, isNotNull);
      expect(await outFile!.exists(), isTrue);

      final outImage = img.decodeImage(await outFile.readAsBytes());
      expect(outImage, isNotNull);

      final corner = outImage!.getPixel(0, 0);
      final center = outImage.getPixel(20, 20);

      expect(center.b.toInt(), greaterThan(200));
      final diff = (corner.r.toInt() - center.r.toInt()).abs() +
          (corner.g.toInt() - center.g.toInt()).abs() +
          (corner.b.toInt() - center.b.toInt()).abs();
      expect(diff, greaterThan(100));

      await File(inputPath).delete();
      await outFile.delete();
    });
  });
}
