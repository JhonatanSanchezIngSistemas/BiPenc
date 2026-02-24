import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:usb_serial/usb_serial.dart';

/// Estado de la impresora.
enum PrinterStatus { connected, occupied, offline, error }

/// Clase profesional para gestión de impresión térmica BiPenc.
class PrintingService {
  PrintingService._();
  static final PrintingService instance = PrintingService._();

  // Configuración de Hardware (POS-E802B / 80mm)
  static const String _btMacAddress = '04:7F:0E:4D:18:0F';
  static const int _maxRetries = 3;
  
  bool _isProcessing = false;
  int _paperWidthChars = 48; // 80mm (Font A)

  void setPaperWidth(int width) => _paperWidthChars = width;

  /// Flujo profesional de impresión: Validar -> Conectar -> Enviar -> Confirmar.
  Future<String?> printRawText(String text) async {
    if (_isProcessing) return 'Error: Impresora en uso.';
    
    try {
      _isProcessing = true;
      debugPrint('🚀 [PRINT] Iniciando flujo de impresión...');

      // 1. Intentar USB OTG (Más estable)
      final usbDevices = await UsbSerial.listDevices();
      if (usbDevices.isNotEmpty) {
        final error = await _printViaUsb(usbDevices.first, text);
        if (error == null) return null; // Éxito
        debugPrint('⚠️ [PRINT] Fallo USB, intentando Bluetooth fallback...');
      }

      // 2. Intentar Bluetooth
      final hasPerms = await _requestPermissions();
      if (!hasPerms) return 'Error: Permisos Bluetooth denegados.';

      final errorBt = await _printViaBluetoothWithRetries(text);
      return errorBt;
    } catch (e) {
      debugPrint('🔴 [PRINT] Error crítico: $e');
      return 'Error inesperado: $e';
    } finally {
      _isProcessing = false;
    }
  }

  /// Impresión via USB OTG
  Future<String?> _printViaUsb(UsbDevice device, String text) async {
    UsbPort? port;
    try {
      port = await device.create();
      if (port == null || !(await port.open())) return 'Cerrado/No compatible';

      await port.setPortParameters(9600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

      // ESC/POS Init
      final bytes = Uint8List.fromList([0x1B, 0x40] + text.codeUnits + [0x1D, 0x56, 0x42, 0x00]);
      await port.write(bytes);
      
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      await port?.close();
    }
  }

  /// Impresión via Bluetooth con reintentos y lógica de reconexión.
  Future<String?> _printViaBluetoothWithRetries(String text) async {
    String? lastError;
    
    for (int i = 0; i < _maxRetries; i++) {
      try {
        final bool isEnabled = await PrintBluetoothThermal.bluetoothEnabled;
        if (!isEnabled) return 'Bluetooth desactivado.';

        final bool connected = await PrintBluetoothThermal.connect(macPrinterAddress: _btMacAddress);
        if (!connected) {
          lastError = 'No se pudo conectar a la impresora BT.';
          await Future.delayed(Duration(seconds: 1));
          continue;
        }

        // Dividir texto para evitar saturación de buffer si es necesario
        final bool ok = await PrintBluetoothThermal.writeString(
          printText: PrintTextSize(size: 1, text: text),
        );

        if (ok) return null;
        lastError = 'Error de transmisión de datos.';
      } catch (e) {
        lastError = e.toString();
      } finally {
        await PrintBluetoothThermal.disconnect;
      }
    }
    return lastError;
  }

  Future<bool> _requestPermissions() async {
    if (kIsWeb) return false;
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }
}
