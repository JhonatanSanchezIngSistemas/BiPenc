import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:bipenc/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncService', () {
    late SyncService service;

    setUp(() {
      service = SyncService();
      service.stop();
      service.resetTestingOverrides();
      service.retryBackoffOverride = (_) => Duration.zero;
    });

    test('skip when no connectivity', () async {
      service.connectivityCheckOverride = () async => [ConnectivityResult.none];

      final result = await service.syncNow();
      expect(result.skipped, isTrue);
      expect(result.reason, 'Sin conexión');
    });

    test('skip when only mobile data', () async {
      service.connectivityCheckOverride = () async => [ConnectivityResult.mobile];

      final result = await service.syncNow();
      expect(result.skipped, isTrue);
      expect(result.reason, 'Solo sincroniza por WiFi');
    });

    test('successful cycle runs all operations', () async {
      var ventasRuns = 0;
      var queueRuns = 0;
      var productosRuns = 0;
      var printRuns = 0;
      var cleanupRuns = 0;

      service.connectivityCheckOverride = () async => [ConnectivityResult.wifi];
      service.subirVentasPendientesOverride = () async => ventasRuns++;
      service.procesarSyncQueueV2Override = () async => queueRuns++;
      service.sincronizarProductosOverride = () async {
        productosRuns++;
        return true;
      };
      service.procesarPrintQueueOverride = () async => printRuns++;
      service.limpiarSyncQueueV2Override = () async => cleanupRuns++;

      final result = await service.syncNow();

      expect(result.skipped, isFalse);
      expect(result.errores, 0);
      expect(result.ventasSubidas, isTrue);
      expect(result.syncQueueProcesada, isTrue);
      expect(result.productosSincronizados, isTrue);
      expect(ventasRuns, 1);
      expect(queueRuns, 1);
      expect(productosRuns, 1);
      expect(printRuns, 1);
      expect(cleanupRuns, 1);
    });

    test('retry eventually succeeds', () async {
      var attempts = 0;
      service.connectivityCheckOverride = () async => [ConnectivityResult.wifi];
      service.subirVentasPendientesOverride = () async {
        attempts++;
        if (attempts < 3) {
          throw Exception('transient');
        }
      };
      service.procesarSyncQueueV2Override = () async {};
      service.sincronizarProductosOverride = () async => true;
      service.procesarPrintQueueOverride = () async {};
      service.limpiarSyncQueueV2Override = () async {};

      final result = await service.syncNow();
      expect(result.errores, 0);
      expect(result.ventasSubidas, isTrue);
      expect(attempts, 3);
    });

    test('failed operation increments error count', () async {
      service.connectivityCheckOverride = () async => [ConnectivityResult.wifi];
      service.subirVentasPendientesOverride = () async {};
      service.procesarSyncQueueV2Override = () async => throw Exception('hard fail');
      service.sincronizarProductosOverride = () async => true;
      service.procesarPrintQueueOverride = () async {};
      service.limpiarSyncQueueV2Override = () async {};

      final result = await service.syncNow();
      expect(result.errores, greaterThanOrEqualTo(1));
      expect(result.syncQueueProcesada, isFalse);
    });
  });
}
