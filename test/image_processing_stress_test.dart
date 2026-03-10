import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:bipenc/services/image_processing_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Mock de PathProvider para el entorno de test
class MockPathProviderPlatform extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => '.';
  @override
  Future<String?> getApplicationDocumentsPath() async => '.';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = MockPathProviderPlatform();

  final service = ImageProcessingService();

  group('Pruebas Exhaustivas de IA Visual (Recorte de Fondo)', () {
    
    test('Debe detectar fondo dominante y eliminarlo (Escenario de contraste alto)', () async {
      // 1. Crear imagen sintética: Fondo Rojo con Círculo Azul en el centro
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgba8(255, 0, 0, 255)); // Fondo Rojo
      img.fillCircle(image, x: 50, y: 50, radius: 20, color: img.ColorRgba8(0, 0, 255, 255)); // Objeto Azul

      const inputPath = 'test_input.png';
      await File(inputPath).writeAsBytes(img.encodePng(image));

      // 2. Ejecutar recorte (Fondo Blanco)
      final resultFile = await service.recortarFondo(inputPath, tolerance: 10, fondoBlanco: true);
      
      expect(resultFile, isNotNull);
      final resultBytes = await resultFile!.readAsBytes();
      final resultImg = img.decodeImage(resultBytes)!;

      // 3. Verificar centro (Debe seguir siendo Azul)
      final center = resultImg.getPixel(50, 50);
      expect(center.r, lessThanOrEqualTo(5));
      expect(center.g, lessThanOrEqualTo(5));
      expect(center.b, greaterThanOrEqualTo(250));

      // Limpieza
      await File(inputPath).delete();
      await resultFile.delete();
    });

    test('Debe manejar ruido en el fondo (Tolerancia)', () async {
      // Crear fondo con "ruido" (variaciones leves de rojo)
      final image = img.Image(width: 100, height: 100);
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 100; x++) {
          final noise = (x + y) % 10; // Variación de 0 a 10
          image.setPixel(x, y, img.ColorRgba8(240 + noise, 0, 0, 255));
        }
      }
      // Objeto central
      img.fillCircle(image, x: 50, y: 50, radius: 20, color: img.ColorRgba8(0, 255, 0, 255));

      const inputPath = 'test_noise.png';
      await File(inputPath).writeAsBytes(img.encodePng(image));

      // Con tolerancia baja (5), el ruido NO debería eliminarse por completo
      final resultLow = await service.recortarFondo(inputPath, tolerance: 5, fondoBlanco: false); // Fondo Negro
      
      // Con tolerancia alta (20), el ruido DEBERÍA eliminarse
      final resultHigh = await service.recortarFondo(inputPath, tolerance: 20, fondoBlanco: false);

      expect(resultHigh, isNotNull);
      final highImg = img.decodeImage(await resultHigh!.readAsBytes())!;
      
      // El borde ruidoso debe oscurecerse fuertemente con tolerancia alta.
      final edge = highImg.getPixel(2, 2);
      expect(edge.r, lessThanOrEqualTo(245));
      expect(edge.a, 255);

      // Limpieza
      await File(inputPath).delete();
      await resultLow?.delete();
      await resultHigh.delete();
    });
  });
}
