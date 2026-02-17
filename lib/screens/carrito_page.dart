import 'package:flutter/material.dart';
import '../models/producto.dart';
import '../widgets/item_carrito_widget.dart';

/// Pantalla del carrito con resumen en tiempo real y opciones de finalización.
class CarritoPage extends StatefulWidget {
  const CarritoPage({super.key});

  @override
  State<CarritoPage> createState() => _CarritoPageState();
}

class _CarritoPageState extends State<CarritoPage> {
  List<ItemCarrito> _carrito = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is List<ItemCarrito>) {
      _carrito = args;
    }
  }

  double get _total =>
      _carrito.fold(0.0, (sum, item) => sum + item.subtotal);

  double get _ahorroTotal =>
      _carrito.fold(0.0, (sum, item) => sum + item.ahorroTotal);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Text('Carrito',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.tealAccent),
        ),
        actions: [
          if (_carrito.isNotEmpty)
            TextButton(
              onPressed: _limpiarCarrito,
              child: const Text('Vaciar',
                  style: TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
      body: _carrito.isEmpty
          ? _buildCarritoVacio()
          : Column(
              children: [
                // ── Lista de ítems ──
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    itemCount: _carrito.length,
                    itemBuilder: (context, index) {
                      final item = _carrito[index];
                      return ItemCarritoWidget(
                        item: item,
                        onIncrement: () => setState(() => item.cantidad++),
                        onDecrement: () {
                          setState(() {
                            if (item.cantidad > 1) {
                              item.cantidad--;
                            } else {
                              _carrito.removeAt(index);
                            }
                          });
                        },
                        onRemove: () =>
                            setState(() => _carrito.removeAt(index)),
                        onMayoristaChanged: (val) {
                          setState(() {
                            item.esMayorista = val;
                            if (val) item.precioEditado = null;
                          });
                        },
                        onPrecioEditado: (precio) {
                          setState(() {
                            if (precio >= item.producto.precioBase) {
                              item.precioEditado = null;
                            } else {
                              item.precioEditado = precio;
                              item.esMayorista = false;
                            }
                          });
                        },
                      );
                    },
                  ),
                ),

                // ── Panel inferior: Resumen + Acciones ──
                _buildResumenPanel(theme),
              ],
            ),
    );
  }

  Widget _buildCarritoVacio() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined,
              size: 80, color: Colors.grey.shade800),
          const SizedBox(height: 16),
          Text(
            'El carrito está vacío',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenPanel(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 10,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ahorro
          if (_ahorroTotal > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF2ECC71).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF2ECC71).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.savings_outlined,
                      color: Color(0xFF2ECC71), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Ahorro Total: S/ ${_ahorroTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Color(0xFF2ECC71),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOTAL',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: Colors.grey.shade400)),
              Text(
                'S/ ${_total.toStringAsFixed(2)}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.tealAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Botones de acción
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _finalizarVenta('boleta'),
                  icon: const Icon(Icons.receipt_long, size: 18),
                  label: const Text('Boleta Simple'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.tealAccent,
                    side: const BorderSide(color: Colors.tealAccent),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _finalizarVenta(String tipo) {
    if (tipo == 'factura') {
      _mostrarDialogoFactura();
    } else {
      _confirmarVenta(tipo, null);
    }
  }

  void _mostrarDialogoFactura() {
    final dniRucController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: const Text('Datos de Factura',
            style: TextStyle(color: Colors.tealAccent)),
        content: TextField(
          controller: dniRucController,
          keyboardType: TextInputType.number,
          maxLength: 11,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            labelText: 'DNI / RUC',
            labelStyle: TextStyle(color: Colors.grey.shade500),
            counterStyle: TextStyle(color: Colors.grey.shade600),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade700),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Colors.tealAccent, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmarVenta('factura', dniRucController.text);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Emitir Factura'),
          ),
        ],
      ),
    );
  }

  void _confirmarVenta(String tipo, String? dniRuc) {
    final tipoLabel = tipo == 'factura' ? 'Factura' : 'Boleta';
    final extra = dniRuc != null && dniRuc.isNotEmpty ? ' — $dniRuc' : '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$tipoLabel emitida$extra — Total: S/ ${_total.toStringAsFixed(2)}',
        ),
        backgroundColor: const Color(0xFF2ECC71),
        duration: const Duration(seconds: 3),
      ),
    );

    setState(() => _carrito.clear());
  }

  void _limpiarCarrito() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: const Text('¿Vaciar carrito?',
            style: TextStyle(color: Colors.white)),
        content: const Text('Se eliminarán todos los productos.',
            style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _carrito.clear());
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            child: const Text('Vaciar'),
          ),
        ],
      ),
    );
  }
}
