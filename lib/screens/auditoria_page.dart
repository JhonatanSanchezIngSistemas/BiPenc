import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/producto.dart';
import '../services/supabase_service.dart';
import '../services/precio_aprobacion_service.dart';
import '../services/caja_service.dart';
import '../services/printing_service.dart';
import '../utils/ticket_builder.dart';
import '../utils/precio_engine.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuditoriaPage extends StatefulWidget {
  const AuditoriaPage({super.key});

  @override
  State<AuditoriaPage> createState() => _AuditoriaPageState();
}

class _AuditoriaPageState extends State<AuditoriaPage> {
  List<Producto> _pendientes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarPendientes();
  }

  Future<void> _cargarPendientes() async {
    setState(() => _isLoading = true);
    final results = await SupabaseService.obtenerProductosParaAuditoria();
    setState(() {
      _pendientes = results;
      _isLoading = false;
    });
  }

  Future<void> _aprobar(Producto p) async {
    final aprobacionService = PrecioAprobacionService(Supabase.instance.client);
    final ok = await aprobacionService.aprobarPrecioPropuesto(p.id);
    
    if (ok && mounted) {
      _cargarPendientes();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Producto aprobado con éxito'), backgroundColor: Colors.teal),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          title: const Text('Panel de Auditoría y Caja'),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.tealAccent,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.approval), text: 'Aprobaciones'),
              Tab(icon: Icon(Icons.receipt_long), text: 'Cierre de Caja'),
            ],
            indicatorColor: Colors.tealAccent,
            labelColor: Colors.tealAccent,
            unselectedLabelColor: Colors.grey,
          ),
        ),
        body: TabBarView(
          children: [
            _buildAprobacionesTab(),
            _buildCajaTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildAprobacionesTab() {
    return _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
          : _pendientes.isEmpty
              ? const Center(child: Text('No hay precios pendientes de aprobación', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _pendientes.length,
                  itemBuilder: (context, index) {
                    final p = _pendientes[index];
                    return Card(
                      color: const Color(0xFF1A1A1A),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(p.nombre, style: const TextStyle(color: Colors.white)),
                        subtitle: Text('Propuesto: S/ ${p.precioPropuesto?.toStringAsFixed(2)}', style: const TextStyle(color: Colors.tealAccent)),
                        trailing: IconButton(
                          icon: const Icon(Icons.check_circle, color: Colors.tealAccent),
                          onPressed: () => _aprobar(p),
                        ),
                      ),
                    );
                  },
                );
  }

  Widget _buildCajaTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: CajaService.generarResumenCaja(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Colors.tealAccent));
        }

        final data = snapshot.data!;
        final total = data['totalVentas'] as double;
        final ahorro = data['ahorroRedondeo'] as double;
        final conteo = data['conteoVentas'] as int;
        final vendedores = data['ventasPorVendedor'] as Map<String, double>;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildResumenCard(total, ahorro, conteo),
              const SizedBox(height: 24),
              const Text('Ventas por Vendedor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              ...vendedores.entries.map((e) => _buildVendedorRow(e.key, e.value)),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () => _imprimirCorte(data),
                  icon: const Icon(Icons.print),
                  label: const Text('IMPRIMIR CORTE X (PARCIAL)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {}, // Implementar borrado de caché local si se desea
                  child: const Text('REALIZAR CIERRE Z (FINAL)', style: TextStyle(color: Colors.redAccent)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResumenCard(double total, double ahorro, int conteo) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.tealAccent.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          const Text('TOTAL EN CAJA (REDONDEADO)', style: TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Text('S/ ${total.toStringAsFixed(2)}', style: const TextStyle(color: Colors.tealAccent, fontSize: 32, fontWeight: FontWeight.bold)),
          const Divider(height: 32, color: Colors.white10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem('Ventas', conteo.toString()),
              _buildStatItem('Extra Round', 'S/ ${ahorro.toStringAsFixed(2)}', color: Colors.orangeAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {Color color = Colors.white}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildVendedorRow(String alias, double monto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(alias, style: const TextStyle(color: Colors.grey)),
          Text('S/ ${monto.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _imprimirCorte(Map<String, dynamic> data) async {
    final ticketText = TicketBuilder.buildCierre(
      ancho: 48,
      tipo: 'X',
      ventas: data['ventasPorVendedor'],
      total: data['totalVentas'],
      ahorro: data['ahorroRedondeo'],
      fecha: DateTime.now(),
    );

    final error = await PrintingService.instance.printRawText(ticketText);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error impresora: $error'), backgroundColor: Colors.redAccent),
      );
    }
  }
}
