import 'package:flutter/material.dart';
import 'package:bipenc/datos/modelos/pedido.dart';
import 'package:bipenc/servicios/servicio_pedidos.dart';
import 'componentes/filtros_pedidos.dart';
import 'componentes/tarjeta_pedido.dart';
import 'componentes/modal_crear_pedido.dart';
import 'componentes/modal_detalle_pedido.dart';

class PantallaListaPedidos extends StatefulWidget {
  const PantallaListaPedidos({super.key});

  @override
  State<PantallaListaPedidos> createState() => _PantallaListaPedidosState();
}

class _PantallaListaPedidosState extends State<PantallaListaPedidos> {
  final _service = ServicioPedidos();
  late Future<List<Pedido>> _futureOrders;
  FiltroPedidos _filter = FiltroPedidos.todos;

  @override
  void initState() {
    super.initState();
    _futureOrders = _service.getPedidos();
  }

  Future<void> _refrescar() async {
    setState(() {
      _futureOrders = _service.getPedidos();
    });
  }

  List<Pedido> _ordenarYFiltrar(List<Pedido> source) {
    final filtered = source.where((o) {
      switch (_filter) {
        case FiltroPedidos.porCobrar:
          return !o.estaCancelado;
        case FiltroPedidos.canceladas:
          return o.estaCancelado;
        case FiltroPedidos.todos:
          return true;
      }
    }).toList();

    filtered.sort((a, b) {
      final byPriority = a.prioridadAtencion.compareTo(b.prioridadAtencion);
      if (byPriority != 0) return byPriority;
      return a.llegadaAt.compareTo(b.llegadaAt);
    });
    return filtered;
  }

  void _mostrarCrearPedido() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => ModalCrearPedido(
        onCreated: () {
          _refrescar();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _mostrarDetallesPedido(Pedido orden) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => ModalDetallesPedido(
        orden: orden,
        onActualizar: () {
          _refrescar();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Listas de Pedidos',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.grey.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<List<Pedido>>(
        future: _futureOrders,
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.teal),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error al cargar pedidos: ${snapshot.error}',
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _refrescar,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          final ordenes = _ordenarYFiltrar(snapshot.data ?? []);
          final totalPendiente =
              ordenes.fold<double>(0, (s, o) => s + o.saldoPendiente);
          final canceladas = ordenes.where((o) => o.estaCancelado).length;

          if (ordenes.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refrescar,
              backgroundColor: Colors.grey.shade900,
              color: Colors.teal,
              child: CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inbox_outlined,
                              size: 80, color: Colors.white30),
                          const SizedBox(height: 24),
                          const Text(
                            'No hay listas de pedidos',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 18),
                          ),
                          const SizedBox(height: 32),
                          FilledButton.icon(
                            onPressed: _mostrarCrearPedido,
                            icon: const Icon(Icons.add, size: 24),
                            label: const Text('Crear Primer Pedido'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refrescar,
            backgroundColor: Colors.grey.shade900,
            color: Colors.teal,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                EncabezadoResumenPedidos(
                  total: ordenes.length,
                  canceladas: canceladas,
                  pendiente: totalPendiente,
                  current: _filter,
                  onFilterChange: (f) => setState(() => _filter = f),
                ),
                const SizedBox(height: 8),
                ...ordenes.map((o) => TarjetaPedido(
                      orden: o,
                      onTap: () => _mostrarDetallesPedido(o),
                    )),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _mostrarCrearPedido,
        backgroundColor: Colors.teal,
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}
