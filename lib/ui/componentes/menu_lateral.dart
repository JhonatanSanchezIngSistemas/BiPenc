import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../servicios/servicio_sesion.dart';
import '../../datos/modelos/producto.dart';
import '../../base/tema.dart';

class MenuLateral extends StatelessWidget {
  const MenuLateral({super.key});

  @override
  Widget build(BuildContext context) {
    final sesion = Provider.of<ServicioSesion>(context);
    final perfil = sesion.perfil;
    final isAdmin = sesion.rol == RolesApp.admin;

    return Drawer(
      backgroundColor: TemaApp.backgroundDark,
      child: Column(
        children: [
          _UserHeader(perfil: perfil),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _DrawerItem(
                  icon: Icons.home_outlined,
                  label: 'Inicio',
                  onTap: () => context.go('/'),
                  isActive: GoRouterState.of(context).uri.toString() == '/',
                ),
                _DrawerItem(
                  icon: Icons.point_of_sale_outlined,
                  label: 'Punto de Venta',
                  onTap: () => context.go('/pos'),
                  isActive: GoRouterState.of(context).uri.toString().startsWith('/pos'),
                ),
                _DrawerItem(
                  icon: Icons.list_alt_outlined,
                  label: 'Pedidos y Listas',
                  onTap: () => context.go('/pedidos'),
                  isActive: GoRouterState.of(context).uri.toString().startsWith('/pedidos'),
                ),
                const Divider(color: Colors.white10, indent: 20, endIndent: 20),
                _DrawerItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'Inventario',
                  onTap: () => context.go('/inventario'),
                  isActive: GoRouterState.of(context).uri.toString().startsWith('/inventario'),
                ),
                _DrawerItem(
                  icon: Icons.receipt_long_outlined,
                  label: 'Boletas y Reportes',
                  onTap: () => context.go('/boletas'),
                  isActive: GoRouterState.of(context).uri.toString().startsWith('/boletas'),
                ),
                if (isAdmin) ...[
                  const Divider(color: Colors.white10, indent: 20, endIndent: 20),
                  const Padding(
                    padding: EdgeInsets.only(left: 20, top: 10, bottom: 5),
                    child: Text(
                      'ADMINISTRACIÓN',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Tablero de Control',
                    onTap: () => context.go('/admin/dashboard'),
                    isActive: GoRouterState.of(context).uri.toString().startsWith('/admin/dashboard'),
                  ),
                  _DrawerItem(
                    icon: Icons.settings_outlined,
                    label: 'Configuración',
                    onTap: () => context.go('/config_dashboard'),
                    isActive: GoRouterState.of(context).uri.toString().startsWith('/config_dashboard'),
                  ),
                  _DrawerItem(
                    icon: Icons.business_outlined,
                    label: 'Configuración de Empresa',
                    onTap: () => context.go('/config/negocio'),
                    isActive: GoRouterState.of(context).uri.toString().startsWith('/config/negocio'),
                  ),
                ],
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          _DrawerItem(
            icon: Icons.logout_rounded,
            label: 'Cerrar Sesión',
            color: Colors.redAccent,
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Cerrar Sesión'),
                  content: const Text('¿Estás seguro de que deseas salir?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salir', style: TextStyle(color: Colors.redAccent))),
                  ],
                ),
              );
              if (confirm == true) {
                await sesion.logoutCompleto();
                if (context.mounted) context.go('/login');
              }
            },
          ),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'BiPenc Diamond Edition v1.0.1+2',
              style: TextStyle(color: Colors.white24, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserHeader extends StatelessWidget {
  final Perfil? perfil;
  const _UserHeader({required this.perfil});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
      decoration: const BoxDecoration(
        color: Color(0xFF141A29),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: TemaApp.primaryTeal.withValues(alpha: 0.1),
            child: Text(
              perfil?.alias.substring(0, 1).toUpperCase() ?? 'U',
              style: const TextStyle(color: TemaApp.primaryTeal, fontWeight: FontWeight.bold, fontSize: 24),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            perfil?.alias ?? 'Usuario',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          Text(
            perfil?.rol ?? 'Ventas',
            style: TextStyle(color: TemaApp.primaryTeal.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final Color? color;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? TemaApp.primaryTeal;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, color: isActive ? activeColor : Colors.white60, size: 22),
        title: Text(
          label,
          style: TextStyle(
            color: isActive ? activeColor : Colors.white70,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        tileColor: isActive ? activeColor.withValues(alpha: 0.08) : Colors.transparent,
      ),
    );
  }
}
