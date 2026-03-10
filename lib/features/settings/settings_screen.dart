import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:bipenc/services/security_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bipenc/services/pdf_service.dart';
import 'package:bipenc/data/models/producto.dart';
import 'package:bipenc/data/models/presentation.dart';
import 'package:pdf/pdf.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _securityService = SecurityService();
  bool _isAuthenticated = false;
  bool _isLoading = true;
  bool _soloWifi = true;

  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _rucCtrl = TextEditingController();
  final _dirCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  // Plantilla térmica
  final _thermalNombreCtrl = TextEditingController();
  final _thermalRucCtrl = TextEditingController();
  final _thermalDirCtrl = TextEditingController();
  final _thermalTelCtrl = TextEditingController();
  final _thermalMsgCtrl = TextEditingController();

  // Plantilla PDF
  final _pdfNombreCtrl = TextEditingController();
  final _pdfRucCtrl = TextEditingController();
  final _pdfDirCtrl = TextEditingController();
  final _pdfFooterCtrl = TextEditingController();
  final _pdfAutorCtrl = TextEditingController();
  final _pdfLogoPathCtrl = TextEditingController();
  final _pdfTaglineCtrl = TextEditingController();
  final _pdfTelCtrl = TextEditingController();
  bool _pdfShowQr = true;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Para simplificar, forzamos al usuario a poner el PIN al entrar
    setState(() => _isLoading = false);
  }

  Future<void> _loadBusinessData() async {
    final prefs = await SharedPreferences.getInstance();
    _nombreCtrl.text = prefs.getString('biz_nombre') ?? 'Librería BiPenc';
    _rucCtrl.text = prefs.getString('biz_ruc') ?? '00000000000';
    _dirCtrl.text = prefs.getString('biz_dir') ?? 'Ciudad Principal';
    _telCtrl.text = prefs.getString('biz_tel') ?? '';
    _msgCtrl.text = prefs.getString('biz_msg') ?? '¡Vuelve pronto!';
    _thermalNombreCtrl.text = prefs.getString('thermal_nombre') ?? _nombreCtrl.text;
    _thermalRucCtrl.text = prefs.getString('thermal_ruc') ?? _rucCtrl.text;
    _thermalDirCtrl.text = prefs.getString('thermal_dir') ?? _dirCtrl.text;
    _thermalTelCtrl.text = prefs.getString('thermal_tel') ?? _telCtrl.text;
    _thermalMsgCtrl.text = prefs.getString('thermal_msg') ?? _msgCtrl.text;

    _pdfNombreCtrl.text = prefs.getString('pdf_nombre') ?? _nombreCtrl.text;
    _pdfRucCtrl.text = prefs.getString('pdf_ruc') ?? _rucCtrl.text;
    _pdfDirCtrl.text = prefs.getString('pdf_dir') ?? _dirCtrl.text;
    _pdfFooterCtrl.text = prefs.getString('pdf_footer') ?? '¡GRACIAS POR SU PREFERENCIA!';
    _pdfAutorCtrl.text = prefs.getString('pdf_autor') ?? '';
    _pdfLogoPathCtrl.text = prefs.getString('pdf_logo_path') ?? '';
    _pdfTaglineCtrl.text = prefs.getString('pdf_tagline') ?? 'Calidad y Servicio';
    _pdfTelCtrl.text = prefs.getString('pdf_tel') ?? _telCtrl.text;
    _pdfShowQr = prefs.getBool('pdf_show_qr') ?? true;
    setState(() {
      _soloWifi = prefs.getBool('sync_solo_wifi') ?? true;
    });
  }

  Future<void> _guardarConfiguracion() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('biz_nombre', _nombreCtrl.text);
      await prefs.setString('biz_ruc', _rucCtrl.text);
      await prefs.setString('biz_dir', _dirCtrl.text);
      await prefs.setString('biz_tel', _telCtrl.text);
      await prefs.setString('biz_msg', _msgCtrl.text);
      await prefs.setBool('sync_solo_wifi', _soloWifi);

      // Defaults térmica
      await prefs.setString('thermal_nombre', _thermalNombreCtrl.text.trim());
      await prefs.setString('thermal_ruc', _thermalRucCtrl.text.trim());
      await prefs.setString('thermal_dir', _thermalDirCtrl.text.trim());
      await prefs.setString('thermal_tel', _thermalTelCtrl.text.trim());
      await prefs.setString('thermal_msg', _thermalMsgCtrl.text.trim());

      // Defaults PDF
      await prefs.setString('pdf_nombre', _pdfNombreCtrl.text.trim());
      await prefs.setString('pdf_ruc', _pdfRucCtrl.text.trim());
      await prefs.setString('pdf_dir', _pdfDirCtrl.text.trim());
      await prefs.setString('pdf_footer', _pdfFooterCtrl.text.trim());
      await prefs.setString('pdf_autor', _pdfAutorCtrl.text.trim());
      await prefs.setString('pdf_logo_path', _pdfLogoPathCtrl.text.trim());
      await prefs.setString('pdf_tagline', _pdfTaglineCtrl.text.trim());
      await prefs.setString('pdf_tel', _pdfTelCtrl.text.trim());
      await prefs.setBool('pdf_show_qr', _pdfShowQr);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración guardada exitosamente.', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _generarBackup() async {
    final status = await Permission.storage.request();
    // En Android 11+ (API 30+) puede requerir manageExternalStorage
    if (!status.isGranted) {
      await Permission.manageExternalStorage.request();
    }
    
    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'bipenc_local.db');
      final currentDB = File(path);
      
      if (await currentDB.exists()) {
        Directory? dir;
        if (Platform.isAndroid) {
          dir = Directory('/storage/emulated/0/Download');
          if (!await dir.exists()) {
            dir = await getExternalStorageDirectory();
          }
        } else {
          dir = await getDownloadsDirectory();
        }
        
        final backupPath = p.join(dir!.path, 'Respaldo_BiPenc_${DateTime.now().millisecondsSinceEpoch}.db');
        await currentDB.copy(backupPath);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Respaldo en Frío creado en: $backupPath'), backgroundColor: Colors.green, duration: const Duration(seconds: 4)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al generar backup: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _mostrarAyudaWhatsApp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Row(children: [Icon(Icons.chat_bubble_outline, color: Colors.greenAccent), SizedBox(width: 8), Text('WhatsApp (Meta)', style: TextStyle(color: Colors.white))]),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Para integrar WhatsApp Business API (Cloud), debes registrar la app en el portal de Meta Developers.', style: TextStyle(color: Colors.white70, fontSize: 13)),
            SizedBox(height: 12),
            Text('Package Name:', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 12)),
            Text('com.jhonatan.bipenc', style: TextStyle(color: Colors.white)),
            SizedBox(height: 12),
            Text('SHA-256 Check (Terminal):', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 12)),
            Text('keytool -list -v -keystore ~/.android/debug.keystore', style: TextStyle(color: Colors.white54, fontSize: 11)),
            SizedBox(height: 12),
            Text('Cierra el reporte de cierre Z y compártelo usando el botón de compartir.', style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CERRAR'))],
      ),
    );
  }

  void _autenticarAdmin() async {
    final pin = _pinCtrl.text;
    final esValido = await _securityService.validarAccesoAdministrador(pin);
    if (esValido) {
      setState(() {
        _isAuthenticated = true;
      });
      await _loadBusinessData();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN Incorrecto'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickPdfLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800);
    if (picked != null) {
      _pdfLogoPathCtrl.text = picked.path;
      if (mounted) setState(() {});
    }
  }

  Future<void> _previewPdf() async {
    if (_previewing) return;
    setState(() => _previewing = true);
    try {
      final items = _mockItems();
      final file = await PdfService.generateVentaPdf(
        items: items,
        total: items.fold<double>(0, (s, i) => s + i.subtotal),
        vendedor: 'PREVIEW',
        correlativo: 'B001-TEST',
        cliente: 'CLIENTE DEMO',
        metodoPago: 'efectivo',
        pageFormat: PdfPageFormat.a4,
      );
      await PdfService.shareVentaPdf(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generando PDF: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  List<ItemCarrito> _mockItems() {
    final pres = Presentation(
      id: 'p1',
      skuCode: 'SKU001',
      name: 'Unidad',
      conversionFactor: 1,
      prices: [
        PricePoint(type: 'NORMAL', amount: 5.5),
        PricePoint(type: 'WHOLESALE', amount: 5.0),
        PricePoint(type: 'SPECIAL', amount: 4.5),
      ],
    );
    final prod = Producto(
      id: 'prod1',
      skuCode: 'SKU001',
      nombre: 'Producto Demo',
      presentaciones: [pres],
      marca: 'Marca X',
      categoria: 'Categoría',
    );
    return [
      ItemCarrito(producto: prod, presentacion: pres, cantidad: 2),
      ItemCarrito(
          producto: prod.copyWith(id: 'prod2', skuCode: 'SKU002', nombre: 'Producto B'),
          presentacion: pres.copyWith(id: 'p2', skuCode: 'SKU002'),
          cantidad: 1,
          manualPriceOverride: 7.0),
    ];
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _rucCtrl.dispose();
    _dirCtrl.dispose();
    _telCtrl.dispose();
    _msgCtrl.dispose();
    _pinCtrl.dispose();
    _thermalNombreCtrl.dispose();
    _thermalRucCtrl.dispose();
    _thermalDirCtrl.dispose();
    _thermalTelCtrl.dispose();
    _thermalMsgCtrl.dispose();
    _pdfNombreCtrl.dispose();
    _pdfRucCtrl.dispose();
    _pdfDirCtrl.dispose();
    _pdfFooterCtrl.dispose();
    _pdfAutorCtrl.dispose();
    _pdfLogoPathCtrl.dispose();
    _pdfTaglineCtrl.dispose();
    _pdfTelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Acceso Restringido'), backgroundColor: const Color(0xFF121B2B)),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0E1422), Color(0xFF101827), Color(0xFF0F0F1A)],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.security, size: 80, color: Colors.teal),
                  const SizedBox(height: 24),
                  const Text('Protección por SHA-256', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'PIN de Administrador',
                      prefixIcon: Icon(Icons.lock),
                    ),
                    onSubmitted: (_) => _autenticarAdmin(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _autenticarAdmin,
                    icon: const Icon(Icons.login),
                    label: const Text('Ingresar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración de Negocio'), backgroundColor: const Color(0xFF121B2B)),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E1422), Color(0xFF101827), Color(0xFF0F0F1A)],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Card(
                color: const Color(0xFF121B2B),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text('Datos de la Empresa para Impresión', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Divider(),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nombreCtrl,
                        decoration: const InputDecoration(labelText: 'Nombre Comercial (Ej. Doña Lola)', border: OutlineInputBorder()),
                        validator: (v) => v!.isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _rucCtrl,
                        decoration: const InputDecoration(labelText: 'RUC / NIT', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _telCtrl,
                        decoration: const InputDecoration(labelText: 'Teléfono / WhatsApp', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _dirCtrl,
                        decoration: const InputDecoration(labelText: 'Dirección', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _msgCtrl,
                        decoration: const InputDecoration(labelText: 'Mensaje de Despedida', border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: const Color(0xFF121B2B),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text('Plantilla Térmica (Ticket)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Divider(),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _thermalNombreCtrl,
                        decoration: const InputDecoration(labelText: 'Nombre (térmica)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _thermalRucCtrl,
                        decoration: const InputDecoration(labelText: 'RUC (térmica)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _thermalTelCtrl,
                        decoration: const InputDecoration(labelText: 'Teléfono (térmica)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _thermalDirCtrl,
                        decoration: const InputDecoration(labelText: 'Dirección (térmica)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _thermalMsgCtrl,
                        decoration: const InputDecoration(labelText: 'Mensaje final (térmica)', border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: const Color(0xFF121B2B),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Plantilla PDF A4 (doble columna)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Divider(),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 340,
                            child: TextFormField(
                              controller: _pdfNombreCtrl,
                              decoration: const InputDecoration(labelText: 'Nombre empresa (PDF)', border: OutlineInputBorder()),
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            child: TextFormField(
                              controller: _pdfRucCtrl,
                              decoration: const InputDecoration(labelText: 'RUC (PDF)', border: OutlineInputBorder()),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: TextFormField(
                              controller: _pdfTelCtrl,
                              decoration: const InputDecoration(labelText: 'Teléfono / WhatsApp (PDF)', border: OutlineInputBorder()),
                            ),
                          ),
                          SizedBox(
                            width: 360,
                            child: TextFormField(
                              controller: _pdfDirCtrl,
                              decoration: const InputDecoration(labelText: 'Dirección (PDF)', border: OutlineInputBorder()),
                            ),
                          ),
                          SizedBox(
                            width: 340,
                            child: TextFormField(
                              controller: _pdfTaglineCtrl,
                              decoration: const InputDecoration(labelText: 'Frase calidad/servicio', border: OutlineInputBorder()),
                            ),
                          ),
                          SizedBox(
                            width: 340,
                            child: TextFormField(
                              controller: _pdfFooterCtrl,
                              decoration: const InputDecoration(labelText: 'Footer (PDF)', border: OutlineInputBorder()),
                            ),
                          ),
                          SizedBox(
                            width: 340,
                            child: TextFormField(
                              controller: _pdfAutorCtrl,
                              decoration: const InputDecoration(labelText: 'Autor/Firma (PDF)', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        value: _pdfShowQr,
                        onChanged: (v) => setState(() => _pdfShowQr = v),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Incluir QR de comprobante en PDF'),
                        subtitle: const Text('Usa los datos SUNAT (serie, correlativo, total, IGV) para evitar reimpresiones incorrectas.'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _pdfLogoPathCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Ruta logo local (PDF, opcional)',
                                border: OutlineInputBorder(),
                              ),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _pickPdfLogo,
                            icon: const Icon(Icons.upload),
                            label: const Text('Cargar logo'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.tealAccent,
                              side: const BorderSide(color: Colors.tealAccent),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _previewing ? null : _previewPdf,
                        icon: const Icon(Icons.picture_as_pdf),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12.0),
                          child: Text(_previewing ? 'Generando...' : 'Previsualizar PDF'),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _guardarConfiguracion,
                icon: const Icon(Icons.save),
                label: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Guardar Configuración', style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              const Text('Seguridad y Respaldo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Subir Fotos/Backups Solo con Wi-Fi'),
                subtitle: const Text('Evita consumir el plan de datos móviles del dispositivo.'),
                value: _soloWifi,
                activeThumbColor: Colors.teal,
                onChanged: (val) {
                  setState(() => _soloWifi = val);
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _generarBackup,
                icon: const Icon(Icons.backup),
                label: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Generar Copia de Seguridad (Respaldo en Frío)', style: TextStyle(fontSize: 16)),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal,
                  side: const BorderSide(color: Colors.teal),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _mostrarAyudaWhatsApp,
                icon: const Icon(Icons.chat_bubble_outline, color: Colors.greenAccent),
                label: const Text('Configuración WhatsApp (Meta/SHA-256)', style: TextStyle(color: Colors.greenAccent)),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
