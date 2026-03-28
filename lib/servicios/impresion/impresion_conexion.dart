part of '../servicio_impresion.dart';

mixin _ConexionImpresion on ServicioImpresion {
  // ── INIT ─────────────────────────────────────────────────────────────────
  void _initAutoConnect() {
    if (!_isPrintSupported()) return;
    intentarReconectar();
    _startWatchdog();
  }

  void _startWatchdog() {
    if (!_isPrintSupported()) return;
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      final stillConnected = await PrintBluetoothThermal.connectionStatus;
      if (!stillConnected && _estaConectado) {
        _estaConectado = false;
        _connectionController.add(false);
        RegistroApp.warn('Watchdog: BT desconectado. Reconectando...', tag: 'BT');
        await intentarReconectar();
      }
    });
  }

  // ── RECONEXIÓN ───────────────────────────────────────────────────────────
  Future<bool> _ensureBluetoothPermissions() async {
    if (!Platform.isAndroid) return true;

    final scanStatus = await Permission.bluetoothScan.status;
    final connectStatus = await Permission.bluetoothConnect.status;

    if (scanStatus.isGranted && connectStatus.isGranted) return true;

    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    final granted = statuses[Permission.bluetoothScan]?.isGranted == true &&
        statuses[Permission.bluetoothConnect]?.isGranted == true;

    if (!granted) {
      RegistroApp.warn('Permisos Bluetooth denegados', tag: 'BT');
      try {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('⚠️ Permisos Bluetooth necesarios para imprimir.'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 6),
          ),
        );
      } catch (e, st) {
        RegistroApp.warn('No se pudo mostrar aviso de permisos BT',
            tag: 'BT', error: e, stackTrace: st);
      }
    }
    return granted;
  }

  Future<void> intentarReconectar() async {
    if (!_isPrintSupported()) return;
    if (_ongoingReconnect != null) {
      await _ongoingReconnect;
      return;
    }
    _ongoingReconnect = _doReconnect();
    try {
      await _ongoingReconnect;
    } finally {
      _ongoingReconnect = null;
    }
  }

  Future<void> _doReconnect() async {
    if (!_isPrintSupported()) return;
    final hasPermissions = await _ensureBluetoothPermissions();
    if (!hasPermissions) {
      _actualizarConectado(false);
      return;
    }

    final connected = await PrintBluetoothThermal.connectionStatus;
    if (connected) {
      _actualizarConectado(true);
      return;
    }
    await _intentarConBackoff();
  }

  Future<bool> _intentarConBackoff({
    int maxIntentos = 3,
    int delayInicialMs = 500,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final savedMac = prefs.getString('printer_mac') ??
        prefs.getString('printerMac') ??
        prefs.getString('bluetooth_mac');
    final macToConnect = (savedMac != null && savedMac.isNotEmpty)
        ? savedMac
        : whitelistedMacFallback;

    final paired = await PrintBluetoothThermal.pairedBluetooths;
    final printer = paired.firstWhere(
      (d) => d.macAdress == macToConnect,
      orElse: () {
        final guessed = paired.where((d) {
          final name = d.name.toLowerCase();
          return name.contains('pt-') ||
              name.contains('pt210') ||
              name.contains('thermal') ||
              name.contains('printer');
        }).toList();
        if (guessed.isNotEmpty) return guessed.first;
        return BluetoothInfo(name: 'NONE', macAdress: '');
      },
    );

    if (printer.macAdress.isEmpty) {
      _actualizarConectado(false);
      if (savedMac != null) _notificarNecesidadEmparejamiento();
      return false;
    }

    for (int i = 0; i < maxIntentos; i++) {
      try {
        final res = await PrintBluetoothThermal.connect(
          macPrinterAddress: printer.macAdress,
        );

        if (res) {
          _actualizarConectado(true);
          RegistroApp.info('BT reconectado en intento ${i + 1}', tag: 'BT');
          _reconnectTimer?.cancel();
          _reconnectTimer = null;
          _failedReconnectCount = 0;
          ColaImpresion.procesarCola().catchError(
            (e) => RegistroApp.error('Error procesando cola BT',
                tag: 'BT', error: e),
          );
          return true;
        }
      } catch (e) {
        RegistroApp.warn('Intento BT $i falló: $e', tag: 'BT');
      }

      if (i < maxIntentos - 1) {
        await Future.delayed(Duration(milliseconds: delayInicialMs * (1 << i)));
      }
    }

    _actualizarConectado(false);
    _failedReconnectCount++;

    if (_failedReconnectCount > 3) {
      RegistroApp.error('Impresora sin respuesta. Reintento en 30 min',
          tag: 'BT');
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(minutes: 30), () {
        _failedReconnectCount = 0;
        intentarReconectar();
      });
    }

    return false;
  }

  void _actualizarConectado(bool valor) {
    _estaConectado = valor;
    _connectionController.add(valor);
  }

  Future<bool> _ensureConnected() async {
    bool conectado = await PrintBluetoothThermal.connectionStatus;
    if (!conectado) {
      await intentarReconectar();
      conectado = await PrintBluetoothThermal.connectionStatus;
    }
    return conectado;
  }

  void _notificarNecesidadEmparejamiento() {
    try {
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
              'Impresora no vinculada. Empareja Bluetooth desde ajustes del dispositivo.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 8),
        ),
      );
    } catch (e) {
      RegistroApp.error('Error mostrando snackbar', tag: 'UI', error: e);
    }
  }

  // ── LIFECYCLE ─────────────────────────────────────────────────────────────
  void dispose() {
    _watchdogTimer?.cancel();
    _reconnectTimer?.cancel();
    _connectionController.close();
    RegistroApp.info('ServicioImpresion disposed', tag: 'BT');
  }

  bool _isPrintSupported() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
