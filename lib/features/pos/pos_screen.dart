import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:bipenc/data/models/product.dart';
import 'package:bipenc/data/models/cliente.dart';
import 'package:bipenc/services/identidad_service.dart';
import 'package:bipenc/services/print_service.dart';
import 'package:bipenc/widgets/conectividad_indicador.dart';
import 'package:bipenc/features/pos/pos_provider.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});
  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _searchCtrl = TextEditingController();
  List<Product> _resultados = [];
  bool _buscando = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscar(String query, PosProvider pos) async {
    if (query.trim().isEmpty) {
      setState(() => _resultados = []);
      return;
    }
    setState(() => _buscando = true);
    final res = await pos.buscarProductos(query);
    if (mounted) setState(() { _resultados = res; _buscando = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PosProvider>(
      builder: (context, pos, _) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.grey.shade900,
            foregroundColor: Colors.white,
            title: const Text('BiPenc POS', style: TextStyle(letterSpacing: 1)),
            actions: [
              // Indicador online/offline discreto (Constitución Artículo 1.3)
              const ConectividadIndicador(),
              IconButton(
                icon: const Icon(Icons.add_shopping_cart, color: Colors.teal),
                tooltip: 'Producto genérico',
                onPressed: () {
                  pos.agregarProductoGenerico();
                  _searchCtrl.clear();
                  setState(() => _resultados = []);
                },
              ),
              IconButton(
                icon: const Icon(Icons.inventory_2_outlined),
                tooltip: 'Inventario',
                onPressed: () => context.push('/inventario'),
              ),
            ],
          ),
          body: Column(
            children: [
              // ── Pestañas de 5 Clientes (Constitución Artículo 2) ─────────
              _ClienteTabs(pos: pos),

              // ── Buscador de Productos ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (q) => _buscar(q, pos),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, SKU o marca...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, color: Colors.teal),
                    suffixIcon: _buscando
                        ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal)))
                        : _searchCtrl.text.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.clear, color: Colors.white54), onPressed: () { _searchCtrl.clear(); setState(() => _resultados = []); })
                            : null,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.07),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),

              // ── Resultados de Búsqueda ────────────────────────────────────
              if (_resultados.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _resultados.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                    itemBuilder: (ctx, i) {
                      final p = _resultados[i];
                      return ListTile(
                        dense: true,
                        title: Text(p.nombre, style: const TextStyle(color: Colors.white, fontSize: 13)),
                        subtitle: Text('${p.marca} • ${p.categoria}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('S/.${p.precioBase.toStringAsFixed(2)}', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 13)),
                            if (p.tienePrecioMayorista)
                              Text('May: S/.${p.precioMayorista.toStringAsFixed(2)}', style: const TextStyle(color: Colors.amber, fontSize: 10)),
                          ],
                        ),
                        onTap: () {
                          pos.agregarProducto(p);
                          _searchCtrl.clear();
                          setState(() => _resultados = []);
                          HapticFeedback.lightImpact();
                        },
                      );
                    },
                  ),
                ),

              const Divider(height: 1, color: Colors.white12, indent: 12, endIndent: 12),

              // ── Carrito ───────────────────────────────────────────────────
              Expanded(
                child: pos.items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.white12),
                            const SizedBox(height: 12),
                            const Text('Carrito vacío', style: TextStyle(color: Colors.white24, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text('Total: S/. ${pos.totalCobrar.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white12, fontSize: 14)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: pos.items.length,
                        itemBuilder: (ctx, i) => _CartItemTile(index: i, item: pos.items[i], pos: pos),
                      ),
              ),
            ],
          ),
          bottomNavigationBar: _BottomBar(pos: pos),
        );
      },
    );
  }
}

// ── Pestañas de 5 Clientes ────────────────────────────────────────────────────
class _ClienteTabs extends StatelessWidget {
  final PosProvider pos;
  const _ClienteTabs({required this.pos});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: pos.maxCarritos,
        itemBuilder: (ctx, i) {
          final isActive = pos.activeCartIndex == i;
          final isEmpty = pos.isCartEmpty(i);
          return GestureDetector(
            onTap: () => pos.cambiarCarrito(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isActive ? Colors.teal : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isActive ? Colors.tealAccent : Colors.white12),
              ),
              child: Row(
                children: [
                  Text(
                    'C${i + 1}',
                    style: TextStyle(
                      color: isActive ? Colors.black : Colors.white54,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  if (!isEmpty) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: isActive ? Colors.black54 : Colors.tealAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Cart Item Tile ─────────────────────────────────────────────────────────────
class _CartItemTile extends StatelessWidget {
  final int index;
  final CartItem item;
  final PosProvider pos;
  const _CartItemTile({required this.index, required this.item, required this.pos});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('item_${index}_${item.product.sku}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        color: Colors.red.shade800,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => pos.eliminarItem(index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          dense: true,
          title: Text(item.product.nombre,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Row(
            children: [
              GestureDetector(
                onTap: () => pos.actualizarCantidad(index, -1),
                child: const Icon(Icons.remove_circle_outline, color: Colors.white38, size: 20),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('${item.cantidad}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              GestureDetector(
                onTap: () => pos.actualizarCantidad(index, 1),
                child: const Icon(Icons.add_circle_outline, color: Colors.teal, size: 20),
              ),
              const SizedBox(width: 8),
              // Toggle mayorista (si el producto lo soporta)
              if (item.product.tienePrecioMayorista)
                GestureDetector(
                  onTap: () => pos.toggleMayorista(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.usarPrecioMayorista ? Colors.amber.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: item.usarPrecioMayorista ? Colors.amber : Colors.white24),
                    ),
                    child: Text(
                      item.etiquetaPrecio,
                      style: TextStyle(
                        color: item.usarPrecioMayorista ? Colors.amber : Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          trailing: GestureDetector(
            onLongPress: () => _editarPrecio(context),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('S/.${item.subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 14)),
                Text('@${item.precioUnitario.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _editarPrecio(BuildContext context) {
    final ctrl = TextEditingController(text: item.precioUnitario.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Precio Especial', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            prefixText: 'S/. ',
            prefixStyle: TextStyle(color: Colors.teal),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.teal)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () {
              final p = double.tryParse(ctrl.text);
              if (p != null && p > 0) pos.setPrecioManual(index, p);
              Navigator.pop(ctx);
            },
            child: const Text('Aplicar', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}

// ── Bottom Bar ────────────────────────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  final PosProvider pos;
  const _BottomBar({required this.pos});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        border: const Border(top: BorderSide(color: Colors.white12)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${pos.cantidadArticulos} art.',
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  Text('S/. ${pos.totalCobrar.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
                ],
              ),
            ),
            if (pos.items.isNotEmpty)
              TextButton(
                onPressed: () => pos.vaciarCarrito(),
                child: const Text('Limpiar', style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: pos.items.isEmpty ? null : () => _iniciarCobro(context, pos),
              icon: const Icon(Icons.point_of_sale),
              label: const Text('COBRAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _iniciarCobro(BuildContext context, PosProvider pos) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _PanelCobro(pos: pos),
    );
  }
}

// ── Panel de Cobro ────────────────────────────────────────────────────────────
class _PanelCobro extends StatefulWidget {
  final PosProvider pos;
  const _PanelCobro({required this.pos});
  @override
  State<_PanelCobro> createState() => _PanelCobroState();
}

class _PanelCobroState extends State<_PanelCobro> {
  final _montoCtrl = TextEditingController();
  final _docCtrl = TextEditingController();
  bool _buscandoCliente = false;
  String? _nombreCliente;

  @override
  void initState() {
    super.initState();
    _montoCtrl.text = widget.pos.totalCobrar.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _docCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscarCliente(String doc, bool esRuc) async {
    setState(() { _buscandoCliente = true; _nombreCliente = null; });
    final nombre = await IdentidadService().consultarDocumento(doc, esRuc);
    if (!mounted) return;
    if (nombre == 'OFFLINE') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📵 Modo Offline: Ingrese el nombre manualmente'),
          backgroundColor: Colors.orange,
        ),
      );
    } else if (nombre != null && nombre != 'ERROR') {
      setState(() => _nombreCliente = nombre);
      widget.pos.setCliente(Cliente(documento: doc, nombre: nombre));
    }
    setState(() => _buscandoCliente = false);
  }

  Future<void> _cobrar() async {
    final monto = double.tryParse(_montoCtrl.text.replaceAll(',', '.'));
    if (monto != null) widget.pos.setMontoRecibido(monto);

    if (!widget.pos.canCheckout) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.pos.totalCobrar > (monto ?? 0)
              ? 'Monto insuficiente — faltan S/.${(widget.pos.totalCobrar - (monto ?? 0)).toStringAsFixed(2)}'
              : 'El carrito está vacío'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await widget.pos.procesarVenta();

    try {
      await PrintService().imprimirTicketCortesia(widget.pos);
    } catch (_) {}

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Venta registrada'),
          backgroundColor: Colors.teal,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.pos;
    final vuelto = (double.tryParse(_montoCtrl.text) ?? 0) - pos.totalCobrar;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),

          Text('Total: S/.${pos.totalCobrar.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Método de pago
          Row(
            children: MetodoPago.values.map((m) {
              final labels = {MetodoPago.efectivo: '💵 Efectivo', MetodoPago.yapePlin: '📱 Yape/Plin', MetodoPago.tarjeta: '💳 Tarjeta'};
              final isActive = pos.metodoPago == m;
              return Expanded(
                child: GestureDetector(
                  onTap: () { pos.setMetodoPago(m); setState(() {}); },
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.teal : Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isActive ? Colors.tealAccent : Colors.white12),
                    ),
                    child: Text(labels[m]!, textAlign: TextAlign.center,
                        style: TextStyle(color: isActive ? Colors.black : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Monto recibido (solo efectivo)
          if (pos.metodoPago == MetodoPago.efectivo) ...[
            TextField(
              controller: _montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white, fontSize: 20),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Monto recibido',
                labelStyle: TextStyle(color: Colors.white54),
                prefixText: 'S/. ',
                prefixStyle: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 20),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.teal)),
              ),
            ),
            if (vuelto > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Vuelto:', style: TextStyle(color: Colors.white54, fontSize: 16)),
                    Text('S/.${vuelto.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.amber, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
          ],

          // DNI/RUC (opcional)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _docCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'DNI / RUC (opcional)',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                    prefixIcon: const Icon(Icons.person_search, color: Colors.white38, size: 18),
                    filled: true, fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buscandoCliente
                  ? const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: Colors.teal, strokeWidth: 2))
                  : IconButton(
                      icon: const Icon(Icons.search, color: Colors.teal),
                      onPressed: () {
                        final doc = _docCtrl.text.trim();
                        if (doc.length >= 8) _buscarCliente(doc, doc.length == 11);
                      },
                    ),
            ],
          ),
          if (_nombreCliente != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('👤 $_nombreCliente',
                  style: const TextStyle(color: Colors.tealAccent, fontSize: 12)),
            ),
          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: _cobrar,
            icon: const Icon(Icons.check_circle),
            label: const Text('CONFIRMAR COBRO', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    ),
  );
}
