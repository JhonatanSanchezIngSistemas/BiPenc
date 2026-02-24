import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import '../../data/models/business_config.dart';
import '../../services/security_service.dart';

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
    _telCtrl.text = prefs.getString('biz_tel') ?? '123456789';
    _msgCtrl.text = prefs.getString('biz_msg') ?? '¡Vuelve pronto!';
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
      final path = join(dbPath, 'bipenc_local.db');
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
        
        final backupPath = join(dir!.path, 'Respaldo_BiPenc_\${DateTime.now().millisecondsSinceEpoch}.db');
        await currentDB.copy(backupPath);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Respaldo en Frío creado en: \$backupPath'), backgroundColor: Colors.green, duration: const Duration(seconds: 4)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al generar backup: \$e'), backgroundColor: Colors.red));
      }
    }
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Acceso Restringido')),
        body: Center(
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
                    border: OutlineInputBorder(),
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
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración de Negocio')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
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
                activeColor: Colors.teal,
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
              )
            ],
          ),
        ),
      ),
    );
  }
}
