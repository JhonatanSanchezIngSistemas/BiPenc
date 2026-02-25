import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrinterConfigScreen extends StatefulWidget {
  const PrinterConfigScreen({super.key});

  @override
  State<PrinterConfigScreen> createState() => _PrinterConfigScreenState();
}

class _PrinterConfigScreenState extends State<PrinterConfigScreen> {
  List<BluetoothInfo> _devices = [];
  bool _scanning = false;
  String? _savedMac;

  @override
  void initState() {
    super.initState();
    _loadSavedPrinter();
  }

  Future<void> _loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedMac = prefs.getString('printer_mac');
    });
    _scanDevices();
  }

  Future<void> _scanDevices() async {
    setState(() => _scanning = true);
    // Verificar permisos y estado de BT
    final btEnabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!btEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, activa el Bluetooth')),
        );
      }
      setState(() => _scanning = false);
      return;
    }

    final results = await PrintBluetoothThermal.pairedBluetoothDevice;
    setState(() {
      _devices = results;
      _scanning = false;
    });
  }

  Future<void> _selectPrinter(BluetoothInfo device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_mac', device.macAdress);
    await prefs.setString('printer_name', device.name);
    
    setState(() => _savedMac = device.macAdress);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ticketera vinculada: ${device.name}'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Configurar Impresora'),
        backgroundColor: Colors.grey.shade900,
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(icon: const Icon(Icons.refresh), onPressed: _scanDevices),
        ],
      ),
      body: _devices.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final d = _devices[index];
                final isSelected = d.macAdress == _savedMac;
                return Card(
                  color: isSelected ? Colors.teal.withOpacity(0.2) : Colors.grey.shade900,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: isSelected ? Colors.teal : Colors.white10),
                  ),
                  child: ListTile(
                    leading: Icon(Icons.print, color: isSelected ? Colors.tealAccent : Colors.white54),
                    title: Text(d.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text(d.macAdress, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    trailing: isSelected 
                        ? const Icon(Icons.check_circle, color: Colors.tealAccent)
                        : const Icon(Icons.circle_outlined, color: Colors.white24),
                    onTap: () => _selectPrinter(d),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bluetooth_searching, size: 64, color: Colors.white10),
          const SizedBox(height: 16),
          const Text('No se han emparejado ticketeras', style: TextStyle(color: Colors.white38)),
          const SizedBox(height: 8),
          const Text('Asegúrate de vincular tu PT-210 en el\nmenú de Bluetooth de tu Samsung A36', 
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 12)),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _scanDevices, child: const Text('Buscar de nuevo')),
        ],
      ),
    );
  }
}
