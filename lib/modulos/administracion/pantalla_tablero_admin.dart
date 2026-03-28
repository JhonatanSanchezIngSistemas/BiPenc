import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../servicios/servicio_configuracion.dart';
import '../../servicios/servicio_sesion.dart';
import '../../servicios/servicio_supabase.dart';
import '../../servicios/supabase/servicio_catalogo.dart';
import '../../servicios/supabase/servicio_usuarios.dart';
import '../../servicios/supabase/servicio_ventas.dart';
import '../../servicios/supabase/servicio_monitoreo.dart';
import '../../servicios/servicio_db_local.dart';

import 'componentes/tab_productos.dart';
import 'componentes/tab_usuarios.dart';
import 'componentes/tab_carritos.dart';

class PantallaTableroAdmin extends StatefulWidget {
  const PantallaTableroAdmin({super.key});

  @override
  State<PantallaTableroAdmin> createState() => _PantallaTableroAdminState();
}

class _PantallaTableroAdminState extends State<PantallaTableroAdmin> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final client = Supabase.instance.client;
  late final bool _isAdmin;
  Timer? _metricsDebounce;
  bool _metricsInFlight = false;
  DateTime _lastMetricsFetch = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _metricsMinInterval = Duration(seconds: 15);
  final TextEditingController _productoSearchCtrl = TextEditingController();
  final TextEditingController _usuarioSearchCtrl = TextEditingController();
  bool _liveCartsEnabled = false;

  // ── Métricas Globales Nube ──
  double _ventasNubeTotalHoy = 0;
  double _ventasNubeEfectivo = 0;
  double _ventasNubeYape = 0;
  List<Map<String, dynamic>> _ventasRecientesNube = [];
  bool _isLoadingMetricas = true;

  // ── Logs / Auditoría / Cajas ──
  List<Map<String, dynamic>> _audits = [];
  List<Map<String, dynamic>> _pedidosGlobales = [];
  List<Map<String, dynamic>> _productosGlobales = [];
  List<Map<String, dynamic>> _usuariosGlobales = [];
  List<Map<String, dynamic>> _carritosLive = [];

  StreamSubscription? _ventasSub;
  StreamSubscription? _pedidosSub;
  StreamSubscription? _productosSub;
  StreamSubscription? _usuariosSub;
  StreamSubscription? _carritosSub;

  @override
  void initState() {
    super.initState();
    _isAdmin = ServicioSesion().rol == RolesApp.admin;
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(_handleTabChange);
    
    if (_isAdmin) {
      _loadInitialData();
      _startSmartSubscription(0); // Empezar con la pestaña de Métricas
    }
  }

  void _handleTabChange() {
    if (!_tabController.indexIsChanging) {
      _startSmartSubscription(_tabController.index);
    }
  }

  void _startSmartSubscription(int index) {
    _cancelAllSubscriptions();
    
    switch (index) {
      case 0:
      case 1:
        _subscribeVentas();
        break;
      case 2:
        _subscribePedidos();
        break;
      case 3:
        _subscribeProductos();
        break;
      case 4:
        _subscribeUsuarios();
        break;
      case 5:
        _subscribeCarritos();
        break;
    }
  }

  void _cancelAllSubscriptions() {
    _ventasSub?.cancel();
    _pedidosSub?.cancel();
    _productosSub?.cancel();
    _usuariosSub?.cancel();
    _carritosSub?.cancel();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _productoSearchCtrl.dispose();
    _usuarioSearchCtrl.dispose();
    if (_isAdmin) {
      _ventasSub?.cancel();
      _pedidosSub?.cancel();
      _productosSub?.cancel();
      _usuariosSub?.cancel();
      _carritosSub?.cancel();
      _metricsDebounce?.cancel();
    }
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingMetricas = true);
    await _cargarMetricasNube();
    await _cargarLiveCartsSetting();
    if (mounted) {
      setState(() => _isLoadingMetricas = false);
    }
  }

  Future<void> _loadAll() async {
    await _cargarMetricasNube();
    await _cargarPedidosGlobales();
    await _cargarAuditoria();
    await _cargarLiveCartsSetting();
  }

  Future<void> _cargarLiveCartsSetting() async {
    try {
      final enabled = await ServicioConfiguracion.getLiveCartsEnabled();
      if (mounted) setState(() => _liveCartsEnabled = enabled);
    } catch (_) {}
  }

  void _subscribeVentas() {
    _ventasSub = ServicioVentasSupabase.streamVentas().listen((data) {
      if (!mounted) return;
      setState(() {
        _ventasRecientesNube = data;
      });
      _recalcularMontoVivos();
    });
  }

  void _subscribePedidos() {
    _pedidosSub = ServicioVentasSupabase.streamPedidos().listen((data) {
      if (!mounted) return;
      setState(() => _pedidosGlobales = data);
    });
  }

  void _subscribeProductos() {
    _productosSub = ServicioCatalogoSupabase.streamProductos().listen((data) {
      if (!mounted) return;
      setState(() => _productosGlobales = data);
    });
  }

  void _subscribeUsuarios() {
    _usuariosSub = ServicioUsuariosSupabase.streamUsuarios().listen((data) {
      if (!mounted) return;
      setState(() => _usuariosGlobales = data);
    });
  }

  void _subscribeCarritos() {
    if (!_liveCartsEnabled) {
      if (mounted) setState(() => _carritosLive = []);
      return;
    }
    _carritosSub = ServicioMonitoreoSupabase.streamCarritosEnVivo().listen((data) {
      if (!mounted) return;
      setState(() => _carritosLive = data);
    });
  }

  void _recalcularMontoVivos() {
    _cargarMetricasNube(limitFrecuencia: true);
  }

  Future<void> _cargarMetricasNube({bool limitFrecuencia = false}) async {
    if (_metricsInFlight) return;
    if (limitFrecuencia) {
      final now = DateTime.now();
      final elapsed = now.difference(_lastMetricsFetch);
      if (elapsed < _metricsMinInterval) {
        _metricsDebounce?.cancel();
        final wait = _metricsMinInterval - elapsed;
        _metricsDebounce = Timer(wait, () {
          if (mounted) _cargarMetricasNube();
        });
        return;
      }
    }
    _metricsInFlight = true;
    _lastMetricsFetch = DateTime.now();
    final now = DateTime.now();
    final inicioDia = DateTime(now.year, now.month, now.day).toIso8601String();
    
    try {
      final res = await client
          .from('ventas')
          .select('total, metodo_pago, anulado, alias_vendedor, created_at')
          .gte('created_at', inicioDia);
      
      double total = 0, efe = 0, yap = 0;
      for (final r in (res as List)) {
        if (r['anulado'] == true) continue;
        final t = (r['total'] as num?)?.toDouble() ?? 0;
        final m = (r['metodo_pago'] ?? '').toString().toLowerCase();
        
        total += t;
        if (m.contains('efect')) {
          efe += t;
        } else if (m.contains('yape') || m.contains('plin')) {
          yap += t;
        }
      }
      
      _ventasNubeTotalHoy = total;
      _ventasNubeEfectivo = efe;
      _ventasNubeYape = yap;
    } catch (e) {
      debugPrint('Error cargando metricas nube: $e');
    } finally {
      _metricsInFlight = false;
    }
  }

  Future<void> _cargarPedidosGlobales() async {
    try {
      final res = await client
          .from('order_lists')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      _pedidosGlobales = (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Error cargando pedidos globales: $e');
    }
  }

  Future<void> _cargarAuditoria() async {
    _audits = await ServicioDbLocal.obtenerAuditLogs(limit: 50);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0F1A),
        appBar: AppBar(
          title: const Text('Acceso restringido', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white70),
        ),
        body: const Center(
          child: Text(
            'Solo administradores pueden acceder a este panel.',
            style: TextStyle(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1A), 
      appBar: AppBar(
        title: const Text('Comando Súper-Admin', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amberAccent)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.amberAccent),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart), text: 'Métricas'),
            Tab(icon: Icon(Icons.receipt_long), text: 'Ventas en Vivo'),
            Tab(icon: Icon(Icons.list_alt), text: 'Todos los Pedidos'),
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Productos'),
            Tab(icon: Icon(Icons.manage_accounts), text: 'Usuarios'),
            Tab(icon: Icon(Icons.shopping_cart_outlined), text: 'Carritos'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          )
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMetricasTab(),
          _buildVentasVivasTab(),
          _buildPedidosGlobalesTab(),
          TabProductos(productos: _productosGlobales),
          TabUsuarios(
            usuarios: _usuariosGlobales,
            onUpdate: (id, field, value) async {
              await ServicioUsuariosSupabase.actualizarCampoPerfil(id, field, value);
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Actualizado: $field a $value')));
            },
            onEdit: (id, data) async {
              await ServicioUsuariosSupabase.actualizarDatosPerfil(id, data);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Usuario actualizado')));
            },
            onInvite: (email, nombre, apellido, rol) async {
              try {
                await ServicioUsuariosSupabase.invitarUsuario(
                    email: email, nombre: nombre, apellido: apellido, rol: rol);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invitación enviada')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
                }
              }
            },
            onEstado: (id, estado) async {
              try {
                await ServicioUsuariosSupabase.actualizarEstado(id, estado);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Estado actualizado a $estado')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
                }
              }
            },
          ),
          TabCarritos(
            carritos: _carritosLive,
            enabled: _liveCartsEnabled,
            onToggle: (value) async {
              await ServicioConfiguracion.setLiveCartsEnabled(value);
              if (mounted) {
                setState(() => _liveCartsEnabled = value);
                if (value) {
                  _subscribeCarritos();
                } else {
                  _carritosSub?.cancel();
                  _carritosSub = null;
                  _carritosLive = [];
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetricasTab() {
    if (_isLoadingMetricas) {
      return const Center(child: CircularProgressIndicator(color: Colors.amber));
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('INGRESOS GLOBALES DE HOY (TODAS LAS CAJAS)', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _metricCard('TOTAL', _ventasNubeTotalHoy, color: Colors.amberAccent, icon: Icons.attach_money)),
              const SizedBox(width: 12),
              Expanded(child: _metricCard('EFECTIVO', _ventasNubeEfectivo, color: Colors.greenAccent, icon: Icons.money)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _metricCard('YAPE/PLIN', _ventasNubeYape, color: Colors.purpleAccent, icon: Icons.phone_android)),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => context.push('/inventario'),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.inventory_2, color: Colors.blueAccent, size: 32),
                        SizedBox(height: 8),
                        Text('Editar Precios', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('MANTENIMIENTO DE DATOS',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          _buildCriticalAction(
            title: 'Sincronizar Catálogo con la Nube',
            subtitle: 'Sube productos locales a Supabase.',
            icon: Icons.cloud_upload_outlined,
            color: Colors.blueAccent,
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A2E),
                  title: const Text('Confirmar Sincronización', style: TextStyle(color: Colors.white)),
                  content: const Text('Esto subirá todo tu catálogo local a la nube. ¿Continuar?', style: TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SUBIR')),
                  ],
                ),
              );
              if (confirm == true) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sincronizando...')));
                try {
                  final count = await ServicioSupabase.subirCatalogoLocal();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sincronizados: $count')));
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
                  }
                }
              }
            },
          ),
          const SizedBox(height: 24),
          const Text('AUDITORÍA Y SEGURIDAD (LOCAL)', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 12),
          _card(
            child: _audits.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('No hay registros aún', style: TextStyle(color: Colors.white54)))
                : Column(
                    children: _audits.map((e) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.security, color: Colors.white24, size: 18),
                          title: Text(e['accion'] ?? '', style: const TextStyle(color: Colors.white)),
                          subtitle: Text('${e['usuario'] ?? '—'} • ${e['detalle'] ?? ''}', style: const TextStyle(color: Colors.white54)),
                          trailing: Text(
                            DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(e['created_at'] as int)),
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        )).toList(),
                  ),
          )
        ],
      ),
    );
  }

  Widget _buildVentasVivasTab() {
    if (_ventasRecientesNube.isEmpty) {
      return const Center(child: Text('Esperando ventas en vivo...', style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _ventasRecientesNube.length,
      itemBuilder: (context, i) {
        final v = _ventasRecientesNube[i];
        final bool anulado = v['anulado'] == true;
        final double total = (v['total'] as num?)?.toDouble() ?? 0.0;
        final alias = v['alias_vendedor'] ?? 'Desconocido';
        final metod = v['metodo_pago'] ?? 'N/A';
        final fecha = DateTime.tryParse(v['created_at'] ?? '')?.toLocal();

        return Card(
          color: Colors.grey.shade900,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: anulado ? Colors.red.withValues(alpha: 0.3) : Colors.white10),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: anulado ? Colors.red.withValues(alpha: 0.1) : Colors.amber.withValues(alpha: 0.1),
              child: Icon(anulado ? Icons.cancel : Icons.point_of_sale, color: anulado ? Colors.redAccent : Colors.amberAccent, size: 18),
            ),
            title: Text('Ticket ${v['correlativo'] ?? v['id']} • $alias',
                style: TextStyle(color: anulado ? Colors.white54 : Colors.white, fontWeight: FontWeight.bold, decoration: anulado ? TextDecoration.lineThrough : null)),
            subtitle: Text('$metod • ${fecha != null ? DateFormat('hh:mm a').format(fecha) : ''}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
            trailing: Text('S/. ${total.toStringAsFixed(2)}', style: TextStyle(color: anulado ? Colors.redAccent : Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            onTap: () => _mostrarDetalleVenta(v),
          ),
        );
      },
    );
  }

  Future<void> _mostrarDetalleVenta(Map<String, dynamic> v) async {
    final itemsInline = v['items'];
    final cliente = (v['nombre_cliente'] ?? '').toString();
    final doc = (v['dni_ruc'] ?? v['documento_cliente'] ?? '').toString();
    final correlativo = (v['correlativo'] ?? v['id']).toString();

    List<Map<String, dynamic>> items = [];
    if (itemsInline is List) {
      items = itemsInline.cast<Map<String, dynamic>>();
    } else {
      final ventaId = v['id']?.toString();
      if (ventaId != null) {
        items = await ServicioVentasSupabase.fetchVentaItems(ventaId);
      }
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('Detalle de venta $correlativo',
            style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 420,
          child: items.isEmpty
              ? const Text('Sin ítems disponibles',
                  style: TextStyle(color: Colors.white54))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cliente.isNotEmpty || doc.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Cliente: ${cliente.isNotEmpty ? cliente : '—'} • Doc: ${doc.isNotEmpty ? doc : '—'}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                        itemBuilder: (context, i) {
                          final it = items[i];
                          final nombre = (it['nombre'] ??
                                  it['producto_nombre'] ??
                                  it['producto_id'] ??
                                  'Producto')
                              .toString();
                          final cantidad = (it['cantidad'] as num?)?.toDouble() ?? 0;
                          final precio = (it['precio'] ?? it['precio_unitario'] as num?)?.toDouble() ?? 0;
                          final pres = (it['presentacion_nombre'] ?? it['presentacion_id'] ?? '').toString();
                          final subtotal = (it['subtotal'] as num?)?.toDouble() ?? (cantidad * precio);
                          return ListTile(
                            dense: true,
                            title: Text(nombre, style: const TextStyle(color: Colors.white)),
                            subtitle: Text(
                              '${pres.isNotEmpty ? pres : '—'} • Cant: ${cantidad.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                            trailing: Text('S/. ${subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _buildPedidosGlobalesTab() {
    if (_pedidosGlobales.isEmpty) {
      return const Center(child: Text('No hay listas ni pedidos en la nube', style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _pedidosGlobales.length,
      itemBuilder: (context, i) {
        final p = _pedidosGlobales[i];
        final cliente = p['cliente_nombre'] ?? 'Sin nombre';
        final estado = p['estado'] ?? 'PENDIENTE';
        final vendedor = p['alias_vendedor'] ?? 'N/A';
        final created = DateTime.tryParse(p['created_at'] ?? '')?.toLocal();

        Color colorEstado = Colors.amber;
        if (estado == 'COMPLETADO') colorEstado = Colors.green;
        if (estado == 'CANCELADO') colorEstado = Colors.red;

        return Card(
          color: Colors.grey.shade900,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white10)),
          child: ListTile(
            title: Text(cliente, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            subtitle: Text('Tomado por: $vendedor • ${created != null ? DateFormat('dd/MM hh:mm a').format(created) : ''}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorEstado.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorEstado.withValues(alpha: 0.3)),
              ),
              child: Text(estado, style: TextStyle(color: colorEstado, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            onTap: () {
               showDialog(context: context, builder: (c) => AlertDialog(
                 backgroundColor: Colors.grey.shade900,
                 title: const Text('Detalle Rápido Admin', style: TextStyle(color: Colors.white)),
                 content: Text('Vendedor: $vendedor\nCliente: $cliente\nEstado: $estado\nTienes permiso para editar esto desde la pestaña Listas Escolares (Todas).', style: const TextStyle(color: Colors.white70)),
               ));
            },
          ),
        );
      },
    );
  }

  Widget _buildCriticalAction({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      tileColor: color.withOpacity(0.05),
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }

  Widget _metricCard(String title, double value, {required Color color, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(color: color.withValues(alpha: 0.8), fontWeight: FontWeight.w600, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),
          Text('S/. ${value.toStringAsFixed(2)}', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 22)),
        ],
      ),
    );
  }

}
