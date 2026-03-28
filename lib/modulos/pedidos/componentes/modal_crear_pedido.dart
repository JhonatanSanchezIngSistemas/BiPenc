import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:bipenc/datos/modelos/pedido.dart';
import 'package:bipenc/servicios/servicio_pedidos.dart';
import 'package:bipenc/utilidades/registro_app.dart';
import 'package:bipenc/servicios/servicio_impresion.dart';
import 'package:bipenc/servicios/servicio_procesamiento_imagen.dart';
import 'package:bipenc/servicios/servicio_foto_pedido.dart';
import 'package:bipenc/servicios/servicio_ocr.dart';
import 'package:bipenc/servicios/servicio_db_local.dart';
import 'package:bipenc/datos/modelos/producto.dart';

class ModalCrearPedido extends StatefulWidget {
  final VoidCallback onCreated;

  const ModalCrearPedido({super.key, required this.onCreated});

  @override
  State<ModalCrearPedido> createState() => _ModalCrearPedidoState();
}

class _ModalCrearPedidoState extends State<ModalCrearPedido> {
  final _service = ServicioPedidos();
  final _clienteCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final _pagadoCtrl = TextEditingController();
  final _bultosCtrl = TextEditingController();
  final _horaCtrl = TextEditingController();
  String? _destinatario; // NIÑO / NIÑA / null
  final _notasCtrl = TextEditingController();
  late DateTime _fechaRecojo = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _horaRecojo = TimeOfDay.now();
  List<String> _responsablesDisponibles = const [];
  final Set<String> _responsablesSeleccionados = <String>{};
  bool _isCreating = false;
  bool _horaInicializada = false;

  @override
  void initState() {
    super.initState();
    _cargarResponsables();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Necesita contexto para Localizations/MaterialLocalizations
    if (!_horaInicializada) {
      _horaCtrl.text = _horaRecojo.format(context);
      _horaInicializada = true;
    }
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
    _bultosCtrl.dispose();
    _horaCtrl.dispose();
    super.dispose();
  }

  Future<void> _crearPedido() async {
    if (_isCreating) return;

    final nombre = _clienteCtrl.text.trim();
    if (nombre.isEmpty) {
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
            content: Text('Ingresa total válido (S/.)'),
            backgroundColor: Colors.red),
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
      final created = await _service.createPedido(
        clienteNombre: nombre,
        montoAdelantado: pagado,
        totalLista: total,
        telefono: _telefonoCtrl.text.trim(),
        responsable: _responsablesSeleccionados.join(', '),
        bultos: int.tryParse(_bultosCtrl.text.trim()),
        destinatario: _destinatario,
        fechaRecojo: fechaHoraRecojo,
        notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim(),
      );

      if (created == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo crear el pedido'),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Pedido creado'),
            backgroundColor: Colors.teal,
          ),
        );
        widget.onCreated();

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('¿Registrar productos ahora?'),
            content: const Text(
                'Puedes abrir el POS con la foto de la lista como referencia y escanear directamente.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Después')),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  GoRouter.of(context).go('/pos', extra: {
                    'orderId': created.id,
                    'fotoUrl': created.fotosUrls.isNotEmpty
                        ? created.fotosUrls.first
                        : null,
                  });
                },
                child: const Text('Ir al POS'),
              )
            ],
          ),
        );
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
          DropdownButtonFormField<String>(
            initialValue: _destinatario,
            decoration: InputDecoration(
              labelText: 'Destinatario',
              labelStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.child_friendly, color: Colors.teal),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12),
              ),
            ),
            dropdownColor: Colors.grey.shade900,
            style: const TextStyle(color: Colors.white),
            items: const [
              DropdownMenuItem(value: 'NIÑO', child: Text('Niño')),
              DropdownMenuItem(value: 'NIÑA', child: Text('Niña')),
            ],
            onChanged: (v) => setState(() => _destinatario = v),
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
          const SizedBox(height: 12),
          TextField(
            controller: _bultosCtrl,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Bultos (opcional)',
              labelStyle: const TextStyle(color: Colors.white54),
              prefixIcon:
                  const Icon(Icons.inventory_2_outlined, color: Colors.teal),
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
              FocusScope.of(context).unfocus();
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
          TextField(
            controller: _horaCtrl,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Hora de Recojo (HH:mm)',
              labelStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.schedule, color: Colors.teal),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.access_time, color: Colors.white54),
                onPressed: () async {
                  FocusScope.of(context).unfocus();
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _horaRecojo,
                  );
                  if (picked != null) {
                    setState(() {
                      _horaRecojo = picked;
                      _horaCtrl.text = picked.format(context);
                    });
                  }
                },
              ),
            ),
            onChanged: (v) {
              final parts = v.split(':');
              if (parts.length == 2) {
                final h = int.tryParse(parts[0]);
                final m = int.tryParse(parts[1]);
                if (h != null &&
                    m != null &&
                    h >= 0 &&
                    h < 24 &&
                    m >= 0 &&
                    m < 60) {
                  setState(() => _horaRecojo = TimeOfDay(hour: h, minute: m));
                }
              }
            },
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
