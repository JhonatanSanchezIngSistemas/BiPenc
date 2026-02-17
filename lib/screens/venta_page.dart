import 'package:flutter/material.dart';
import '../models/producto.dart';
import '../widgets/producto_card.dart';
import '../services/supabase_service.dart';

/// Pantalla principal de venta con búsqueda y agrupación inteligente por marca.
class VentaPage extends StatefulWidget {
  const VentaPage({super.key});

  @override
  State<VentaPage> createState() => _VentaPageState();
}

class _VentaPageState extends State<VentaPage> {
  final TextEditingController _searchController = TextEditingController();
  final List<ItemCarrito> _carrito = [];
  List<Producto> _productosCloud = [];
  bool _isLoading = false;
  String _query = '';

  Future<void> _onSearchChanged(String val) async {
    setState(() {
      _query = val;
    });

    if (val.length < 3) {
      setState(() => _productosCloud = []);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final results = await SupabaseService.buscarProductos(val);
      setState(() => _productosCloud = results);
    } catch (e) {
      print('Búsqueda fallida: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Agrupa los productos por marca.
  Map<String, List<Producto>> get _agrupadosPorMarca {
    final map = <String, List<Producto>>{};
    for (final p in _productosCloud) {
      map.putIfAbsent(p.marca, () => []).add(p);
    }
    return map;
  }

  void _agregarAlCarrito(Producto producto) {
    setState(() {
      final existente = _carrito.indexWhere(
          (i) => i.producto.id == producto.id);
      if (existente >= 0) {
        _carrito[existente].cantidad++;
      } else {
        _carrito.add(ItemCarrito(producto: producto));
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${producto.nombre} agregado'),
        backgroundColor: const Color(0xFF2ECC71),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  int get _totalItems =>
      _carrito.fold<int>(0, (sum, item) => sum + item.cantidad);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grupos = _agrupadosPorMarca;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Text('BiPenc',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: Colors.tealAccent)),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.person_outline, color: Colors.grey),
            tooltip: 'Perfil',
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Barra de búsqueda ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar producto (mín. 3 letras)',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                prefixIcon:
                    Icon(Icons.search, color: Colors.grey.shade500),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        color: Colors.grey,
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1E1E2C),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: Colors.tealAccent, width: 1.5),
                ),
              ),
            ),
          ),

          // ── Contenido ──
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
                : _query.length < 3
                    ? _buildEmptyState()
                    : _productosCloud.isEmpty
                        ? _buildNoResults()
                        : _buildGroupedList(grupos),
          ),
        ],
      ),

      // ── Botones Flotantes ──
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Botón Nuevo Producto
          FloatingActionButton(
            heroTag: 'add_product',
            onPressed: () async {
              final result =
                  await Navigator.pushNamed(context, '/producto_form');
              if (result == true) {
                setState(() {}); // Refrescar lista con nuevo producto
              }
            },
            backgroundColor: Colors.tealAccent,
            child: const Icon(Icons.add, color: Colors.black),
          ),

          if (_carrito.isNotEmpty) ...[
            const SizedBox(height: 16),
            // Botón Carrito
            FloatingActionButton.extended(
              heroTag: 'cart',
              onPressed: () async {
                await Navigator.pushNamed(
                  context,
                  '/carrito',
                  arguments: _carrito,
                );
                setState(() {}); // Refrescar badge al volver
              },
              backgroundColor: Colors.tealAccent,
              foregroundColor: Colors.black,
              icon: Badge(
                label: Text('$_totalItems',
                    style: const TextStyle(color: Colors.white, fontSize: 10)),
                backgroundColor: Colors.redAccent,
                child: const Icon(Icons.shopping_cart_outlined,
                    color: Colors.black),
              ),
              label: Text('Carrito ($_totalItems)'),
            ),
          ],
        ],
      ),
    );
  }

  // ── Estado vacío ──
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey.shade800),
          const SizedBox(height: 16),
          Text(
            'Escribe al menos 3 letras\npara buscar productos',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Sin resultados ──
  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 64, color: Colors.grey.shade800),
          const SizedBox(height: 16),
          Text(
            'No se encontraron productos\npara "$_query"',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Lista agrupada por marca ──
  Widget _buildGroupedList(Map<String, List<Producto>> grupos) {
    return CustomScrollView(
      slivers: grupos.entries.map((entry) {
        return SliverMainAxisGroup(
          slivers: [
            // Header de marca (sticky)
            SliverPersistentHeader(
              pinned: true,
              delegate: _MarcaHeaderDelegate(entry.key),
            ),
            // Productos de esa marca
            SliverList.builder(
              itemCount: entry.value.length,
              itemBuilder: (context, index) {
                final producto = entry.value[index];
                return ProductoCard(
                  producto: producto,
                  onAgregar: () => _agregarAlCarrito(producto),
                );
              },
            ),
          ],
        );
      }).toList(),
    );
  }
}

/// Delegate para el header sticky de marca.
class _MarcaHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String marca;
  _MarcaHeaderDelegate(this.marca);

  @override
  double get minExtent => 40;
  @override
  double get maxExtent => 40;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFF0F0F1A),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        marca,
        style: const TextStyle(
          color: Colors.tealAccent,
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _MarcaHeaderDelegate oldDelegate) =>
      marca != oldDelegate.marca;
}
