import 'dart:async';
import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class PrinterStatusIndicator extends StatefulWidget {
  const PrinterStatusIndicator({super.key});

  @override
  State<PrinterStatusIndicator> createState() => _PrinterStatusIndicatorState();
}

class _PrinterStatusIndicatorState extends State<PrinterStatusIndicator> {
  bool _isConnected = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    // Verificamos cada 10 segundos para no saturar el Bluetooth
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkStatus();
    });
  }

  Future<void> _checkStatus() async {
    try {
      final bool status = await PrintBluetoothThermal.connectionStatus;
      if (mounted && status != _isConnected) {
        setState(() => _isConnected = status);
      }
    } catch (_) {
      if (mounted) setState(() => _isConnected = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: _isConnected ? 'Impresora conectada' : 'Impresora desconectada',
        child: Icon(
          Icons.print,
          size: 20,
          color: _isConnected ? Colors.greenAccent : Colors.redAccent,
        ),
      ),
    );
  }
}
