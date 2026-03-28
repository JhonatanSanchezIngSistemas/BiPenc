import 'package:flutter/material.dart';
import 'package:bipenc/servicios/servicio_sesion.dart';
import 'package:bipenc/servicios/supabase/servicio_configuracion.dart';

class PantallaConfiguracionNegocio extends StatefulWidget {
  const PantallaConfiguracionNegocio({super.key});

  @override
  State<PantallaConfiguracionNegocio> createState() =>
      _PantallaConfiguracionNegocioState();
}

class _PantallaConfiguracionNegocioState
    extends State<PantallaConfiguracionNegocio> {
  final _formKey = GlobalKey<FormState>();
  final _rucCtrl = TextEditingController();
  final _razonCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _logoUrlCtrl = TextEditingController();

  BusinessProfile? _perfil;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final perfil = await ServicioConfiguracion.obtenerPerfil();
    if (perfil != null) {
      _rucCtrl.text = perfil.ruc;
      _razonCtrl.text = perfil.razonSocial;
      _telCtrl.text = perfil.celular ?? '';
      _emailCtrl.text = perfil.email ?? '';
      _logoUrlCtrl.text = perfil.logoUrl ?? '';
    }
    if (mounted) {
      setState(() {
        _perfil = perfil;
        _loading = false;
      });
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final perfil = BusinessProfile(
      id: _perfil?.id ?? '1',
      ruc: _rucCtrl.text.trim(),
      razonSocial: _razonCtrl.text.trim(),
      celular: _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
      email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      logoUrl:
          _logoUrlCtrl.text.trim().isEmpty ? null : _logoUrlCtrl.text.trim(),
      moneda: _perfil?.moneda ?? 'PEN',
      nombreComercial: _perfil?.nombreComercial,
      direccion: _perfil?.direccion,
    );

    final ok = await ServicioConfiguracion.actualizarPerfil(perfil);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Perfil de negocio actualizado'
            : 'No se pudo actualizar el perfil'),
        backgroundColor: ok ? Colors.teal : Colors.redAccent,
      ),
    );
    if (ok) setState(() => _perfil = perfil);
  }

  @override
  void dispose() {
    _rucCtrl.dispose();
    _razonCtrl.dispose();
    _telCtrl.dispose();
    _emailCtrl.dispose();
    _logoUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ServicioSesion().rol == RolesApp.admin;

    if (!isAdmin) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0F1A),
        appBar: AppBar(
          title: const Text('Acceso restringido',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white70),
        ),
        body: const Center(
          child: Text(
            'Solo administradores pueden configurar el negocio.',
            style: TextStyle(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Configuración Empresarial', 
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
            ),
          ),
        ),
      ),
      body: Container(
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E1422), Color(0xFF101827), Color(0xFF0F0F1A)],
          ),
        ),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              children: [
                // Header Visual
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.tealAccent.withValues(alpha: 0.05),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.1)),
                    ),
                    child: const Icon(Icons.business_center_outlined, size: 48, color: Colors.tealAccent),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'IDENTIDAD CORPORATIVA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.tealAccent,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 2.5,
                  ),
                ),
                const SizedBox(height: 32),
                _field(
                  label: 'RUC / Identificación Fiscal',
                  controller: _rucCtrl,
                  icon: Icons.badge_outlined,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) return 'RUC requerido';
                    if (value.length != 11) return 'RUC debe tener 11 dígitos';
                    return null;
                  },
                ),
                _field(
                  label: 'Razón Social / Nombre Legal',
                  controller: _razonCtrl,
                  icon: Icons.business,
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Razón Social requerida'
                      : null,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        label: 'Teléfono',
                        controller: _telCtrl,
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        label: 'Email de Contacto',
                        controller: _emailCtrl,
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return null;
                          final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(value);
                          return ok ? null : 'Email inválido';
                        },
                      ),
                    ),
                  ],
                ),
                _field(
                  label: 'URL del Logo (Alta Resolución)',
                  controller: _logoUrlCtrl,
                  icon: Icons.link,
                  keyboardType: TextInputType.url,
                  helper: 'Ej: https://mi-empresa.com/logo.png',
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _guardar,
                    icon: const Icon(Icons.save_as_outlined, color: Colors.black),
                    label: const Text('SINCRONIZAR PERFIL', 
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.tealAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 8,
                      shadowColor: Colors.tealAccent.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'Estos datos se usarán en todos los comprobantes PDF generados.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(label.toUpperCase(), 
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          ),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            validator: validator,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: Colors.tealAccent.withValues(alpha: 0.5), size: 20),
              helperText: helper,
              helperStyle: const TextStyle(color: Colors.white24, fontSize: 10),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.03),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.tealAccent, width: 1),
              ),
              errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}
