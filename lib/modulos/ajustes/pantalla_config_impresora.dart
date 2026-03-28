import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:bipenc/servicios/servicio_impresion.dart';
import 'package:bipenc/servicios/cola_impresion.dart';
import 'package:bipenc/datos/modelos/producto.dart';
import 'package:bipenc/datos/modelos/presentacion.dart';

class PantallaConfigImpresora extends StatefulWidget {
  const PantallaConfigImpresora({super.key});

  @override
  State<PantallaConfigImpresora> createState() => _PantallaConfigImpresoraState();
}

class _PantallaConfigImpresoraState extends State<PantallaConfigImpresora> {
  List<BluetoothInfo> _devices = [];
  bool _scanning = false;
  String? _savedMac;

  // Controladores para la cabecera del ticket
  final _nombreCtrl = TextEditingController();
  final _rucCtrl = TextEditingController();
  final _dirCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _serieCtrl = TextEditingController();
  String _selectedCodePage = 'CP1252';
  String _selectedPaperSize = '80';
  static const _codePages = ['CP1252'];
  static const _paperSizes = ['80', '58'];

  @override
  void initState() {
    super.initState();
    _loadSavedPrinter();
  }

  Future<void> _loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedMac = prefs.getString('printer_mac');
      _nombreCtrl.text = prefs.getString('biz_nombre') ?? 'Librería BiPenc';
      _rucCtrl.text = prefs.getString('biz_ruc') ?? '00000000000';
      _dirCtrl.text = prefs.getString('biz_dir') ?? 'Ciudad Principal';
      _telCtrl.text =
          prefs.getString('thermal_tel') ?? prefs.getString('biz_tel') ?? '';
      _serieCtrl.text = prefs.getString('biz_serie') ?? 'B001';
      _selectedCodePage =
          prefs.getString('thermal_code_page')?.toUpperCase() ?? 'CP1252';
      _selectedPaperSize =
          (prefs.getString('thermal_paper_size') ?? '80').trim();
    });
    // Escaneo automático al entrar para mejorar UX
    _scanDevices();
  }

  Future<void> _saveHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('biz_nombre', _nombreCtrl.text.trim());
    await prefs.setString('biz_ruc', _rucCtrl.text.trim());
    await prefs.setString('biz_dir', _dirCtrl.text.trim());
    await prefs.setString('biz_tel', _telCtrl.text.trim());
    await prefs.setString('thermal_tel', _telCtrl.text.trim());
    await prefs.setString(
        'biz_serie',
        _serieCtrl.text.trim().isEmpty
            ? 'B001'
            : _serieCtrl.text.trim().toUpperCase());
    await prefs.setString('thermal_code_page', _selectedCodePage);
    await prefs.setString('thermal_paper_size', _selectedPaperSize);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('✅ Cabecera guardada'), backgroundColor: Colors.teal),
      );
    }
  }

  Future<void> _probarImpresion() async {
    await _saveHeaders();
    final ok = await ServicioImpresion().imprimirPruebaCalibracion();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Prueba enviada a la impresora'
              : 'No se pudo imprimir ahora. Se encoló para reintento.',
        ),
        backgroundColor: ok ? Colors.teal : Colors.orange,
      ),
    );
  }

  Future<void> _scanDevices() async {
    if (_scanning) return;
    setState(() => _scanning = true);

    // Gestión de Permisos Android 12+ (Constitución Art 1.2)
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (statuses[Permission.bluetoothScan] != PermissionStatus.granted ||
        statuses[Permission.bluetoothConnect] != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '⚠️ Permisos de Bluetooth denegados. Actívalos en Ajustes.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      setState(() => _scanning = false);
      return;
    }

    // Verificar si el BT está encendido físicamente
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

    final results = await PrintBluetoothThermal.pairedBluetooths;
    final filtered = results.where(_isLikelyPrinter).toList();
    setState(() {
      _devices = filtered;
      _scanning = false;
    });
  }

  bool _isLikelyPrinter(BluetoothInfo d) {
    final name = d.name.toLowerCase();
    const printerHints = [
      'printer',
      'print',
      'thermal',
      'pt-',
      'pt210',
      'pos',
      'xp-',
      'epson',
      'tm-',
      'esc',
      'rp-',
      'mpt',
    ];
    return printerHints.any(name.contains);
  }

  Future<void> _selectPrinter(BluetoothInfo device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_mac', device.macAdress);
    await prefs.setString('printer_name', device.name);

    setState(() => _savedMac = device.macAdress);

    // Intentar conectar inmediatamente
    await ServicioImpresion().intentarReconectar();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ticketera configurada: ${device.name}'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        title: const Text('Configurar Impresora'),
        backgroundColor: const Color(0xFF121B2B),
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
                icon: const Icon(Icons.refresh), onPressed: _scanDevices),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E1422), Color(0xFF101827), Color(0xFF0F0F1A)],
          ),
        ),
        child: _devices.isEmpty
            ? _buildEmptyState()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeaderSection(),
                  const SizedBox(height: 16),
                  _buildQueueSection(),
                  const SizedBox(height: 24),
                  const Text('DISPOSITIVOS VINCULADOS',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  ..._devices.map((d) {
                    final isSelected = d.macAdress == _savedMac;
                    return Card(
                      color: isSelected
                          ? Colors.teal.withValues(alpha: 0.2)
                          : const Color(0xFF121B2B),
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                            color: isSelected ? Colors.teal : Colors.white10),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.print,
                            color: isSelected
                                ? Colors.tealAccent
                                : Colors.white54),
                        title: Text(d.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(d.macAdress,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle,
                                color: Colors.tealAccent)
                            : const Icon(Icons.circle_outlined,
                                color: Colors.white24),
                        onTap: () => _selectPrinter(d),
                      ),
                    );
                  }),
                ],
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bluetooth_searching,
              size: 64, color: Colors.white10),
          const SizedBox(height: 16),
          const Text('No se detectaron impresoras',
              style: TextStyle(color: Colors.white38)),
          const SizedBox(height: 8),
          const Text(
              'Solo se listan dispositivos tipo impresora.\nVincula tu PT-210 desde Bluetooth del teléfono.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white24, fontSize: 12)),
          const SizedBox(height: 24),
          ElevatedButton(
              onPressed: _scanDevices, child: const Text('Buscar de nuevo')),
        ],
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Card(
      color: const Color(0xFF121B2B),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white10)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('CABECERA DEL TICKET',
                style: TextStyle(
                    color: Colors.tealAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            const SizedBox(height: 16),
            _buildTextField(
                _nombreCtrl, 'Nombre de la Empresa', Icons.business),
            const SizedBox(height: 12),
            _buildTextField(
                _rucCtrl, 'RUC / Identificación', Icons.badge_outlined),
            const SizedBox(height: 12),
            _buildTextField(
                _dirCtrl, 'Dirección / Localidad', Icons.location_on_outlined),
            const SizedBox(height: 12),
            _buildTextField(
                _telCtrl, 'Teléfono (ticket)', Icons.phone_outlined),
            const SizedBox(height: 12),
            TextField(
              controller: _serieCtrl,
              enabled: false,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Serie boleta (automática por sistema)',
                helperText: 'Se maneja por correlativo del sistema y usuario.',
                helperStyle:
                    const TextStyle(color: Colors.white38, fontSize: 11),
                labelStyle:
                    const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(Icons.confirmation_num_outlined,
                    color: Colors.teal, size: 20),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.03),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedPaperSize,
              decoration: InputDecoration(
                labelText: 'Ancho de papel',
                helperText: 'Usa 80mm para PT-210, 58mm para modelos compactos',
                labelStyle:
                    const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              dropdownColor: Colors.grey.shade900,
              items: _paperSizes
                  .map((sz) =>
                      DropdownMenuItem(value: sz, child: Text('$sz mm')))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _selectedPaperSize = v);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedCodePage,
              decoration: InputDecoration(
                labelText: 'Code page (caracteres)',
                helperText: 'Fijado en CP1252 (estable para acentos)',
                labelStyle:
                    const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              dropdownColor: Colors.grey.shade900,
              items: _codePages
                  .map((cp) => DropdownMenuItem(value: cp, child: Text(cp)))
                  .toList(),
              onChanged: null,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saveHeaders,
              icon: const Icon(Icons.save),
              label: const Text('GUARDAR CABECERA'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal.withValues(alpha: 0.8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _probarImpresion,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('IMPRIMIR PRUEBA'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.tealAccent,
                side: const BorderSide(color: Colors.tealAccent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _previewTicket,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Ver preview texto'),
              style: TextButton.styleFrom(foregroundColor: Colors.tealAccent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueSection() {
    return Card(
      color: const Color(0xFF121B2B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Cola de impresión',
                style: TextStyle(
                    color: Colors.tealAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
              future: ColaImpresion.obtenerEstadisticas(),
              builder: (context, snap) {
                final data = snap.data ??
                    const {'pendientes': 0, 'impresos': 0, 'fallidos': 0};
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _badge('Pendientes', data['pendientes'], Colors.amber),
                    _badge('Impresos', data['impresos'], Colors.greenAccent),
                    _badge('Fallidos', data['fallidos'], Colors.redAccent),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await ColaImpresion.procesarCola();
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.playlist_play),
                    label: const Text('Reprocesar ahora'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.tealAccent,
                      side: const BorderSide(color: Colors.tealAccent),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await ColaImpresion.vaciar();
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Vaciar cola'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, int value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            '$value',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
      TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        prefixIcon: Icon(icon, color: Colors.teal, size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      ),
    );
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _rucCtrl.dispose();
    _dirCtrl.dispose();
    _telCtrl.dispose();
    _serieCtrl.dispose();
    super.dispose();
  }

  void _previewTicket() {
    final dummyItem = ItemCarrito(
      producto: Producto(
        id: 'p1',
        skuCode: 'SKU001',
        nombre: 'Producto Demo',
        presentaciones: const [],
      ),
      presentacion: Presentacion.unit,
      cantidad: 1,
    );
    final text = ServicioImpresion.renderTicketPreview(
      items: [dummyItem],
      total: dummyItem.subtotal,
      serie: 'B001',
      correlativo: 'TEST-001',
      cliente: 'Cliente Demo',
      vendedor: 'Preview',
      metodoPago: 'efectivo',
      montoRecibido: 10,
      vuelto: 4.5,
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Text('Preview Ticket', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'monospace',
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar', style: TextStyle(color: Colors.tealAccent)))
        ],
      ),
    );
  }
}
