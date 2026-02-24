import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/producto.dart';
import '../services/local_db_service.dart';
import '../services/supabase_service.dart';
import '../repositories/producto_repository.dart';
import '../utils/app_logger.dart';
import '../utils/precio_engine.dart';

/// Pantalla de inicio con Top 10 inteligente desde caché local.
/// Orden de prioridad: 1. Más vendidos, 2. Última venta, 3. Más nuevos.
class HomePage extends StatefulWidget {
  final Perfil? perfil;
  final void Function(Producto, int, Presentacion) onAgregar;

  const HomePage({
    super.key,
    required this.perfil,
    required this.onAgregar,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Producto> _top10 = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  int _totalEnCache = 0;

  @override
  void initState() {
    super.initState();
    _cargarTop10();
    _sincronizarEnBackground();
  }

  // Carga instantánea desde SQLite local
  Future<void> _cargarTop10() async {
    setState(() => _isLoading = true);
    try {
      final productos = await LocalDbService.obtenerTop10();
      final total = await LocalDbService.contarProductos();
      setState(() {
        _top10 = productos;
        _totalEnCache = total;
      });
    } catch (e) {
      AppLogger.error('Error cargando Top 10', tag: 'HOME', error: e);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Sincroniza con Supabase en segundo plano (solo si hay internet)
  Future<void> _sincronizarEnBackground() async {
    setState(() => _isSyncing = true);
    final ok = await SupabaseService.sincronizarProductos();
    if (ok) await _cargarTop10(); // Refrescar con datos nuevos
    await SupabaseService.subirVentasPendientes();
    if (mounted) setState(() => _isSyncing = false);
  }

  // Pull-to-refresh manual
  Future<void> _onRefresh() async {
    await _sincronizarEnBackground();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Top Productos',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$_totalEnCache productos en catálogo',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (_isSyncing)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Colors.tealAccent.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Sincronizando',
                        style: TextStyle(
                          color: Colors.tealAccent.withOpacity(0.6),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // ── Grid Top 10 ──
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.tealAccent))
              : _top10.isEmpty
                  ? _buildEmptyCache()
                  : RefreshIndicator(
                      onRefresh: _onRefresh,
                      color: Colors.tealAccent,
                      backgroundColor: const Color(0xFF1E1E2C),
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _top10.length,
                        itemBuilder: (context, index) {
                          return _ProductoCard(
                            producto: _top10[index],
                            rank: index + 1,
                            onAgregar: widget.onAgregar,
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyCache() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey.shade800),
          const SizedBox(height: 16),
          Text(
            'Sin datos locales aún.\nDesliza hacia abajo para sincronizar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _onRefresh,
            icon: const Icon(Icons.sync),
            label: const Text('Sincronizar ahora'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.tealAccent.withOpacity(0.1),
              foregroundColor: Colors.tealAccent,
              side: BorderSide(color: Colors.tealAccent.withOpacity(0.5)),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Card de producto para el grid
// ──────────────────────────────────────────────
class _ProductoCard extends StatefulWidget {
  final Producto producto;
  final int rank;
  final void Function(Producto, int, Presentacion) onAgregar;

  const _ProductoCard({
    required this.producto,
    required this.rank,
    required this.onAgregar,
  });

  @override
  State<_ProductoCard> createState() => _ProductoCardState();
}

class _ProductoCardState extends State<_ProductoCard> {
  late int _cantidadSeleccionada;
  late Presentacion _presentacionSeleccionada;

  @override
  void initState() {
    super.initState();
    _cantidadSeleccionada = 1;
    _presentacionSeleccionada = widget.producto.presentaciones.firstWhere(
      (p) => p.id == 'unid',
      orElse: () => widget.producto.presentaciones.isNotEmpty 
          ? widget.producto.presentaciones.first 
          : Presentacion.unidad,
    );
  }

  IconData _iconoCategoria(String cat) {
    switch (cat) {
      case 'Cuadernos':
        return Icons.menu_book_rounded;
      case 'Lapiceros':
        return Icons.edit;
      case 'Arte':
        return Icons.palette;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isTop3 = widget.rank <= 3;
    final sku = widget.producto.id;
    final escalas = PrecioEngine.getPresentaciones(sku);
    final unidadPrice = widget.producto.presentaciones.firstWhere((p) => p.id == 'unid', orElse: () => Presentacion.unidad).precio;

    final resultado = PrecioEngine.calcularPrecio(
      sku: sku,
      cantidad: _cantidadSeleccionada,
      precioBase: unidadPrice,
    );

    return Material(
      color: const Color(0xFF1E1E2C),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => widget.onAgregar(widget.producto, _cantidadSeleccionada, _presentacionSeleccionada),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Portada ──
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 110,
                      width: double.infinity,
                      color: Colors.tealAccent.withOpacity(0.06),
                      child: widget.producto.imagenPath != null &&
                              widget.producto.imagenPath!.startsWith('http')
                          ? CachedNetworkImage(
                              imageUrl: widget.producto.imagenPath!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.tealAccent,
                                ),
                              ),
                              errorWidget: (_, __, ___) => Icon(
                                _iconoCategoria(widget.producto.categoria),
                                color: Colors.tealAccent.withOpacity(0.5),
                                size: 40,
                              ),
                            )
                          : Icon(
                              _iconoCategoria(widget.producto.categoria),
                              color: Colors.tealAccent.withOpacity(0.5),
                              size: 40,
                            ),
                    ),
                  ),
                  // Badge Top 3 🔥
                  if (isTop3)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.rank == 1 ? '🔥 #1' : '🔥 #${widget.rank}',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.black),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // ── Nombre ──
              Text(
                widget.producto.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    widget.producto.marca,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                  ),
                  const SizedBox(width: 4),
                  _buildTierBadge(widget.producto.marca),
                ],
              ),
              const SizedBox(height: 6),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: widget.producto.presentaciones.map((p) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _buildChoiceChip(p.nombre.substring(0, 1), p),
                    );
                  }).toList(),
                ),
              ),
              if (escalas.length > 1) 
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: escalas.where((e) => e.nombre != 'Unidad').map((e) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: GestureDetector(
                            onTap: () => setState(() => _cantidadSeleccionada = e.minCantidad),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: _cantidadSeleccionada == e.minCantidad 
                                    ? Colors.orangeAccent.withOpacity(0.2) 
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('x${e.minCantidad}', style: const TextStyle(fontSize: 8, color: Colors.orangeAccent)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              const Spacer(),

              // ── Precio + botón ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'S/ ${_getPrecioActual().toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        _getLabelPresentacion(),
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 9),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => widget.onAgregar(widget.producto, _cantidadSeleccionada, _presentacionSeleccionada),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.tealAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.tealAccent.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.add,
                          color: Colors.tealAccent, size: 16),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceChip(String label, Presentacion p) {
    final isSelected = _presentacionSeleccionada.id == p.id;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 8)),
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _presentacionSeleccionada = p);
      },
      selectedColor: Colors.tealAccent.withOpacity(0.2),
      backgroundColor: Colors.transparent,
      labelStyle: TextStyle(
        color: isSelected ? Colors.tealAccent : Colors.grey,
        fontSize: 8,
      ),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide(
          color: isSelected ? Colors.tealAccent : Colors.grey.shade800),
    );
  }

  double _getPrecioActual() {
    return _presentacionSeleccionada.precio;
  }

  String _getLabelPresentacion() {
    return _presentacionSeleccionada.nombre;
  }

  Widget _buildTierBadge(String marca) {
    final tier = PrecioEngine.getTier(marca);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
      decoration: BoxDecoration(
        color: Color(int.parse(tier.hexColor.replaceFirst('#', '0xFF'))).withOpacity(0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        tier.label.toUpperCase(),
        style: TextStyle(
          fontSize: 7,
          fontWeight: FontWeight.bold,
          color: Color(int.parse(tier.hexColor.replaceFirst('#', '0xFF'))),
        ),
      ),
    );
  }
}
