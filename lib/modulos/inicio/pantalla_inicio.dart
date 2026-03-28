import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../servicios/servicio_db_local.dart';
import '../../servicios/cola_impresion.dart';

class PantallaInicio extends StatefulWidget {
  const PantallaInicio({super.key});

  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  late Future<_EstadisticasInicio> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
  }

  Future<_EstadisticasInicio> _loadStats() async {
    final ventas = await ServicioDbLocal.getUltimasVentas(limit: 40);
    final pendientesSync = await ServicioDbLocal.obtenerVentasPendientes();
    final printStats = await ColaImpresion.obtenerEstadisticas();
    final totalDia = ventas.fold<double>(
      0,
      (s, v) => s + ((v['total'] ?? 0) as num).toDouble(),
    );
    return _EstadisticasInicio(
      ventasHoy: ventas.length,
      totalHoy: totalDia,
      pendientesSync: pendientesSync.length,
      pendientesPrint: (printStats['pendientes'] ?? 0) as int,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D111B),
              Color(0xFF132033),
              Color(0xFF0F0F1A),
            ],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _statsFuture = _loadStats();
              });
              await _statsFuture;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              children: [
                const Text(
                  'Panel BiPenc',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Control rápido de ventas, pedidos y operación diaria',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FutureBuilder<_EstadisticasInicio>(
                  future: _statsFuture,
                  builder: (context, snap) {
                    final s = snap.data ??
                        const _EstadisticasInicio(
                          ventasHoy: 0,
                          totalHoy: 0,
                          pendientesSync: 0,
                          pendientesPrint: 0,
                        );
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _TarjetaMetrica(
                                title: 'Ventas de hoy',
                                value: '${s.ventasHoy}',
                                color: Colors.tealAccent,
                                icon: Icons.receipt_long,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _TarjetaMetrica(
                                title: 'Total hoy',
                                value: 'S/.${s.totalHoy.toStringAsFixed(2)}',
                                color: Colors.greenAccent,
                                icon: Icons.attach_money,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _TarjetaMetrica(
                                title: 'Pendiente sync',
                                value: '${s.pendientesSync}',
                                color: s.pendientesSync > 0
                                    ? Colors.orangeAccent
                                    : Colors.blueAccent,
                                icon: Icons.sync_problem,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _TarjetaMetrica(
                                title: 'Cola impresión',
                                value: '${s.pendientesPrint}',
                                color: s.pendientesPrint > 0
                                    ? Colors.amber
                                    : Colors.purpleAccent,
                                icon: Icons.print,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                const _TituloSeccion('Acciones Rápidas'),
                const SizedBox(height: 10),
                _FichaAccion(
                  title: 'Nueva Venta',
                  subtitle: 'Abrir POS y cobrar',
                  icon: Icons.point_of_sale,
                  color: Colors.teal,
                  onTap: () => context.go('/pos'),
                ),
                _FichaAccion(
                  title: 'Listas Escolares',
                  subtitle: 'Llegadas, pagos y prioridad',
                  icon: Icons.list_alt,
                  color: Colors.orangeAccent,
                  onTap: () => context.go('/pedidos'),
                ),
                _FichaAccion(
                  title: 'Inventario',
                  subtitle: 'Crear y editar productos',
                  icon: Icons.add_circle_outline,
                  color: Colors.cyanAccent,
                  onTap: () => context.go('/inventario'),
                ),
                _FichaAccion(
                  title: 'Boletas y Reportes',
                  subtitle: 'Reimpresión, anulación, caja',
                  icon: Icons.analytics_outlined,
                  color: Colors.greenAccent,
                  onTap: () => context.go('/config_dashboard'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  final String text;
  const _TituloSeccion(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _TarjetaMetrica extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _TarjetaMetrica({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF151C2C),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FichaAccion extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _FichaAccion({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF141A29),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white60)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white30),
      ),
    );
  }
}

class _EstadisticasInicio {
  final int ventasHoy;
  final double totalHoy;
  final int pendientesSync;
  final int pendientesPrint;

  const _EstadisticasInicio({
    required this.ventasHoy,
    required this.totalHoy,
    required this.pendientesSync,
    required this.pendientesPrint,
  });
}
