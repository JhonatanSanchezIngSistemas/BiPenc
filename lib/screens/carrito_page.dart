import 'package:flutter/material.dart';
import '../models/producto.dart';
import '../widgets/item_carrito_widget.dart';
import '../services/printing_service.dart';
import '../services/supabase_service.dart';
import '../services/carrito_service.dart';
import '../services/session_service.dart';
import '../utils/ticket_builder.dart';
import '../utils/precio_engine.dart';
import '../services/pdf_service.dart';
import '../utils/app_logger.dart';

/// Pantalla del carrito conectada al CarritoService singleton.
class CarritoPage extends StatefulWidget {
  const CarritoPage({super.key});

  @override
  State<CarritoPage> createState() => _CarritoPageState();
}

class _CarritoPageState extends State<CarritoPage> {
  final _carrito = CarritoService();
  final _session = SessionService();

  bool _isProcessing = false;
  bool _isPrinting = false;
  String _metodoPago = 'EFECTIVO';

  @override
  void initState() {
    super.initState();
    // El perfil ya está en SessionService, no necesitamos cargarlo
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _carrito,
      builder: (context, _) {
        final theme = Theme.of(context);
        final items = _carrito.items;

        return Scaffold(
          backgroundColor: const Color(0xFF0F0F1A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0F0F1A),
            title: Text(
              'Carrito (${_carrito.totalItems} uds)',
              style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
            ),
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.tealAccent),
            ),
            actions: [
              if (items.isNotEmpty)
                TextButton(
                  onPressed: _limpiarCarrito,
                  child: const Text('Vaciar', style: TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
          body: items.isEmpty
              ? _buildCarritoVacio()
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ItemCarritoWidget(
                            item: item,
                            onIncrement: () => _carrito.incrementar(index),
                            onDecrement: () => _carrito.decrementar(index),
                            onRemove: () => _carrito.eliminar(index),
                            onPrecioEditado: (precio) =>
                                _carrito.aplicarPrecioPersonalizado(index, precio),
                          );
                        },
                      ),
                    ),
                    _buildResumenPanel(theme),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildCarritoVacio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey.shade800),
          const SizedBox(height: 16),
          Text('El carrito está vacío', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Volver a buscar', style: TextStyle(color: Colors.tealAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenPanel(ThemeData theme) {
    final total = _carrito.subtotal;
    final totalRedondeado = _carrito.totalRedondeado;
    final redondeo = _carrito.redondeo;
    final ahorroTotal = _carrito.ahorroTotal;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Banner de ahorro
          if (ahorroTotal > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF2ECC71).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2ECC71).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.savings_outlined, color: Color(0xFF2ECC71), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Ahorro: S/ ${ahorroTotal.toStringAsFixed(2)}',
                    style: const TextStyle(color: Color(0xFF2ECC71), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOTAL', style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey.shade400)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (redondeo > 0.001)
                    Text(
                      'S/ ${total.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Text(
                    'S/ ${totalRedondeado.toStringAsFixed(2)}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.tealAccent,
                    ),
                  ),
                  if (redondeo > 0.001)
                    Text(
                      '+S/${redondeo.toStringAsFixed(2)} redondeo',
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildMetodoPagoSelector(),
          const SizedBox(height: 16),

          if (_isProcessing || _isPrinting)
            Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(color: Colors.tealAccent),
                  const SizedBox(height: 8),
                  Text(
                    _isPrinting ? 'Imprimiendo...' : 'Procesando...',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _imprimirTicket,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Imprimir Ticket Previo'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      side: const BorderSide(color: Colors.orangeAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _finalizarVenta('boleta'),
                        icon: const Icon(Icons.receipt_long, size: 18),
                        label: const Text('Boleta'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.tealAccent,
                          side: const BorderSide(color: Colors.tealAccent),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _finalizarVenta('factura'),
                        icon: const Icon(Icons.description_outlined, size: 18),
                        label: const Text('Factura'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.tealAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMetodoPagoSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Método de Pago',
            style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildPagoTab('EFECTIVO', Icons.payments_outlined),
            _buildPagoTab('YAPE', Icons.smartphone_outlined),
            _buildPagoTab('TRANSF.', Icons.account_balance_outlined),
          ],
        ),
      ],
    );
  }

  Widget _buildPagoTab(String label, IconData icon) {
    final isSelected = _metodoPago == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _metodoPago = label),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.tealAccent.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? Colors.tealAccent : Colors.grey.shade800,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? Colors.tealAccent : Colors.grey, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.tealAccent : Colors.grey,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _imprimirTicket() async {
    setState(() => _isPrinting = true);
    try {
      final alias = _session.perfil?.alias ?? 'VENDEDOR';
      final total = _carrito.subtotal;
      final ticketText = TicketBuilder.buildVenta(
        ancho: 48,
        items: _carrito.snapshot(),
        total: total,
        vendedor: alias,
        correlativo: 'PRE-${DateTime.now().millisecondsSinceEpoch}',
        cliente: '',
        dniRuc: '',
        tipo: 'PRE-VENTA',
      );

      final errorPrint = await PrintingService.instance.printRawText(ticketText);
      if (!mounted) return;

      if (errorPrint == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Ticket impreso'), backgroundColor: Color(0xFF2ECC71)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🔴 $errorPrint'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  void _finalizarVenta(String tipo) => _mostrarDialogoDatosCliente(tipo);

  void _mostrarDialogoDatosCliente(String tipo) {
    final dniRucController = TextEditingController();
    final nombreController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: Text('Datos de $tipo', style: const TextStyle(color: Colors.tealAccent)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dniRucController,
              keyboardType: TextInputType.number,
              maxLength: 11,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'DNI / RUC',
                labelStyle: TextStyle(color: Colors.grey.shade500),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade700)),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nombreController,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Nombre / Razón Social',
                labelStyle: TextStyle(color: Colors.grey.shade500),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade700)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _procesarFinalizacion(
                tipo: tipo,
                dniRuc: dniRucController.text,
                nombre: nombreController.text,
              );
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
            child: const Text('Confirmar y Cobrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _procesarFinalizacion({
    required String tipo,
    required String dniRuc,
    required String nombre,
  }) async {
    setState(() => _isProcessing = true);
    try {
      final perfil = _session.perfil;
      final alias = perfil?.alias ?? 'DESCONOCIDO';
      final itemsSnapshot = _carrito.snapshot();
      final totalRedondeado = _carrito.totalRedondeado;
      final total = _carrito.subtotal;

      final correlativo = await SupabaseService.generarSiguienteCorrelativo(alias);

      final ticketText = TicketBuilder.buildVenta(
        ancho: 48,
        items: itemsSnapshot,
        total: total,
        vendedor: alias,
        correlativo: correlativo,
        dniRuc: dniRuc,
        cliente: nombre,
        tipo: tipo.toUpperCase(),
      );

      final errorImpresion = await PrintingService.instance.printRawText(ticketText);

      if (errorImpresion != null) {
        if (!mounted) return;
        final proceedAnyway = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E2C),
            title: const Text('⚠️ Error de Impresión', style: TextStyle(color: Colors.orangeAccent)),
            content: Text('No se pudo imprimir: $errorImpresion\n¿Registrar la venta igualmente?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Registrar sin Ticket'),
              ),
            ],
          ),
        );
        if (proceedAnyway != true) {
          setState(() => _isProcessing = false);
          return;
        }
      }

      final ok = await SupabaseService.registrarVenta(
        items: itemsSnapshot,
        total: totalRedondeado,
        alias: alias,
        metodoPago: _metodoPago,
        tipoDocumento: tipo.toUpperCase(),
        dniRuc: dniRuc,
        nombreCliente: nombre,
      );

      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ S/ ${totalRedondeado.toStringAsFixed(2)} — $correlativo'),
            backgroundColor: const Color(0xFF2ECC71),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'PDF',
              textColor: Colors.white,
              onPressed: () async {
                final file = await PdfService.generateVentaPdf(
                  items: itemsSnapshot,
                  total: totalRedondeado,
                  vendedor: alias,
                  correlativo: correlativo,
                  cliente: nombre,
                  dniRuc: dniRuc,
                  tipo: tipo.toUpperCase(),
                );
                await PdfService.shareVentaPdf(file);
              },
            ),
          ),
        );

        // Limpiar carrito global
        _carrito.limpiar();

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/picking', arguments: {
            'items': itemsSnapshot,
            'total': totalRedondeado,
            'documento': tipo.toUpperCase(),
          });
        }
      } else if (mounted) {
        throw Exception('Error al guardar la venta');
      }
    } catch (e) {
      AppLogger.error('Error procesando venta', tag: 'CARRITO', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _limpiarCarrito() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: const Text('¿Vaciar carrito?', style: TextStyle(color: Colors.white)),
        content: const Text('Se eliminarán todos los productos.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _carrito.limpiar();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Vaciar'),
          ),
        ],
      ),
    );
  }
}
