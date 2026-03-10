import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../../services/session_manager.dart';
import '../../services/session_service.dart';
import '../../services/config_service.dart';
import '../../services/print_service.dart';
import '../../data/models/venta.dart';
import '../../services/local_db_service.dart';
import '../pos/pos_provider.dart';
import '../../services/despacho_service.dart';

class ConfigDashboardScreen extends StatelessWidget {
  const ConfigDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E1422), Color(0xFF101827), Color(0xFF0F0F1A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── HEADER SENSORIAL (Sin AppBar) ────────────────────────────────
              _buildMinimalHeader(),
              
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  children: [
                  _buildStatusRow(),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Panel de Control'),
                  const SizedBox(height: 12),
                  _buildActionCard(
                    context,
                    title: 'Gestión de Inventario',
                    subtitle: 'Productos, precios y presentaciones',
                    icon: Icons.inventory_2_outlined,
                    color: Colors.teal,
                    onTap: () => context.push('/inventario'),
                  ),
                  const SizedBox(height: 20),
                  _buildActionCard(
                    context,
                    title: 'Impresora Térmica',
                    subtitle: 'Configurar BT-210 y cabeceras',
                    icon: Icons.print_outlined,
                    color: Colors.blueAccent,
                    onTap: () => context.push('/settings/printer'),
                  ),
                  const SizedBox(height: 20),
                  _buildActionCard(
                    context,
                    title: 'Boletas y Reimpresión',
                    subtitle: 'Buscar por número, reimprimir y exportar PDF',
                    icon: Icons.receipt_long_outlined,
                    color: Colors.orangeAccent,
                    onTap: () => context.push('/boletas'),
                  ),
                  const SizedBox(height: 20),
                  _buildActionCard(
                    context,
                    title: 'Listas Escolares',
                    subtitle: 'Llegadas, fotos, pagos y prioridad de entrega',
                    icon: Icons.list_alt_outlined,
                    color: Colors.amberAccent,
                    onTap: () => context.push('/pedidos'),
                  ),
                  const SizedBox(height: 20),
                  _buildActionCard(
                    context,
                    title: 'Caja por Turno',
                    subtitle: 'Apertura, cierre, diferencias y reporte',
                    icon: Icons.point_of_sale_outlined,
                    color: Colors.greenAccent,
                    onTap: () => context.push('/cierre_caja'),
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Pedidos de Hoy'),
                  const SizedBox(height: 12),
                  _buildPedidosRecientes(context),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Perfil y Sesión'),
                  _buildProfileCard(context),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () {
                      context.read<SessionManager>().cerrarSesion();
                      context.go('/login');
                    },
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    label: const Text('CERRAR SESIÓN', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalHeader() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.teal.withValues(alpha: 0.1),
            child: const Icon(Icons.shield_outlined, color: Colors.tealAccent),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Consola Administrativa', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              Text('Panel de operación del negocio', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    return StreamBuilder<bool>(
      stream: PrintService().connectionStream,
      initialData: PrintService().estaConectado,
      builder: (context, snapshot) {
        final isConnected = snapshot.data ?? false;
        return Row(
          children: [
            _statusLabel('DB Online', true, Icons.cloud_done_outlined),
            const SizedBox(width: 12),
            _statusLabel(
              'Impresora térmica',
              isConnected,
              isConnected ? Icons.print : Icons.print_disabled,
            ),
          ],
        );
      }
    );
  }

  Widget _statusLabel(String label, bool active, IconData icon) {
    final color = active ? Colors.greenAccent : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildPedidosRecientes(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: LocalDbService.getUltimasVentas(limit: 5),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Card(
            color: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Sin ventas hoy', style: TextStyle(color: Colors.white24, fontSize: 12)),
            ),
          );
        }
        return Column(
          children: snapshot.data!.map((v) {
            final double total = (v['total'] ?? 0.0).toDouble();
            final bool despachado = (v['despachado'] ?? 0) == 1;
            
            return Card(
              color: Colors.grey.shade900,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: despachado ? Colors.teal.withValues(alpha: 0.3) : Colors.amber.withValues(alpha: 0.3)),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(
                  despachado ? Icons.check_circle_outline : Icons.pending_actions,
                  color: despachado ? Colors.tealAccent : Colors.amber,
                ),
                title: Text('Ticket ${v['correlativo'] ?? v['id']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('Total: S/. ${total.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                trailing: despachado 
                  ? const Icon(Icons.print_outlined, color: Colors.white24, size: 18)
                  : const Text('PICKING', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                onTap: () async {
                  // Mapeo detallado para el Picking
                  final itemsRaw = v['items_json'] != null ? jsonDecode(v['items_json'] as String) : [];
                  final ivaRate = await ConfigService.obtenerIGVActual();
                  final operacionBase = total / (1 + ivaRate);
                  final igvValue = total - operacionBase;

                  final venta = Venta(
                    id: (v['correlativo'] ?? v['id'].toString()),
                    fecha: DateTime.parse(v['creado_at']),
                    tipoComprobante: (v['correlativo']?.toString().contains('F') ?? false) 
                        ? TipoComprobante.factura 
                        : TipoComprobante.boleta,
                    documentoCliente: '00000000',
                    operacionGravada: operacionBase,
                    igv: igvValue,
                    total: total,
                    metodoPago: MetodoPago.values.firstWhere(
                      (e) => e.name.toUpperCase() == (v['metodo_pago']?.toString().toUpperCase() ?? 'EFECTIVO'),
                      orElse: () => MetodoPago.efectivo,
                    ),
                    montoRecibido: total,
                    vuelto: 0,
                    items: (itemsRaw as List).map((i) => ItemCarrito.fromJson(i as Map<String, dynamic>)).cast<ItemCarrito>().toList(),
                    dbId: v['id'] as int,
                    despachado: despachado,
                  );
                  
                  if (context.mounted) {
                    await DespachoService().abrirPicking(context, venta);
                  }
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Card(
      color: Colors.grey.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white10)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.white24),
        onTap: onTap,
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context) {
    return FutureBuilder(
      future: SessionService().obtenerPerfil(forceRefresh: true),
      builder: (context, snapshot) {
        final perfil = snapshot.data;
        final nombre = perfil?.nombreCompleto.trim().isNotEmpty == true
            ? perfil!.nombreCompleto
            : 'Usuario';
        final alias = perfil?.alias.trim().isNotEmpty == true ? perfil!.alias : 'SIN ALIAS';
        final rol = perfil?.rol ?? 'VENTAS';
        return Card(
          color: Colors.grey.shade900,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white10)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.teal.withValues(alpha: 0.2),
              child: const Icon(Icons.person, color: Colors.white),
            ),
            title: Text(nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Text('Alias: $alias  •  Rol: $rol', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white24),
            onTap: () => context.push('/settings/profile'),
          ),
        );
      },
    );
  }
}
