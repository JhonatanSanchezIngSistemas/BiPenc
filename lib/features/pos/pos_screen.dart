import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bipenc/data/models/cliente.dart';
import 'package:bipenc/features/pos/pos_provider.dart';
import 'package:bipenc/services/identidad_service.dart';
import 'package:bipenc/services/print_service.dart';
import 'package:bipenc/services/session_service.dart';
import 'package:bipenc/utils/app_logger.dart';
import 'package:bipenc/widgets/scanner_modal.dart';
import 'package:bipenc/widgets/printer_status_indicator.dart';
import 'package:bipenc/data/models/venta.dart';
import 'package:bipenc/services/config_service.dart';
import 'package:bipenc/services/pdf_service.dart';
import 'package:bipenc/widgets/modals/product_detail_modal.dart';
import '../../services/despacho_service.dart';
import '../../widgets/conectividad_indicador.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});
  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _searchCtrl = TextEditingController();
  List<Producto> _resultados = [];
  bool _buscando = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    Future.microtask(_mostrarBienvenidaPrimeraVez);
  }

  Future<void> _mostrarBienvenidaPrimeraVez() async {
    User? user;
    try {
      user = Supabase.instance.client.auth.currentUser;
    } catch (_) {
      // Widget tests o entorno sin Supabase inicializado.
      return;
    }
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final key = 'welcome_pending_${user.id}';
    final pending = prefs.getBool(key) ?? false;
    if (!pending || !mounted) return;

    final perfil = await SessionService().obtenerPerfil(forceRefresh: true);
    final nombre = (perfil?.nombre.trim().isNotEmpty == true)
        ? perfil!.nombre.trim()
        : (user.email?.split('@').first ?? 'Usuario');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bienvenido a BiPenc, $nombre'),
        backgroundColor: Colors.teal,
        duration: const Duration(seconds: 3),
      ),
    );
    await prefs.setBool(key, false);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _buscarDebounced(String query, PosProvider pos) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _buscar(query, pos);
    });
  }

  Future<void> _buscar(String query, PosProvider pos) async {
    if (query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _resultados = [];
          _buscando = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _buscando = true);
    final res = await pos.buscarProductos(query);
    if (mounted) {
      setState(() {
        _resultados = res;
        _buscando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PosProvider>(
      builder: (context, pos, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF0F0F1A),
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0D111B),
                  Color(0xFF132033),
                  Color(0xFF0F0F1A)
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // ── Cabecera Personalizada (UX Architect) ─────────────────
                  _CustomPosHeader(pos: pos),

                  // ── Buscador de Productos ─────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      onChanged: (q) => _buscarDebounced(q, pos),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        hintText: 'Buscar por nombre, SKU o marca...',
                        hintStyle: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                        prefixIcon: const Icon(Icons.search,
                            color: Colors.teal, size: 20),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_buscando)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.teal)),
                              ),
                            IconButton(
                              icon: const Icon(Icons.qr_code_scanner,
                                  color: Colors.tealAccent, size: 20),
                              onPressed: () async {
                                final code = await openScanner(context,
                                    title: 'Escanear Producto');
                                if (code != null && context.mounted) {
                                  final p = await pos.buscarProducto(code);
                                  if (p != null) {
                                    pos.agregarProducto(p);
                                  } else {
                                    // Mostrar diálogo de producto no encontrado
                                    if (!context.mounted) return;
                                    final agregarNuevo = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: Colors.grey.shade900,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16)),
                                        title: const Row(children: [
                                          Icon(Icons.search_off,
                                              color: Colors.amber),
                                          SizedBox(width: 8),
                                          Text('Producto no encontrado',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16)),
                                        ]),
                                        content: Text(
                                          'No se encontró ningún producto con el código:\n\n"$code"\n\n¿Deseas agregarlo al inventario?',
                                          style: const TextStyle(
                                              color: Colors.white70),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Cancelar',
                                                style: TextStyle(
                                                    color: Colors.white54)),
                                          ),
                                          FilledButton.icon(
                                            style: FilledButton.styleFrom(
                                                backgroundColor: Colors.teal),
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            icon:
                                                const Icon(Icons.add, size: 16),
                                            label:
                                                const Text('Agregar producto'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (agregarNuevo == true &&
                                        context.mounted) {
                                      final agregado = await context.push<bool>(
                                          '/inventario/nuevo',
                                          extra: {'initialSku': code});
                                      if (agregado == true) {
                                        // Recargar y buscar el producto recién creado
                                        final nuevo =
                                            await pos.buscarProducto(code);
                                        if (nuevo != null) {
                                          pos.agregarProducto(nuevo);
                                        }
                                      }
                                    }
                                  }
                                }
                              },
                            ),
                            if (_searchCtrl.text.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear,
                                    color: Colors.white54, size: 20),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _resultados = []);
                                },
                              ),
                          ],
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.07),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
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
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Colors.white12),
                        itemBuilder: (ctx, i) {
                          final p = _resultados[i];
                          return ListTile(
                            dense: true,
                            title: Text(p.nombre,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13)),
                            subtitle: Text('${p.marca} • ${p.categoria}',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 11)),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('S/.${p.precioBase.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        color: Colors.teal,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                if (p.precioMayorista < p.precioBase)
                                  Text(
                                      'May: S/.${p.precioMayorista.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          color: Colors.amber, fontSize: 10)),
                              ],
                            ),
                            onTap: () {
                              pos.agregarProducto(p);
                              _searchCtrl.clear();
                              setState(() => _resultados = []);
                              HapticFeedback.lightImpact();
                            },
                            onLongPress: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => ProductDetailModal(
                                  producto: p,
                                  onAddWithPresentation: (pres) => pos
                                      .agregarProducto(p, presentacion: pres),
                                  onApplyManualPrice: (precio) async {
                                    await pos.agregarProducto(
                                      p,
                                      presentacion: p.presentaciones.isNotEmpty
                                          ? p.presentaciones.first
                                          : null,
                                    );
                                    if (pos.items.isNotEmpty) {
                                      pos.setPrecioManual(
                                          pos.items.length - 1, precio);
                                    }
                                  },
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),

                  const Divider(
                      height: 1,
                      color: Colors.white12,
                      indent: 12,
                      endIndent: 12),

                  // ── Carrito ───────────────────────────────────────────────────
                  Expanded(
                    child: pos.items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.shopping_cart_outlined,
                                    size: 64, color: Colors.white12),
                                const SizedBox(height: 12),
                                const Text('Carrito vacío',
                                    style: TextStyle(
                                        color: Colors.white24, fontSize: 16)),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: () async {
                                    final code = await openScanner(context,
                                        title: 'Escanear Producto');
                                    if (code != null) {
                                      final p = await pos.buscarProducto(code);
                                      if (!context.mounted) return;
                                      if (p != null) {
                                        pos.agregarProducto(p);
                                      } else {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                'Producto no encontrado: $code'),
                                            backgroundColor: Colors.orange,
                                            action: SnackBarAction(
                                              label: 'Registrar',
                                              onPressed: () =>
                                                  context.push('/inventario'),
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.qr_code_scanner),
                                  label: const Text('ESCANEAR PRODUCTO'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.05),
                                    foregroundColor: Colors.tealAccent,
                                    side: const BorderSide(color: Colors.teal),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                    'Total: S/. ${pos.totalCobrar.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        color: Colors.white12, fontSize: 14)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: pos.items.length,
                            itemBuilder: (ctx, i) => _CartItemTile(
                                index: i, item: pos.items[i], pos: pos),
                          ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: _BottomBar(
            pos: pos,
            onCobrar: () => _iniciarCobro(context, pos),
          ),
        );
      },
    );
  }

  Future<void> _iniciarCobro(BuildContext context, PosProvider pos) async {
    final venta = await showModalBottomSheet<Venta>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _PanelCobro(pos: pos),
    );

    if (venta != null && mounted) {
      _manejarPostVenta(venta, pos);
    }
  }

  Future<void> _manejarPostVenta(Venta venta, PosProvider pos) async {
    try {
      String mensajeLargo = 'Total: S/.${venta.total.toStringAsFixed(2)}\n\n';
      if (venta.synced) {
        mensajeLargo += '✅ Sincronizado con servidor\n';
      } else {
        mensajeLargo +=
            '⚠️ Guardado localmente (sin internet)\nSincronizará automáticamente cuando haya conexión\n';
      }
      mensajeLargo += '¿Imprimir comprobante ahora?';

      final accion = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0F0F1A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(venta.synced ? Icons.check_circle : Icons.cloud_off,
                color: venta.synced ? Colors.tealAccent : Colors.orange),
            const SizedBox(width: 12),
            Text(venta.synced ? '¡Venta Guardada!' : '⚠️ Guardado Offline',
                style: const TextStyle(color: Colors.white)),
          ]),
          content: Text(
            mensajeLargo,
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'skip'),
              child:
                  const Text('OMITIR', style: TextStyle(color: Colors.white38)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, 'pdf'),
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('PDF'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.tealAccent,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(ctx, 'thermal'),
              icon: const Icon(Icons.print, size: 18),
              label: const Text('IMPRIMIR'),
            ),
          ],
        ),
      );

      if (accion == 'thermal' && mounted) {
        final impreso = await PrintService().imprimirComprobante(venta);
        if (!impreso && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(children: [
                Icon(Icons.print_disabled, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                    child:
                        Text('Impresora no conectada. La venta fue guardada.')),
              ]),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else if (accion == 'pdf' && mounted) {
        try {
          final tasa = await ConfigService.obtenerIGVActual();
          final vendedorAlias = await PrintService.obtenerAliasVendedor();
          final pdf = await PdfService.generateVentaPdf(
            items: venta.items,
            total: venta.total,
            vendedor: vendedorAlias,
            correlativo: venta.id,
            cliente: venta.nombreCliente,
            dniRuc: venta.documentoCliente,
            tipo: venta.tipoComprobante == TipoComprobante.factura
                ? 'FACTURA ELECTRÓNICA'
                : 'BOLETA ELECTRÓNICA',
            metodoPago: venta.metodoPago.name,
            montoRecibido: venta.montoRecibido,
            vuelto: venta.vuelto,
            tasaIgv: tasa,
            subtotalSinIgv: venta.operacionGravada,
            igvValue: venta.igv,
          );
          await PdfService.shareVentaPdf(pdf);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('No se pudo generar PDF: $e'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }
      }

      if (!mounted) return;

      // PASO 3: Preguntar por Picking
      await DespachoService().preguntarYAbrirPicking(context, venta);

      // PASO 4: Limpiar carrito
      pos.finalizarVentaYLimpiar();
    } catch (e) {
      AppLogger.error('Error post-venta en UI', tag: 'POS', error: e);
    }
  }
}

// ── Custom Pos Header (UX Architect) ──────────────────────────────────────────
class _CustomPosHeader extends StatelessWidget {
  final PosProvider pos;
  const _CustomPosHeader({required this.pos});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // Chips de Clientes C1-C5
          Expanded(
            child: SizedBox(
              height: 32,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: pos.maxCarritos,
                itemBuilder: (ctx, i) {
                  final isActive = pos.activeCartIndex == i;
                  final isEmpty = pos.isCartEmpty(i);
                  return GestureDetector(
                    onTap: () => pos.cambiarCarrito(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.teal : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color:
                                isActive ? Colors.tealAccent : Colors.white12),
                      ),
                      child: Center(
                        child: Text(
                          'C${i + 1}${!isEmpty ? ' •' : ''}',
                          style: TextStyle(
                            color: isActive ? Colors.black : Colors.white54,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Indicadores y Botón (+)
          const SizedBox(width: 8),
          const PrinterStatusIndicator(),
          const SizedBox(width: 4),
          const ConectividadIndicador(),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, color: Colors.tealAccent, size: 24),
            tooltip: 'Añadir Genérico',
            onPressed: () {
              pos.agregarProductoGenerico();
            },
          ),
        ],
      ),
    );
  }
}

// ── Cart Item Tile ─────────────────────────────────────────────────────────────
class _CartItemTile extends StatelessWidget {
  final int index;
  final ItemCarrito item;
  final PosProvider pos;
  const _CartItemTile(
      {required this.index, required this.item, required this.pos});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('item_${index}_${item.producto.id}'),
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
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          dense: true,
          onLongPress: () => _editarItemCompleto(context),
          title: Text(item.producto.nombre,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          subtitle: Row(
            children: [
              GestureDetector(
                onTap: () => pos.actualizarCantidad(index, -1),
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  child: const Icon(Icons.remove_circle_outline,
                      color: Colors.white38, size: 24),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('${item.cantidad}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              GestureDetector(
                onTap: () => pos.actualizarCantidad(index, 1),
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  child: const Icon(Icons.add_circle_outline,
                      color: Colors.teal, size: 24),
                ),
              ),
              const SizedBox(width: 8),
              // Toggle mayorista (si el producto lo soporta)
              if (item.producto.precioMayorista < item.producto.precioBase)
                GestureDetector(
                  onTap: () => pos.toggleMayorista(index),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.presentacion.id == 'mayo'
                          ? Colors.amber.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: item.presentacion.id == 'mayo'
                              ? Colors.amber
                              : Colors.white24),
                    ),
                    child: Text(
                      item.etiquetaPrecio,
                      style: TextStyle(
                        color: item.presentacion.id == 'mayo'
                            ? Colors.amber
                            : Colors.white38,
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
                    style: const TextStyle(
                        color: Colors.teal,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                Text('@${item.precioActual.toStringAsFixed(2)}',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _editarPrecio(BuildContext context) {
    final ctrl =
        TextEditingController(text: item.precioActual.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Precio Especial',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            prefixText: 'S/. ',
            prefixStyle: TextStyle(color: Colors.teal),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.teal)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.white54))),
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

  void _editarItemCompleto(BuildContext context) {
    if (item.producto.id.startsWith('GEN-')) {
      _mostrarDialogoEdicionGenerico(context);
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ProductDetailModal(
          producto: item.producto,
          onApplyManualPrice: (precio) => pos.setPrecioManual(index, precio),
        ),
      );
    }
  }

  void _mostrarDialogoEdicionGenerico(BuildContext context) {
    final nombreCtrl = TextEditingController(text: item.producto.nombre);
    final precioCtrl =
        TextEditingController(text: item.precioActual.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Editar Producto Rápido',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                  labelText: 'Nombre',
                  labelStyle: TextStyle(color: Colors.white54)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: precioCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Precio',
                labelStyle: TextStyle(color: Colors.white54),
                prefixText: 'S/. ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final p = double.tryParse(precioCtrl.text.replaceAll(',', '.'));
              if (p != null) {
                pos.editarItemGenerico(index, nombreCtrl.text.trim(), p);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

// ── Bottom Bar ────────────────────────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  final PosProvider pos;
  final VoidCallback onCobrar;
  const _BottomBar({required this.pos, required this.onCobrar});

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
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11)),
                  Text('S/. ${pos.totalCobrar.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 22)),
                ],
              ),
            ),
            if (pos.items.isNotEmpty)
              TextButton(
                onPressed: () => pos.vaciarCarrito(),
                child: const Text('Limpiar',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: pos.items.isEmpty ? null : onCobrar,
              icon: const Icon(Icons.point_of_sale),
              label: const Text('COBRAR',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
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
  String? _nombreCliente;
  bool _buscandoCliente = false;
  bool _isProcessing = false;

  String _sanitizeDocumento(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9]'), '');
  }

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
    setState(() {
      _buscandoCliente = true;
      _nombreCliente = null;
    });
    final nombre = await IdentidadService.consultarDocumento(doc, esRuc);
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
    if (_isProcessing) return;

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

    setState(() => _isProcessing = true);

    try {
      final docLimpio = _sanitizeDocumento(_docCtrl.text);
      if (docLimpio.isNotEmpty &&
          docLimpio.length != 8 &&
          docLimpio.length != 11) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento inválido: usa 8 dígitos (DNI) o 11 (RUC)'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _isProcessing = false);
        return;
      }
      final venta = await widget.pos.procesarVenta(
        tipo: docLimpio.length == 11
            ? TipoComprobante.factura
            : TipoComprobante.boleta,
        docCliente: docLimpio.isNotEmpty ? docLimpio : null,
        nombreCliente: _nombreCliente,
      );

      if (venta == null) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      if (mounted) {
        // Retornar la venta al modal para que el flujo siga en el context principal
        Navigator.pop(context, venta);
      }
    } catch (e) {
      AppLogger.error('Error al procesar cobro: $e', tag: 'POS');
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al procesar: $e'),
              backgroundColor: Colors.red),
        );
      }
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
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),

            Text('Total: S/.${pos.totalCobrar.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Método de pago
            Row(
              children: MetodoPago.values.map((m) {
                final labels = {
                  MetodoPago.efectivo: '💵 Efectivo',
                  MetodoPago.yapePlin: '📱 Yape/Plin',
                  MetodoPago.tarjeta: '💳 Tarjeta'
                };
                final isActive = pos.metodoPago == m;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      pos.setMetodoPago(m);
                      setState(() {});
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.teal
                            : Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color:
                                isActive ? Colors.tealAccent : Colors.white12),
                      ),
                      child: Text(labels[m]!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: isActive ? Colors.black : Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // QR de Yape (Constitución Art 4)
            if (pos.metodoPago == MetodoPago.yapePlin)
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12)),
                  child: Image.network(
                    'https://upload.wikimedia.org/wikipedia/commons/d/d0/QR_code_for_mobile_English_Wikipedia.svg', // Placeholder QR
                    width: 150,
                    height: 150,
                    errorBuilder: (_, __, ___) => const Icon(Icons.qr_code_2,
                        size: 100, color: Colors.teal),
                  ),
                ),
              ),

            // Monto recibido (solo efectivo)
            if (pos.metodoPago == MetodoPago.efectivo) ...[
              TextField(
                controller: _montoCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white, fontSize: 20),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Monto recibido',
                  labelStyle: TextStyle(color: Colors.white54),
                  prefixText: 'S/. ',
                  prefixStyle: TextStyle(
                      color: Colors.teal,
                      fontWeight: FontWeight.bold,
                      fontSize: 20),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.teal)),
                ),
              ),
              if (vuelto > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Vuelto:',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 16)),
                      Text('S/.${vuelto.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
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
                    maxLength: 11,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'DNI / RUC (opcional)',
                      hintStyle:
                          const TextStyle(color: Colors.white24, fontSize: 12),
                      prefixIcon: const Icon(Icons.person_search,
                          color: Colors.white38, size: 18),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      counterText: '',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buscandoCliente
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                            color: Colors.teal, strokeWidth: 2))
                    : IconButton(
                        icon: const Icon(Icons.search, color: Colors.teal),
                        onPressed: () {
                          final doc = _sanitizeDocumento(_docCtrl.text);
                          if (doc.length == 8 || doc.length == 11) {
                            _buscarCliente(doc, doc.length == 11);
                          } else if (doc.isNotEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Ingresa un DNI (8) o RUC (11) válido'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        },
                      ),
              ],
            ),
            if (_nombreCliente != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('👤 $_nombreCliente',
                    style: const TextStyle(
                        color: Colors.tealAccent, fontSize: 12)),
              ),
            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: _cobrar,
              icon: const Icon(Icons.check_circle),
              label: const Text('CONFIRMAR COBRO',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
