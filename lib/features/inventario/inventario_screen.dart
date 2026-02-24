import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import '../../data/models/product.dart';
import '../../data/local/db_helper.dart';

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
  String _filtroActivo = 'Todos'; // Control del CHIP activo

  @override
  void initState() {
    super.initState();
    _cargarProductos();
  }

  Future<void> _cargarProductos() async {
    setState(() => _isLoading = true);
    final prods = await DBHelper().getAllProducts();
    setState(() {
      _productosBase = prods;
      _productosFiltrados = prods;
      _isLoading = false;
    });
  }

  void _filtrarInventario(String query) {
    final busqueda = query.toLowerCase();
    setState(() {
      _productosFiltrados = _productosBase.where((prod) {
        // 1. Filtro por Chip de Categoría/Marca rápida
        final pasaFiltroChip = _filtroActivo == 'Todos' || 
            prod.marca.toLowerCase() == _filtroActivo.toLowerCase() ||
            (prod.descripcion.toLowerCase().contains(_filtroActivo.toLowerCase()));
        
        if (!pasaFiltroChip) return false;

        // 2. Filtro por texto en el SearchBar
        if (busqueda.isEmpty) return true;

        return prod.descripcion.toLowerCase().contains(busqueda) ||
            prod.codigoBarras.contains(busqueda) ||
            prod.marca.toLowerCase().contains(busqueda);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          onChanged: _filtrarInventario,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Buscar por nombre, código o marca...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            border: InputBorder.none,
            icon: const Icon(Icons.search, color: Colors.white),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear, color: Colors.white),
              onPressed: () {
                _searchController.clear();
                _filtrarInventario('');
              },
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Carrusel de Filtros Rápidos (Chips)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              children: ['Todos', 'Faber-Castell', 'Standford', 'Cuadernos', 'Arte']
                  .map((filtro) => Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(filtro),
                          selected: _filtroActivo == filtro,
                          onSelected: (bool selected) {
                            setState(() {
                              _filtroActivo = selected ? filtro : 'Todos';
                            });
                            _filtrarInventario(_searchController.text);
                          },
                          selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                          checkmarkColor: Theme.of(context).primaryColor,
                        ),
                      ))
                  .toList(),
            ),
          ),
          const Divider(height: 1),
          // Lista de Productos
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _productosFiltrados.isEmpty && _productosBase.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 100, color: Theme.of(context).primaryColor.withValues(alpha: 0.5)),
                          const SizedBox(height: 24),
                          Text('¡BiPenc está listo!', 
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)
                          ),
                          const SizedBox(height: 12),
                          const Text('Comienza agregando tu primer producto usando el botón en la parte inferior.', 
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.black54)
                          ),
                        ],
                      ),
                    ),
                  )
                : _productosFiltrados.isEmpty 
                  ? const Center(child: Text('No se encontraron coincidencias.'))
                  : ListView.builder(
                    padding: const EdgeInsets.all(12.0),
                    itemCount: _productosFiltrados.length,
                    cacheExtent: 1000, 
                    itemBuilder: (context, index) {
                      final prod = _productosFiltrados[index];
                      return _ProductoDynamicCard(producto: prod);
                    },
                  ),
          ),
        ],
      ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final res = await context.push<bool>('/inventario/nuevo');
          if (res == true) {
            _cargarProductos(); // Refresca la lista automáticamente si creamos uno
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Producto'),
      ),
    );
  }
}

class _ProductoDynamicCard extends StatelessWidget {
  final Product producto;
  const _ProductoDynamicCard({required this.producto});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: ExpansionTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 50,
            height: 50,
            color: Colors.grey.shade200,
            child: producto.imagenUrl != null && producto.imagenUrl!.isNotEmpty
              ? Image.file(File(producto.imagenUrl!), fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.broken_image))
              : CachedNetworkImage(
                  imageUrl: 'https://via.placeholder.com/150/EEEEEE/999999?text=IMG', // Placeholder temporal
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (context, url, error) => const Icon(Icons.image_not_supported, color: Colors.grey),
                ),
          ),
        ),
        title: Text(
          producto.descripcion,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          '${producto.marca} • CB: ${producto.codigoBarras}\nPresentaciones: ${producto.presentaciones.length}',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        children: producto.presentaciones.map((pres) {
          return ListTile(
            dense: true,
            title: Text(pres.nombre),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'U: \$${pres.precioUnitario.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (pres.precioMayor > 0 && pres.esPrecioMayorValido)
                  Text(
                    'M(3+): \$${pres.precioMayor.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.green, fontSize: 12),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
