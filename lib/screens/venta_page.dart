import 'package:flutter/material.dart';
import '../models/producto.dart';
import '../widgets/producto_card.dart';
import '../repositories/producto_repository.dart';
import '../services/session_service.dart';
import '../services/carrito_service.dart';
import '../utils/app_logger.dart';
import 'home_page.dart';

/// Pantalla principal de venta con búsqueda y agrupación por marca.
/// Usa SessionService para el perfil y CarritoService para el carrito.
class VentaPage extends StatefulWidget {
  const VentaPage({super.key});

  @override
  State<VentaPage> createState() => _VentaPageState();
}

class _VentaPageState extends State<VentaPage> {
  final TextEditingController _searchController = TextEditingController();
  final _repo = ProductoRepository();
  final _session = SessionService();
  final _carrito = CarritoService();

  List<Producto> _productosCloud = [];
  bool _isLoading = false;
  String _query = '';
  bool _isLoadingPerfil = true;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    setState(() => _isLoadingPerfil = true);
    await _session.obtenerPerfil();
    if (mounted) setState(() => _isLoadingPerfil = false);
  }

  Future<void> _onSearchChanged(String val) async {
    setState(() => _query = val);

    if (val.isEmpty) {
      setState(() => _productosCloud = []);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final results = await _repo.buscar(val);
      if (mounted) setState(() => _productosCloud = results);
    } catch (e) {
      AppLogger.error('Búsqueda fallida', tag: 'VENTA', error: e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, List<Producto>> get _agrupadosPorMarca {
    final map = <String, List<Producto>>{};
    for (final p in _productosCloud) {
      map.putIfAbsent(p.marca, () => []).add(p);
    }
    return map;
  }

  void _agregarAlCarrito(Producto producto, int cantidad, {Presentacion presentacion = Presentacion.unidad}) {
    _carrito.agregar(producto, cantidad, presentacion);
    final label = cantidad > 1 ? '$cantidad × ${producto.nombre}' : producto.nombre;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label agregado al carrito'),
          backgroundColor: const Color(0xFF2ECC71),
          duration: const Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final perfil = _session.perfil;
    final puedeGestionar = _session.puedeGestionarProductos;
    final grupos = _agrupadosPorMarca;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Text(
          'BiPenc',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2, color: Colors.tealAccent),
        ),
        centerTitle: false,
        actions: [
          // Inventario y Auditoría solo para SERVER/ADMIN
          if (_session.puedeAuditaria) ...[
            IconButton(
              onPressed: () => Navigator.pushNamed(context, '/inventario'),
              icon: const Icon(Icons.inventory, color: Colors.tealAccent),
              tooltip: 'Inventario',
            ),
            IconButton(
              onPressed: () => Navigator.pushNamed(context, '/auditoria'),
              icon: const Icon(Icons.admin_panel_settings, color: Colors.orangeAccent),
              tooltip: 'Auditoría',
            ),
          ],
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/about'),
            icon: const Icon(Icons.info_outline, color: Colors.grey),
            tooltip: 'Acerca de',
          ),
          // Chip del alias del usuario
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _isLoadingPerfil
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.tealAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
                      ),
                      child: Text(
                        perfil?.alias ?? '???',
                        style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
            ),
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
                hintText: 'Buscar por nombre, marca o SKU...',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
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
                  borderSide: const BorderSide(color: Colors.tealAccent, width: 1.5),
                ),
              ),
            ),
          ),

          // ── Contenido ──
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
                : _query.isEmpty
                    ? HomePage(
                        perfil: perfil,
                        onAgregar: (p, c, pres) => _agregarAlCarrito(p, c, presentacion: pres),
                      )
                    : _productosCloud.isEmpty
                        ? _buildNoResults()
                        : _buildGroupedList(grupos),
          ),
        ],
      ),

      // ── Botones Flotantes ──
      floatingActionButton: ListenableBuilder(
        listenable: _carrito,
        builder: (_, __) {
          final total = _carrito.totalItems;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Botón Nuevo Producto — solo para SERVER/ADMIN
              if (puedeGestionar)
                FloatingActionButton(
                  heroTag: 'add_product',
                  mini: true,
                  onPressed: () async {
                    final result = await Navigator.pushNamed(context, '/producto_form');
                    if (result == true && mounted) {
                      // Refrescar búsqueda si hay query activo
                      if (_query.isNotEmpty) _onSearchChanged(_query);
                    }
                  },
                  backgroundColor: const Color(0xFF1E1E2C),
                  child: const Icon(Icons.add, color: Colors.tealAccent),
                  tooltip: 'Nuevo Producto',
                ),

              if (total > 0) ...[
                const SizedBox(height: 12),
                // Botón Carrito
                FloatingActionButton.extended(
                  heroTag: 'cart',
                  onPressed: () async {
                    await Navigator.pushNamed(context, '/carrito');
                    // Registrar ventas locales tras navegar al carrito
                    await _repo.registrarVentaLocal(_carrito.snapshot());
                  },
                  backgroundColor: Colors.tealAccent,
                  foregroundColor: Colors.black,
                  icon: Badge(
                    label: Text('$total', style: const TextStyle(color: Colors.white, fontSize: 10)),
                    backgroundColor: Colors.redAccent,
                    child: const Icon(Icons.shopping_cart_outlined, color: Colors.black),
                  ),
                  label: Text('Carrito ($total)', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade800),
          const SizedBox(height: 16),
          Text(
            'No se encontraron productos\npara "$_query"',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          if (_session.puedeGestionarProductos) ...[
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/producto_form'),
              icon: const Icon(Icons.add, color: Colors.tealAccent),
              label: const Text('Agregar este producto', style: TextStyle(color: Colors.tealAccent)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupedList(Map<String, List<Producto>> grupos) {
    return CustomScrollView(
      slivers: grupos.entries.map((entry) {
        return SliverMainAxisGroup(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _MarcaHeaderDelegate(entry.key),
            ),
            SliverList.builder(
              itemCount: entry.value.length,
              itemBuilder: (context, index) {
                return ProductoCard(
                  producto: entry.value[index],
                  onAgregar: (p, c, pres) => _agregarAlCarrito(p, c, presentacion: pres),
                );
              },
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _MarcaHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String marca;
  _MarcaHeaderDelegate(this.marca);

  @override
  double get minExtent => 40;
  @override
  double get maxExtent => 40;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
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
  bool shouldRebuild(covariant _MarcaHeaderDelegate oldDelegate) => marca != oldDelegate.marca;
}
