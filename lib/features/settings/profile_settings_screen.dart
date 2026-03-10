import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bipenc/services/session_service.dart';
import 'package:bipenc/services/supabase_service.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _apellidoCtrl = TextEditingController();
  final _aliasCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _avatarCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  bool _loading = true;
  bool _savingProfile = false;
  bool _savingPass = false;
  bool _savingEmail = false;

  String get _email => Supabase.instance.client.auth.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final perfil = await SessionService().obtenerPerfil(forceRefresh: true);
    if (!mounted) return;
    _nombreCtrl.text = perfil?.nombre ?? '';
    _apellidoCtrl.text = perfil?.apellido ?? '';
    _aliasCtrl.text = perfil?.alias ?? '';
    _emailCtrl.text = _email;
    setState(() => _loading = false);
  }

  Future<void> _guardarPerfil() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _savingProfile = true);
    final ok = await SupabaseService.actualizarPerfil(
      nombre: _nombreCtrl.text,
      apellido: _apellidoCtrl.text,
      alias: _aliasCtrl.text,
      avatarUrl: _avatarCtrl.text,
    );
    await SessionService().obtenerPerfil(forceRefresh: true);
    if (!mounted) return;
    setState(() => _savingProfile = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(ok ? 'Perfil actualizado' : 'No se pudo actualizar perfil'),
        backgroundColor: ok ? Colors.green : Colors.redAccent,
      ),
    );
  }

  Future<void> _cambiarPassword() async {
    final p1 = _passCtrl.text.trim();
    final p2 = _pass2Ctrl.text.trim();
    if (p1.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('La contraseña debe tener al menos 8 caracteres')),
      );
      return;
    }
    if (p1 != p2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Las contraseñas no coinciden')),
      );
      return;
    }
    setState(() => _savingPass = true);
    final err = await SupabaseService.cambiarPassword(nuevaPassword: p1);
    if (!mounted) return;
    setState(() => _savingPass = false);
    if (err == null) {
      _passCtrl.clear();
      _pass2Ctrl.clear();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? 'Contraseña actualizada'),
        backgroundColor: err == null ? Colors.green : Colors.redAccent,
      ),
    );
  }

  Future<void> _guardarEmail() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty || !email.endsWith('@bipenc.com')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El correo debe terminar en @bipenc.com')),
      );
      return;
    }
    setState(() => _savingEmail = true);
    final err = await SupabaseService.cambiarEmail(nuevoEmail: email);
    if (!mounted) return;
    setState(() => _savingEmail = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(err ?? 'Correo actualizado. Revisa confirmación en tu email.'),
        backgroundColor: err == null ? Colors.green : Colors.redAccent,
      ),
    );
  }

  Future<void> _seleccionarFoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (photo == null) return;
    final url = await SupabaseService.subirAvatarPerfil(File(photo.path));
    if (!mounted) return;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se pudo subir la foto'),
            backgroundColor: Colors.redAccent),
      );
      return;
    }
    setState(() => _avatarCtrl.text = url);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Foto de perfil cargada'),
          backgroundColor: Colors.teal),
    );
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _apellidoCtrl.dispose();
    _aliasCtrl.dispose();
    _emailCtrl.dispose();
    _avatarCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0E1422), Color(0xFF101827), Color(0xFF0F0F1A)],
            ),
          ),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
          title: const Text('Mi Cuenta'),
          backgroundColor: const Color(0xFF121B2B)),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E1422), Color(0xFF101827), Color(0xFF0F0F1A)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: const Color(0xFF121B2B),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Datos de perfil',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Correo',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          onPressed: _savingEmail ? null : _guardarEmail,
                          icon: const Icon(Icons.alternate_email),
                          label: Text(_savingEmail
                              ? 'Guardando...'
                              : 'Actualizar Correo'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Requerido'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _apellidoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Apellido',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _aliasCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Alias (aparece en boletas)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Requerido'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _avatarCtrl,
                        decoration: const InputDecoration(
                          labelText: 'URL de foto de perfil (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: _seleccionarFoto,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Subir foto'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _savingProfile ? null : _guardarPerfil,
                        icon: _savingProfile
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: const Text('Guardar Perfil'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: const Color(0xFF121B2B),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Cambiar contraseña',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Nueva contraseña',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass2Ctrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirmar nueva contraseña',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _savingPass ? null : _cambiarPassword,
                      icon: _savingPass
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_reset),
                      label: const Text('Actualizar Contraseña'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
