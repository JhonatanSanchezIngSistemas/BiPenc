import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config/theme.dart';
import '../services/supabase_service.dart';
import '../models/producto.dart';

/// Pantalla "About" con información del creador y detalles de la app.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _packageInfo;
  Perfil? _perfil;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final info = await PackageInfo.fromPlatform();
    final p = await SupabaseService.obtenerPerfil();
    if (mounted) {
      setState(() {
        _packageInfo = info;
        _perfil = p;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: BiPencTheme.backgroundDark,
        body: Center(child: CircularProgressIndicator(color: BiPencTheme.primaryTeal)),
      );
    }

    return Scaffold(
      backgroundColor: BiPencTheme.backgroundDark,
      appBar: AppBar(
        title: const Text('Acerca de BiPenc'),
        backgroundColor: Colors.transparent,
        foregroundColor: BiPencTheme.primaryTeal,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo / Ícono de la app
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      BiPencTheme.primaryTeal,
                      BiPencTheme.primaryTeal.withOpacity(0.5),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: BiPencTheme.primaryTeal.withOpacity(0.4),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.store,
                  size: 60,
                  color: Colors.black,
                ),
              ),
              
              const SizedBox(height: 24),

              // Título
              const Text(
                'BiPenc',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: BiPencTheme.primaryTeal,
                  letterSpacing: 3,
                ),
              ),

              const SizedBox(height: 8),

              // Versión dinámica
              if (_packageInfo != null)
                Text(
                  'v${_packageInfo!.version}+${_packageInfo!.buildNumber} | BiPenc Official',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    letterSpacing: 1,
                  ),
                ),

              const SizedBox(height: 40),

              // Información del creador / Usuario actual
              _buildCreatorCard(),

              const SizedBox(height: 32),

              // Descripción
              Text(
                'Sistema de Gestión Integral para Librerías Escolares',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),

              const SizedBox(height: 24),

              // Features
              _buildFeaturesList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreatorCard() {
    final nombre = _perfil?.nombreCompleto ?? 'Invitado';
    final alias = _perfil?.alias ?? '???';
    final rol = _perfil?.rol ?? 'USER';
    final isCreator = alias == 'JJGS';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: BiPencTheme.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: BiPencTheme.primaryTeal.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: [
          // Avatar
          CircleAvatar(
            radius: 40,
            backgroundColor: BiPencTheme.primaryTeal.withOpacity(0.2),
            child: Icon(
              isCreator ? Icons.verified_user : Icons.person,
              size: 50,
              color: BiPencTheme.primaryTeal,
            ),
          ),

          const SizedBox(height: 16),

          Text(
            nombre,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 4),

          BiPencTheme.aliasBadge(alias),

          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: (isCreator ? BiPencTheme.warningOrange : BiPencTheme.primaryTeal).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: (isCreator ? BiPencTheme.warningOrange : BiPencTheme.primaryTeal).withOpacity(0.3),
              ),
            ),
            child: Text(
              isCreator ? 'ADMIN • Creator' : '$rol • User',
              style: TextStyle(
                color: isCreator ? BiPencTheme.warningOrange : BiPencTheme.primaryTeal,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesList() {
    final features = [
      'Catálogo en la Nube con Supabase',
      'Validación Colaborativa por Consenso',
      'Historial de Ventas con Correlativos',
      'Auditoría de Precios Multi-Usuario',
      'Autenticación Biométrica',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: features
          .map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: BiPencTheme.successGreen,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        f,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }
}
