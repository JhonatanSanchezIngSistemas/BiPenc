import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:bipenc/data/models/producto.dart';
import 'package:bipenc/services/local_db_service.dart';
import 'package:bipenc/services/supabase_service.dart';
import 'package:bipenc/utils/app_logger.dart';
import '../../widgets/conectividad_indicador.dart';
import '../../widgets/common/robust_image.dart';
import '../../widgets/modals/product_detail_modal.dart';

import 'package:bipenc/widgets/scanner_modal.dart';

class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key});

  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  List<Producto> _productosBase = [];
  List<Producto> _productosFiltrados = [];
  final TextEditingController _searchController = TextEditingController();
  String _filtroActivo = 'Todos';
  List<String> _filtrosDinamicos = const ['Todos'];

  @override
  void initState() {
    super.initState();
    _cargarProductos();
    _sincronizar();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _sincronizar() async {
    try {
      // Sincronización proactiva (Fix #2)
      await SupabaseService.sincronizarProductos();
      if (mounted) {
        await _cargarProductos();
      }
    } catch (e) {
      AppLogger.error('Error sincronizando inventario',
          tag: 'INVENTARIO', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('No se pudo sincronizar ahora. Mostrando datos locales.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _cargarProductos() async {
    try {
      final prods = await LocalDbService.buscarLocal(
          ''); // Vacío trae todos (o top según service)
      if (mounted) {
        setState(() {
          _productosBase = prods;
          _reconstruirFiltros(prods);
          _productosFiltrados = _aplicarFiltros(prods, _searchController.text);
        });
      }
    } catch (e) {
      AppLogger.error('Error cargando inventario local',
          tag: 'INVENTARIO', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error cargando productos locales'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  List<Producto> _aplicarFiltros(List<Producto> base, String query) {
    final busqueda = query.toLowerCase();
    final filtro = _filtroActivo.toLowerCase();
    final filtrados = base.where((prod) {
      if (_filtroActivo != 'Todos') {
        if (_filtroActivo.startsWith('#')) {
          final token = filtro.replaceFirst('#', '');
          if (!prod.nombre.toLowerCase().contains(token) &&
              !prod.categoria.toLowerCase().contains(token)) {
            return false;
          }
        } else if (prod.categoria.toLowerCase() != filtro) {
          return false;
        }
      }
      if (busqueda.isEmpty) return true;
      return prod.nombre.toLowerCase().contains(busqueda) ||
          prod.skuCode.toLowerCase().contains(busqueda) ||
          prod.id.toLowerCase().contains(busqueda) ||
          prod.marca.toLowerCase().contains(busqueda);
    }).toList();
    return filtrados.take(20).toList();
  }

  void _reconstruirFiltros(List<Producto> productos) {
    final categorias = <String>{};
    final tokenCount = <String, int>{};
    const stopWords = {
      'de',
      'del',
      'la',
      'el',
      'los',
      'las',
      'para',
      'con',
      'sin',
      'y',
      'en',
      'por',
      'un',
      'una',
      'x',
      'ml',
      'gr',
      'kg',
      'cm'
    };

    for (final p in productos) {
      final categoria = p.categoria.trim();
      if (categoria.isNotEmpty) categorias.add(categoria);

      final words = p.nombre
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9áéíóúñ ]'), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 4 && !stopWords.contains(w));
      for (final w in words) {
        tokenCount[w] = (tokenCount[w] ?? 0) + 1;
      }
    }

    final topTokens = tokenCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final tags = topTokens.take(5).map((e) => '#${e.key}');

    _filtrosDinamicos = [
      'Todos',
      ...categorias.toList()..sort(),
      ...tags,
    ];
    if (!_filtrosDinamicos.contains(_filtroActivo)) {
      _filtroActivo = 'Todos';
    }
  }

  void _filtrarInventario(String query) {
    setState(() {
      _productosFiltrados = _aplicarFiltros(_productosBase, query);
    });
  }

  Future<void> _abrirEditor(Producto producto) async {
    final res = await context.push<bool>('/inventario/editar', extra: producto);
    if (res == true) _cargarProductos();
  }

  Future<void> _confirmarEliminar(Producto producto) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Eliminar Producto', style: TextStyle(color: Colors.white))
          ],
        ),
        content: Text(
            '¿Seguro que deseas borrar "${producto.nombre}"?\nID: ${producto.id}\n\nEsta acción es irreversible.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.white54))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado == true) {
      try {
        await LocalDbService.eliminarProducto(producto.id,
            sku: producto.skuCode);
        await _cargarProductos();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ "${producto.nombre}" eliminado')),
          );
        }
      } catch (e) {
        AppLogger.error('Error eliminando producto',
            tag: 'INVENTARIO', error: e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo eliminar el producto'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121B2B),
        actions: const [
          ConectividadIndicador(),
        ],
        title: TextField(
          controller: _searchController,
          onChanged: _filtrarInventario,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Buscar por nombre, SKU o marca...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            border: InputBorder.none,
            icon: IconButton(
              icon: const Icon(Icons.qr_code_scanner, color: Colors.teal),
              onPressed: () async {
                final code =
                    await openScanner(context, title: 'Escanear para filtrar');
                if (code != null) {
                  _searchController.text = code;
                  _filtrarInventario(code);
                }
              },
            ),
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
              children: _filtrosDinamicos.map((cat) {
                final activo = _filtroActivo == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: cat != 'Todos'
                        ? Icon(
                            cat.startsWith('#')
                                ? Icons.local_offer_outlined
                                : Icons.folder_open_outlined,
                            size: 16,
                            color: activo ? Colors.black : Colors.teal.shade300,
                          )
                        : null,
                    label: Text(cat,
                        style: TextStyle(
                          color: activo ? Colors.black : Colors.teal.shade300,
                          fontWeight:
                              activo ? FontWeight.bold : FontWeight.normal,
                        )),
                    selected: activo,
                    selectedColor: Colors.teal.shade400,
                    backgroundColor: Colors.grey.shade800,
                    checkmarkColor: Colors.black,
                    side: BorderSide(
                        color:
                            activo ? Colors.teal.shade400 : Colors.transparent),
                    onSelected: (_) {
                      setState(() {
                        _filtroActivo =
                            activo && cat != 'Todos' ? 'Todos' : cat;
                        _productosFiltrados = _aplicarFiltros(
                            _productosBase, _searchController.text);
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: SupabaseService.client
            .from('productos')
            .stream(primaryKey: ['id']).order('nombre'),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            if (_productosFiltrados.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off,
                          color: Colors.orangeAccent, size: 42),
                      SizedBox(height: 10),
                      Text(
                        'Sin internet. Mostrando datos locales.',
                        style: TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              _productosBase.isEmpty) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.teal));
          }

          if (snapshot.hasData) {
            // Actualizar cache local silenciosamente (Mission CTO: Real-time Sync)
            final List<Map<String, dynamic>> raw = snapshot.data!;
            // Importante: si nube devuelve vacío, NO pisar caché local.
            if (raw.isNotEmpty) {
              final List<Producto> updatedProds =
                  raw.map((row) => SupabaseService.mapToProducto(row)).toList();
              _reconstruirFiltros(updatedProds);

              if (_searchController.text.isEmpty && _filtroActivo == 'Todos') {
                _productosBase = updatedProds;
                _productosFiltrados = updatedProds.take(20).toList();
              } else {
                _productosBase = updatedProds;
                _productosFiltrados =
                    _aplicarFiltros(updatedProds, _searchController.text);
              }
            }
          }

          if (_productosFiltrados.isEmpty) {
            return _searchController.text.isEmpty
                ? _buildEmptyState()
                : const Center(
                    child: Text('No se encontraron coincidencias',
                        style: TextStyle(color: Colors.white24)));
          }

          final double totalInventario = _productosFiltrados.fold(
            0,
            (s, p) => s + p.precioBase,
          );
          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF131D2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    _MiniMetric(
                      label: 'Mostrando',
                      value: '${_productosFiltrados.length}',
                      color: Colors.tealAccent,
                    ),
                    const SizedBox(width: 12),
                    _MiniMetric(
                      label: 'Catálogo',
                      value: '${_productosBase.length}',
                      color: Colors.cyanAccent,
                    ),
                    const SizedBox(width: 12),
                    _MiniMetric(
                      label: 'Suma Base',
                      value: 'S/.${totalInventario.toStringAsFixed(1)}',
                      color: Colors.amberAccent,
                    ),
                  ],
                ),
              ),
              if (snapshot.hasError)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Colors.orange.withValues(alpha: 0.15),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_off,
                          size: 14, color: Colors.orangeAccent),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Modo offline: usando inventario local',
                          style: TextStyle(
                              color: Colors.orangeAccent, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_productosBase.length > 20 &&
                  _searchController.text.isEmpty &&
                  _filtroActivo == 'Todos')
                Container(
                  padding: const EdgeInsets.all(8),
                  width: double.infinity,
                  color: Colors.teal.withValues(alpha: 0.1),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: Colors.tealAccent),
                      SizedBox(width: 8),
                      Text(
                          'Sincronizado en tiempo real. Mostrando top 20 más recientes.',
                          style: TextStyle(
                              color: Colors.tealAccent, fontSize: 11)),
                    ],
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _sincronizar,
                  color: Colors.teal,
                  backgroundColor: Colors.grey.shade900,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    physics: const AlwaysScrollableScrollPhysics(),
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
              ),
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'fullAdd',
            backgroundColor: Colors.teal,
            foregroundColor: Colors.black,
            onPressed: () async {
              final res = await context.push<bool>('/inventario/nuevo');
              if (res == true) _cargarProductos();
            },
            icon: const Icon(Icons.add),
            label: const Text('Completo',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 80, color: Colors.white12),
            SizedBox(height: 24),
            Text('Sin productos registrados',
                style: TextStyle(fontSize: 18, color: Colors.white54)),
            SizedBox(height: 12),
            Text('Usa "Completo" para registrar el primer producto.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white24, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniMetric(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ProductoCard extends StatelessWidget {
  final Producto producto;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;

  const _ProductoCard(
      {required this.producto,
      required this.onEditar,
      required this.onEliminar});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => ProductDetailModal(
            producto: producto,
            readOnly: true,
          ),
        );
      },
      child: Card(
        color: Colors.grey.shade900,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: RobustImage(
            imagePath: producto.imagenPath,
            width: 40,
            height: 40,
            borderRadius: BorderRadius.circular(8),
          ),
          title: Text(producto.nombre,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.white)),
          subtitle: Text('${producto.marca} | ${producto.id}',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('S/.${producto.precioBase.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.teal, fontWeight: FontWeight.bold)),
                  if (producto.precioMayorista < producto.precioBase)
                    Text(
                        'May: S/.${producto.precioMayorista.toStringAsFixed(2)}',
                        style:
                            const TextStyle(color: Colors.amber, fontSize: 10)),
                ],
              ),
              IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      size: 20, color: Colors.white54),
                  onPressed: onEditar),
              IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: Colors.redAccent),
                  onPressed: onEliminar),
            ],
          ),
        ),
      ),
    );
  }
}

// Eliminado _EditarProductoSheet legacy
