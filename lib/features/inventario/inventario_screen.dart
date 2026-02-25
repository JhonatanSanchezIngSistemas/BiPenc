import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/product.dart';
import '../../data/local/db_helper.dart';
import '../../widgets/conectividad_indicador.dart';

const _kCategorias = ['Todos', 'Escritura', 'Arte', 'Cuadernos', 'Papelería'];

const _kIconoCategoria = {
  'Escritura': Icons.edit,
  'Arte': Icons.palette,
  'Cuadernos': Icons.menu_book,
  'Papelería': Icons.folder_copy,
};

class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key});

  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  List<Product> _productosBase = [];
  List<Product> _productosFiltrados = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _filtroActivo = 'Todos';

  @override
  void initState() {
    super.initState();
    _cargarProductos();
  }

  Future<void> _cargarProductos() async {
    setState(() => _isLoading = true);
    final prods = await DBHelper().getAllProducts();
    if (mounted) {
      setState(() {
        _productosBase = prods;
        _productosFiltrados = prods;
        _isLoading = false;
      });
    }
  }

  void _filtrarInventario(String query) {
    final busqueda = query.toLowerCase();
    setState(() {
      final filtrados = _productosBase.where((prod) {
        final pasaCategoria = _filtroActivo == 'Todos' ||
            (prod.categoria.toLowerCase() == _filtroActivo.toLowerCase());
        if (!pasaCategoria) return false;
        if (busqueda.isEmpty) return true;
        return prod.nombre.toLowerCase().contains(busqueda) ||
            prod.sku.toLowerCase().contains(busqueda) ||
            prod.marca.toLowerCase().contains(busqueda);
      }).toList();
      
      // Optimizacion: Solo mostramos los primeros 20 para evitar lag en el Samsung A36
      _productosFiltrados = filtrados.take(20).toList();
    });
  }

  Future<void> _abrirEditor(Product producto) async {
    final actualizado = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditarProductoSheet(producto: producto),
    );
    if (actualizado != null) {
      await DBHelper().updateProduct(actualizado);
      _cargarProductos();
    }
  }

  Future<void> _confirmarEliminar(Product producto) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Row(
          children: [Icon(Icons.warning_amber_rounded, color: Colors.red), SizedBox(width: 8), Text('Eliminar Producto', style: TextStyle(color: Colors.white))],
        ),
        content: Text('¿Seguro que deseas borrar "${producto.nombre}"?\nSKU: ${producto.sku}\n\nEsta acción es irreversible.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado == true) {
      await DBHelper().deleteProduct(producto.sku);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${producto.nombre} eliminado.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      _cargarProductos();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey.shade900,
        actions: const [
          ConectividadIndicador(),
        ],
        title: TextField(
          controller: _searchController,
          onChanged: _filtrarInventario,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Buscar por nombre, SKU o marca...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            border: InputBorder.none,
            icon: const Icon(Icons.search, color: Colors.teal),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear, color: Colors.white70),
              onPressed: () {
                _searchController.clear();
                _filtrarInventario('');
              },
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: _kCategorias.map((cat) {
                final activo = _filtroActivo == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: cat != 'Todos'
                        ? Icon(_kIconoCategoria[cat], size: 16, color: activo ? Colors.black : Colors.teal.shade300)
                        : null,
                    label: Text(cat,
                        style: TextStyle(
                          color: activo ? Colors.black : Colors.teal.shade300,
                          fontWeight: activo ? FontWeight.bold : FontWeight.normal,
                        )),
                    selected: activo,
                    selectedColor: Colors.teal.shade400,
                    backgroundColor: Colors.grey.shade800,
                    checkmarkColor: Colors.black,
                    side: BorderSide(color: activo ? Colors.teal.shade400 : Colors.transparent),
                    onSelected: (_) {
                      setState(() => _filtroActivo = activo && cat != 'Todos' ? 'Todos' : cat);
                      _filtrarInventario(_searchController.text);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : _productosFiltrados.isEmpty && _productosBase.isEmpty
              : Column(
                  children: [
                    if (_productosBase.length > 20 && _searchController.text.isEmpty && _filtroActivo == 'Todos')
                      Container(
                        padding: const EdgeInsets.all(8),
                        width: double.infinity,
                        color: Colors.teal.withOpacity(0.1),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.info_outline, size: 14, color: Colors.tealAccent),
                            SizedBox(width: 8),
                            Text('Mostrando los 20 más recientes para mayor velocidad.', 
                              style: TextStyle(color: Colors.tealAccent, fontSize: 11)),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _productosFiltrados.length,
                        itemBuilder: (_, index) {
                          final prod = _productosFiltrados[index];
                          return _ProductoCard(
                            producto: prod,
                            onEditar: () => _abrirEditor(prod),
                            onEliminar: () => _confirmarEliminar(prod),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'quickAdd',
            backgroundColor: Colors.orange,
            foregroundColor: Colors.black,
            onPressed: () async {
              final res = await context.push<bool>('/inventario/rapido');
              if (res == true) _cargarProductos();
            },
            icon: const Icon(Icons.flash_on),
            label: const Text('⚡ Rápido', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'fullAdd',
            backgroundColor: Colors.teal,
            foregroundColor: Colors.black,
            onPressed: () async {
              final res = await context.push<bool>('/inventario/nuevo');
              if (res == true) _cargarProductos();
            },
            icon: const Icon(Icons.add),
            label: const Text('Completo', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 80, color: Colors.white12),
            const SizedBox(height: 24),
            const Text('Sin productos registrados', style: TextStyle(fontSize: 18, color: Colors.white54)),
            const SizedBox(height: 12),
            const Text('Usa "Carga Rápida" para empezar en segundos.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white24, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _ProductoCard extends StatelessWidget {
  final Product producto;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  const _ProductoCard({required this.producto, required this.onEditar, required this.onEliminar});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey.shade900,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.teal.withOpacity(0.1),
          child: Icon(_kIconoCategoria[producto.categoria] ?? Icons.inventory_2, color: Colors.teal, size: 20),
        ),
        title: Text(producto.nombre, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        subtitle: Text('${producto.marca} | ${producto.sku}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('S/.${producto.precioBase.toStringAsFixed(2)}', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
                if (producto.tienePrecioMayorista)
                  Text('May: S/.${producto.precioMayorista.toStringAsFixed(2)}', style: const TextStyle(color: Colors.amber, fontSize: 10)),
              ],
            ),
            IconButton(icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.white54), onPressed: onEditar),
            IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent), onPressed: onEliminar),
          ],
        ),
      ),
    );
  }
}

class _EditarProductoSheet extends StatefulWidget {
  final Product producto;
  const _EditarProductoSheet({required this.producto});
  @override
  State<_EditarProductoSheet> createState() => _EditarProductoSheetState();
}

class _EditarProductoSheetState extends State<_EditarProductoSheet> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _marcaCtrl;
  late final TextEditingController _precioBaseCtrl;
  late final TextEditingController _precioMayoristaCtrl;
  late String _categoria;

  @override
  void initState() {
    super.initState();
    final p = widget.producto;
    _nombreCtrl = TextEditingController(text: p.nombre);
    _marcaCtrl = TextEditingController(text: p.marca);
    _precioBaseCtrl = TextEditingController(text: p.precioBase.toStringAsFixed(2));
    _precioMayoristaCtrl = TextEditingController(text: p.precioMayorista.toStringAsFixed(2));
    _categoria = p.categoria;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose(); _marcaCtrl.dispose();
    _precioBaseCtrl.dispose(); _precioMayoristaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, left: 20, right: 20, top: 10),
      decoration: const BoxDecoration(color: Color(0xFF1E1E1E), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Editar Producto', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _campo(_nombreCtrl, 'Nombre', Icons.label),
          const SizedBox(height: 12),
          _campo(_marcaCtrl, 'Marca', Icons.branding_watermark),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _campoPrecio(_precioBaseCtrl, 'Precio Base')),
              const SizedBox(width: 12),
              Expanded(child: _campoPrecio(_precioMayoristaCtrl, 'Precio Mayo (3+)')),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: () {
              final p = widget.producto.copyWith(
                nombre: _nombreCtrl.text.trim(),
                marca: _marcaCtrl.text.trim(),
                precioBase: double.tryParse(_precioBaseCtrl.text) ?? widget.producto.precioBase,
                precioMayorista: double.tryParse(_precioMayoristaCtrl.text) ?? widget.producto.precioMayorista,
              );
              Navigator.pop(context, p);
            },
            child: const Text('GUARDAR CAMBIOS', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _campo(TextEditingController ctrl, String label, IconData icon) => TextField(
    controller: ctrl,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label, labelStyle: const TextStyle(color: Colors.white54),
      prefixIcon: Icon(icon, color: Colors.teal),
      filled: true, fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
  );

  Widget _campoPrecio(TextEditingController ctrl, String label) => TextField(
    controller: ctrl,
    keyboardType: TextInputType.number,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label, labelStyle: const TextStyle(color: Colors.white54),
      prefixText: 'S/. ', prefixStyle: const TextStyle(color: Colors.teal),
      filled: true, fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
  );
}
