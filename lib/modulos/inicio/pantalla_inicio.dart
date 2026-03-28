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
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                const SizedBox(height: 8),
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
                const SizedBox(height: 10),
                const _TituloSeccion('Acciones Rápidas'),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.4,
                  children: [
                    _FichaAccionGrid(
                      title: 'Venta POS',
                      icon: Icons.point_of_sale,
                      color: Colors.teal,
                      onTap: () => context.go('/pos'),
                    ),
                    _FichaAccionGrid(
                      title: 'Pedidos',
                      icon: Icons.list_alt,
                      color: Colors.orangeAccent,
                      onTap: () => context.go('/pedidos'),
                    ),
                    _FichaAccionGrid(
                      title: 'Inventario',
                      icon: Icons.inventory_2_outlined,
                      color: Colors.cyanAccent,
                      onTap: () => context.go('/inventario'),
                    ),
                    _FichaAccionGrid(
                      title: 'Reportes',
                      icon: Icons.analytics_outlined,
                      color: Colors.greenAccent,
                      onTap: () => context.go('/boletas'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
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

class _FichaAccionGrid extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _FichaAccionGrid({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF141A29),
          border: Border.all(color: Colors.white10),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF141A29),
              color.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
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
