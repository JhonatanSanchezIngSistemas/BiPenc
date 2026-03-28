import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../servicios/servicio_backend.dart';
import 'componentes/menu_lateral.dart';

class LayoutPrincipal extends StatefulWidget {
  final Widget child;
  const LayoutPrincipal({super.key, required this.child});

  @override
  State<LayoutPrincipal> createState() => _LayoutPrincipalState();
}

class _LayoutPrincipalState extends State<LayoutPrincipal> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    try {
      final minVersion = await ServicioBackend.obtenerVersionMinima();
      if (minVersion == null) return;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (_isVersionLower(currentVersion, minVersion)) {
        if (mounted) {
          _showUpdateBanner();
        }
      }
    } catch (e) {
      debugPrint('Error en update checker: $e');
    }
  }

  bool _isVersionLower(String current, String min) {
    try {
      List<int> c = current.split('.').map(int.parse).toList();
      List<int> m = min.split('.').map(int.parse).toList();
      for (int i = 0; i < m.length; i++) {
        if (i >= c.length) return true;
        if (c[i] < m[i]) return true;
        if (c[i] > m[i]) false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _showUpdateBanner() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.system_update_alt, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
                child: Text('Actualización crítica disponible.',
                    style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        backgroundColor: Colors.indigo,
        duration: Duration(days: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    
    // Títulos dinámicos según ruta
    String title = 'BiPenc';
    if (location == '/') title = 'Inicio';
    else if (location.startsWith('/pos')) title = 'Caja (POS)';
    else if (location.startsWith('/pedidos')) title = 'Pedidos';
    else if (location.startsWith('/inventario')) title = 'Inventario';
    else if (location.startsWith('/admin')) title = 'Administración';
    else if (location.startsWith('/boletas')) title = 'Reportes';

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        backgroundColor: const Color(0xFF0D111B),
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, color: Colors.white54),
            onPressed: () {}, // Futuro: Notificaciones
          ),
        ],
      ),
      drawer: const MenuLateral(),
      body: widget.child,
    );
  }
}

