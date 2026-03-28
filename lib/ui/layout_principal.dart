import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../servicios/servicio_backend.dart';

class LayoutPrincipal extends StatefulWidget {
  final Widget child;
  const LayoutPrincipal({super.key, required this.child});

  @override
  State<LayoutPrincipal> createState() => _LayoutPrincipalState();
}

class _LayoutPrincipalState extends State<LayoutPrincipal> {
  Timer? _syncTimer;
  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
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
        if (c[i] > m[i]) return false;
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
                child: Text('Actualización de seguridad disponible.',
                    style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        backgroundColor: Colors.indigo,
        duration: Duration(days: 1), // Persistente
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();

    final navItems = [
      (
        '/pos',
        'Ventas',
        const Icon(Icons.point_of_sale_outlined),
        const Icon(Icons.point_of_sale)
      ),
      (
        '/pedidos',
        'Pedidos',
        const Icon(Icons.list_alt_outlined),
        const Icon(Icons.list_alt)
      ),
      (
        '/inventario',
        'Inventario',
        const Icon(Icons.inventory_2_outlined),
        const Icon(Icons.inventory_2)
      ),
      (
        '/config_dashboard',
        'Gestión',
        const Icon(Icons.settings_outlined),
        const Icon(Icons.settings)
      ),
    ];

    int currentIndex = navItems.indexWhere((e) => location.startsWith(e.$1));
    if (currentIndex == -1) currentIndex = 0;

    return Scaffold(
      body: widget.child,
      floatingActionButton: null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          GoRouter.of(context).go(navItems[index].$1);
        },
        destinations: navItems
            .map((e) => NavigationDestination(
                  icon: e.$3,
                  selectedIcon: e.$4,
                  label: e.$2,
                ))
            .toList(),
      ),
    );
  }
}
