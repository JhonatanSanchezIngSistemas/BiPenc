import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/supabase_service.dart';

class MainLayout extends StatefulWidget {
  final Widget child;
  const MainLayout({super.key, required this.child});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    try {
      final minVersion = await SupabaseService.obtenerVersionMinima();
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
            Expanded(child: Text('Actualización de seguridad disponible.', style: TextStyle(fontWeight: FontWeight.bold))),
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
    
    // Determinar el índice seleccionado basado en la ruta actual
    int currentIndex = 0;
    if (location.startsWith('/pedidos')) {
      currentIndex = 1;
    } else if (location.startsWith('/inventario')) {
      currentIndex = 2;
    } else if (location.startsWith('/config_dashboard') ||
        location.startsWith('/settings') ||
        location.startsWith('/boletas') ||
        location.startsWith('/cierre_caja')) {
      currentIndex = 3;
    } else if (location.startsWith('/pos')) {
      currentIndex = 0;
    } else if (location == '/') {
      currentIndex = 0;
    }

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          const routes = ['/pos', '/pedidos', '/inventario', '/config_dashboard'];
          GoRouter.of(context).go(routes[index]);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Ventas',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Pedidos',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventario',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Gestión',
          ),
        ],
      ),
    );
  }
}
