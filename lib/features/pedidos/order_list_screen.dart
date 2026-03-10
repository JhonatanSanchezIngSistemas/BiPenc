import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bipenc/data/models/order_list.dart';
import 'package:bipenc/services/order_list_service.dart';
import 'package:bipenc/utils/app_logger.dart';

enum _OrderFilter { todos, porCobrar, canceladas }

class OrderListScreen extends StatefulWidget {
  const OrderListScreen({super.key});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  final _service = OrderListService();
  late Future<List<OrderList>> _futureOrders;
  _OrderFilter _filter = _OrderFilter.todos;

  @override
  void initState() {
    super.initState();
    _futureOrders = _service.getOrderLists();
  }

  Future<void> _refrescar() async {
    setState(() {
      _futureOrders = _service.getOrderLists();
    });
  }

  List<OrderList> _ordenarYFiltrar(List<OrderList> source) {
    final filtered = source.where((o) {
      switch (_filter) {
        case _OrderFilter.porCobrar:
          return !o.estaCancelado;
        case _OrderFilter.canceladas:
          return o.estaCancelado;
        case _OrderFilter.todos:
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
      builder: (ctx) => _CrearPedidoModal(
        onCreated: () {
          _refrescar();
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _mostrarDetallesPedido(OrderList orden) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _DetallesPedidoModal(
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
      body: FutureBuilder<List<OrderList>>(
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
                _ResumenPedidosHeader(
                  total: ordenes.length,
                  canceladas: canceladas,
                  pendiente: totalPendiente,
                  current: _filter,
                  onFilterChange: (f) => setState(() => _filter = f),
                ),
                const SizedBox(height: 8),
                ...ordenes.map((o) => _OrdenCard(
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

// ── Card de Orden ──────────────────────────────────────────────────────────

class _ResumenPedidosHeader extends StatelessWidget {
  final int total;
  final int canceladas;
  final double pendiente;
  final _OrderFilter current;
  final ValueChanged<_OrderFilter> onFilterChange;

  const _ResumenPedidosHeader({
    required this.total,
    required this.canceladas,
    required this.pendiente,
    required this.current,
    required this.onFilterChange,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                  child: _MetricChip(
                      label: 'Listas',
                      value: '$total',
                      color: Colors.tealAccent)),
              const SizedBox(width: 8),
              Expanded(
                  child: _MetricChip(
                      label: 'Canceladas',
                      value: '$canceladas',
                      color: Colors.greenAccent)),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricChip(
                  label: 'Por Cobrar',
                  value: 'S/.${pendiente.toStringAsFixed(2)}',
                  color: Colors.orangeAccent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _FilterChip(
              text: 'Todas',
              active: current == _OrderFilter.todos,
              onTap: () => onFilterChange(_OrderFilter.todos),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              text: 'Por Cobrar',
              active: current == _OrderFilter.porCobrar,
              onTap: () => onFilterChange(_OrderFilter.porCobrar),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              text: 'Canceladas',
              active: current == _OrderFilter.canceladas,
              onTap: () => onFilterChange(_OrderFilter.canceladas),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.text, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? Colors.teal : Colors.grey.shade900,
            borderRadius: BorderRadius.circular(22),
            border:
                Border.all(color: active ? Colors.tealAccent : Colors.white12),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.black : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrdenCard extends StatelessWidget {
  final OrderList orden;
  final VoidCallback onTap;

  const _OrdenCard({
    required this.orden,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fechaFormato = DateFormat('dd/MM/yyyy HH:mm').format(orden.llegadaAt);
    final recojoFormato =
        DateFormat('dd/MM/yyyy HH:mm').format(orden.fechaRecojo);
    final estadoColor = orden.estaCancelado ? Colors.green : Colors.orange;
    final estadoLabel = orden.estaCancelado
        ? 'CANCELADO'
        : 'DEBE S/.${orden.saldoPendiente.toStringAsFixed(2)}';

    return Card(
      color: Colors.grey.shade900,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cliente + Estado
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          orden.clienteNombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text('ID: ${orden.id}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (orden.telefonoContacto != null &&
                            orden.telefonoContacto!.isNotEmpty)
                          Text('Tel: ${orden.telefonoContacto}',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                        if (orden.responsable != null &&
                            orden.responsable!.isNotEmpty)
                          Text('Resp: ${orden.responsable}',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: estadoColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      estadoLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Monto + Fecha
              Row(
                children: [
                  const Icon(Icons.attach_money,
                      size: 18, color: Colors.tealAccent),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                    'Pagado: S/.${orden.montoAdelantado.toStringAsFixed(2)} / '
                    'Total: S/.${orden.totalLista.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  )),
                  const Icon(Icons.calendar_today,
                      size: 18, color: Colors.tealAccent),
                  const SizedBox(width: 8),
                  Text(
                    'Llegó: $fechaFormato',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Recojo: $recojoFormato',
                  style:
                      const TextStyle(color: Colors.tealAccent, fontSize: 12)),

              // Fotos
              if (orden.fotosUrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.image, size: 16, color: Colors.tealAccent),
                    const SizedBox(width: 8),
                    Text(
                      '${orden.fotosUrls.length} foto${orden.fotosUrls.length > 1 ? 's' : ''}',
                      style: const TextStyle(
                          color: Colors.tealAccent, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Modal Crear Pedido ─────────────────────────────────────────────────────

class _CrearPedidoModal extends StatefulWidget {
  final VoidCallback onCreated;

  const _CrearPedidoModal({required this.onCreated});

  @override
  State<_CrearPedidoModal> createState() => _CrearPedidoModalState();
}

class _CrearPedidoModalState extends State<_CrearPedidoModal> {
  final _service = OrderListService();
  final _clienteCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final _pagadoCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();
  late DateTime _fechaRecojo = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _horaRecojo = TimeOfDay.now();
  List<String> _responsablesDisponibles = const [];
  final Set<String> _responsablesSeleccionados = <String>{};
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _cargarResponsables();
  }

  Future<void> _cargarResponsables() async {
    final users = await _service.getResponsablesDisponibles();
    if (!mounted) return;
    setState(() => _responsablesDisponibles = users);
  }

  @override
  void dispose() {
    _clienteCtrl.dispose();
    _telefonoCtrl.dispose();
    _totalCtrl.dispose();
    _pagadoCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  Future<void> _crearPedido() async {
    if (_clienteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ingresa nombre del cliente'),
            backgroundColor: Colors.red),
      );
      return;
    }

    final total = double.tryParse(_totalCtrl.text.replaceAll(',', '.')) ?? 0;
    final pagado = double.tryParse(_pagadoCtrl.text.replaceAll(',', '.')) ?? 0;
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Ingresa total válido'), backgroundColor: Colors.red),
      );
      return;
    }
    if (pagado < 0 || pagado > total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('El pagado debe estar entre 0 y el total'),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final fechaHoraRecojo = DateTime(
        _fechaRecojo.year,
        _fechaRecojo.month,
        _fechaRecojo.day,
        _horaRecojo.hour,
        _horaRecojo.minute,
      );
      await _service.createOrderList(
        clienteNombre: _clienteCtrl.text.trim(),
        montoAdelantado: pagado,
        totalLista: total,
        telefono: _telefonoCtrl.text.trim(),
        responsable: _responsablesSeleccionados.join(', '),
        fechaRecojo: fechaHoraRecojo,
        notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Pedido creado'),
            backgroundColor: Colors.teal,
          ),
        );
        widget.onCreated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: keyboardHeight + 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Crear Lista de Pedidos',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),

          // Cliente
          TextField(
            controller: _clienteCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Nombre del Cliente',
              labelStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.person, color: Colors.teal),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Responsables
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Responsables',
              labelStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.badge_outlined, color: Colors.teal),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _responsablesSeleccionados.isEmpty
                      ? const [
                          Text('Sin asignar',
                              style: TextStyle(color: Colors.white38))
                        ]
                      : _responsablesSeleccionados
                          .map((r) => Chip(
                                label: Text(r),
                                onDeleted: () => setState(
                                    () => _responsablesSeleccionados.remove(r)),
                              ))
                          .toList(),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _seleccionarResponsables,
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Asignar responsables'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _telefonoCtrl,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Teléfono (opcional)',
              labelStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.phone, color: Colors.teal),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Total y pago
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _totalCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Total (S/.)',
                    labelStyle: const TextStyle(color: Colors.white54),
                    prefixIcon:
                        const Icon(Icons.receipt_long, color: Colors.teal),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _pagadoCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Pagado (S/.)',
                    labelStyle: const TextStyle(color: Colors.white54),
                    prefixIcon:
                        const Icon(Icons.attach_money, color: Colors.teal),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _notasCtrl,
            style: const TextStyle(color: Colors.white),
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Notas',
              labelStyle: const TextStyle(color: Colors.white54),
              prefixIcon:
                  const Icon(Icons.note_alt_outlined, color: Colors.teal),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Fecha/Hora Recojo
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _fechaRecojo,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                setState(() => _fechaRecojo = picked);
              }
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Fecha de Recojo',
                labelStyle: const TextStyle(color: Colors.white54),
                prefixIcon:
                    const Icon(Icons.calendar_today, color: Colors.teal),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
              ),
              child: Text(
                DateFormat('dd/MM/yyyy').format(_fechaRecojo),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _horaRecojo,
              );
              if (picked != null) {
                setState(() => _horaRecojo = picked);
              }
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Hora de Recojo',
                labelStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.schedule, color: Colors.teal),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
              ),
              child: Text(
                _horaRecojo.format(context),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Botón Crear
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _isCreating ? null : _crearPedido,
              icon: _isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.add),
              label: Text(_isCreating ? 'Creando...' : 'Crear Pedido'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _seleccionarResponsables() async {
    final temp = Set<String>.from(_responsablesSeleccionados);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: Colors.grey.shade900,
          title: const Text('Asignar responsables',
              style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 340,
            child: _responsablesDisponibles.isEmpty
                ? const Text('No se encontraron usuarios registrados',
                    style: TextStyle(color: Colors.white54))
                : ListView(
                    shrinkWrap: true,
                    children: _responsablesDisponibles
                        .map((u) => CheckboxListTile(
                              value: temp.contains(u),
                              onChanged: (v) {
                                setStateDialog(() {
                                  if (v == true) {
                                    temp.add(u);
                                  } else {
                                    temp.remove(u);
                                  }
                                });
                              },
                              title: Text(u,
                                  style: const TextStyle(color: Colors.white)),
                              controlAffinity: ListTileControlAffinity.leading,
                            ))
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                setState(() {
                  _responsablesSeleccionados
                    ..clear()
                    ..addAll(temp);
                });
                Navigator.pop(ctx);
              },
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Modal Detalles Pedido ──────────────────────────────────────────────────

class _DetallesPedidoModal extends StatefulWidget {
  final OrderList orden;
  final VoidCallback onActualizar;

  const _DetallesPedidoModal({
    required this.orden,
    required this.onActualizar,
  });

  @override
  State<_DetallesPedidoModal> createState() => _DetallesPedidoModalState();
}

class _DetallesPedidoModalState extends State<_DetallesPedidoModal> {
  final _service = OrderListService();
  late OrderList _orden = widget.orden;
  bool _isUploadingFoto = false;

  Future<void> _registrarAbono() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Registrar Abono',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Monto abonado (S/.)',
            labelStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final monto = double.tryParse(ctrl.text.replaceAll(',', '.'));
    if (monto == null || monto <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Monto inválido'), backgroundColor: Colors.red),
      );
      return;
    }

    final nuevoPagado = _orden.montoAdelantado + monto;
    final okUpdate = await _service.updateOrderListFinancial(
      order: _orden,
      nuevoMontoPagado: nuevoPagado,
    );
    if (!mounted) return;
    if (!okUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se pudo guardar abono'),
            backgroundColor: Colors.red),
      );
      return;
    }
    setState(() {
      _orden = _orden.copyWith(montoAdelantado: nuevoPagado);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _orden.estaCancelado
              ? 'Lista cancelada totalmente'
              : 'Abono registrado',
        ),
        backgroundColor: Colors.teal,
      ),
    );
    widget.onActualizar();
  }

  Future<void> _editarFinanzasYContacto() async {
    final totalCtrl =
        TextEditingController(text: _orden.totalLista.toStringAsFixed(2));
    final telCtrl = TextEditingController(text: _orden.telefonoContacto ?? '');
    final respCtrl = TextEditingController(text: _orden.responsable ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title:
            const Text('Editar Datos', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: totalCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Total lista'),
            ),
            TextField(
              controller: telCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Teléfono'),
            ),
            TextField(
              controller: respCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Responsable'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final total = double.tryParse(totalCtrl.text.replaceAll(',', '.'));
    if (total == null || total <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Total inválido'), backgroundColor: Colors.red),
      );
      return;
    }
    final updated = await _service.updateOrderListFinancial(
      order: _orden,
      nuevoTotalLista: total,
      nuevoTelefono: telCtrl.text.trim(),
      nuevoResponsable: respCtrl.text.trim(),
    );
    if (!mounted) return;
    if (!updated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se pudo actualizar'),
            backgroundColor: Colors.red),
      );
      return;
    }
    setState(() {
      _orden = _orden.copyWith(
        meta: _orden.meta.copyWith(
          totalLista: total,
          telefono: telCtrl.text.trim(),
          responsable: respCtrl.text.trim(),
        ),
      );
    });
    widget.onActualizar();
  }

  Future<void> _llamarCliente() async {
    final tel = _orden.telefonoContacto?.trim();
    if (tel == null || tel.isEmpty) return;
    final uri = Uri.parse('tel:$tel');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _capturarYSubirFoto() async {
    // ── [PATCH] Solicitar permiso de cámara antes de abrir el picker ──────────
    final permiso = await Permission.camera.request();

    if (!permiso.isGranted) {
      AppLogger.warning(
        'Permiso de cámara denegado. Estado: $permiso',
        tag: 'CAMERA',
      );
      if (mounted) {
        final isPermanentlyDenied = permiso.isPermanentlyDenied;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPermanentlyDenied
                  ? '🚫 Permiso de cámara bloqueado. Ve a Ajustes > Aplicaciones > BiPenc > Permisos para habilitarlo.'
                  : '📷 Necesitamos acceso a la cámara para tomar la foto del pedido.',
            ),
            backgroundColor: Colors.orange.shade800,
            duration: Duration(seconds: isPermanentlyDenied ? 5 : 3),
            action: isPermanentlyDenied
                ? const SnackBarAction(
                    label: 'Abrir Ajustes',
                    textColor: Colors.white,
                    onPressed: openAppSettings,
                  )
                : null,
          ),
        );
      }
      return;
    }
    // ─────────────────────────────────────────────────────────────────────────

    try {
      AppLogger.debug('Permiso concedido. Abriendo cámara...', tag: 'CAMERA');

      final foto = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (foto == null) {
        AppLogger.debug('Usuario canceló captura de foto', tag: 'CAMERA');
        return;
      }

      AppLogger.debug('Foto capturada: ${foto.path} (${foto.name})',
          tag: 'CAMERA');
      setState(() => _isUploadingFoto = true);

      final imagenFile = File(foto.path);
      final fileSizeKb = imagenFile.lengthSync() / 1024;
      AppLogger.debug('Tamaño de archivo: ${fileSizeKb.toStringAsFixed(2)} KB',
          tag: 'CAMERA');

      AppLogger.debug('Iniciando upload de foto a Storage...', tag: 'CAMERA');
      final (success, fotoUrl) = await _service.uploadFotoAndUpdate(
        _orden.id,
        imagenFile,
      );

      if (mounted) {
        if (success) {
          AppLogger.info('✅ Foto subida correctamente: $fotoUrl',
              tag: 'CAMERA');

          setState(() {
            _orden = _orden.copyWith(
              fotosUrls: [..._orden.fotosUrls, fotoUrl!],
            );
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Foto subida exitosamente'),
              backgroundColor: Colors.teal,
            ),
          );
          widget.onActualizar();
        } else {
          AppLogger.error('❌ Upload falló - Service retornó false',
              tag: 'CAMERA');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al subir foto. Intenta de nuevo.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Excepción en _capturarYSubirFoto: $e',
        tag: 'CAMERA',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error inesperado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingFoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: keyboardHeight + 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Encabezado
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _orden.clienteNombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${_orden.id}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getEstadoColor(_orden.estado),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _orden.estado,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Información
          _InfoRow(
            icon: Icons.attach_money,
            label: 'Pagado / Total',
            value:
                'S/.${_orden.montoAdelantado.toStringAsFixed(2)} / S/.${_orden.totalLista.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Saldo Pendiente',
            value: 'S/.${_orden.saldoPendiente.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.phone,
            label: 'Teléfono',
            value: _orden.telefonoContacto?.isNotEmpty == true
                ? _orden.telefonoContacto!
                : 'No registrado',
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.badge_outlined,
            label: 'Responsables',
            value: _orden.responsable?.isNotEmpty == true
                ? _orden.responsable!
                : 'Sin asignar',
          ),
          const SizedBox(height: 12),
          _InfoRow(
            icon: Icons.calendar_today,
            label: 'Fecha de Recojo',
            value: DateFormat('dd/MM/yyyy HH:mm').format(_orden.fechaRecojo),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _orden.telefonoContacto?.isNotEmpty == true
                      ? _llamarCliente
                      : null,
                  icon: const Icon(Icons.call),
                  label: const Text('Llamar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _editarFinanzasYContacto,
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Editar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _registrarAbono,
              icon: const Icon(Icons.add_card),
              label: const Text('Registrar Abono'),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal, foregroundColor: Colors.black),
            ),
          ),
          const SizedBox(height: 24),

          // Sección Fotos
          const Text(
            'Fotos de Lista de Papel',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          if (_orden.fotosUrls.isEmpty)
            const Center(
              child: Column(
                children: [
                  Icon(Icons.image_not_supported,
                      size: 48, color: Colors.white30),
                  SizedBox(height: 12),
                  Text(
                    'Sin fotos aún',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _orden.fotosUrls.length,
              itemBuilder: (ctx, idx) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _orden.fotosUrls[idx],
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, progress) => progress == null
                      ? child
                      : const Center(
                          child: CircularProgressIndicator(color: Colors.teal),
                        ),
                  errorBuilder: (ctx, err, st) => Container(
                    color: Colors.grey.shade900,
                    child: const Icon(Icons.error, color: Colors.red),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Botón Capturar
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _isUploadingFoto ? null : _capturarYSubirFoto,
              icon: _isUploadingFoto
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.camera_alt),
              label: Text(_isUploadingFoto ? 'Subiendo...' : 'Capturar Foto'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getEstadoColor(String estado) {
    switch (estado) {
      case 'PENDIENTE':
        return Colors.orange;
      case 'EN_PROCESO':
        return Colors.blue;
      case 'COMPLETADO':
        return Colors.green;
      case 'CANCELADO':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

// ── Helper Widget ──────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.tealAccent),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ],
    );
  }
}
