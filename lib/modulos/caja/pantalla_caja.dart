import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bipenc/modulos/caja/proveedor_caja.dart';
import 'package:bipenc/servicios/servicio_impresion.dart';
import 'package:bipenc/servicios/servicio_sesion.dart';
import 'package:bipenc/utilidades/registro_app.dart';
import 'package:share_plus/share_plus.dart';
import 'package:bipenc/servicios/servicio_pedidos.dart';
import 'package:bipenc/ui/modales/modal_escaner.dart';
import 'package:bipenc/ui/indicador_estado_impresora.dart';
import 'package:bipenc/datos/modelos/venta.dart';
import 'package:bipenc/servicios/servicio_configuracion.dart';
import '../../servicios/servicio_pdf.dart';
import 'package:bipenc/ui/modales/modal_detalle_producto.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../servicios/servicio_despacho.dart';
import 'componentes/seccion_escaneo.dart';
import 'componentes/resumen_carrito.dart';
import 'componentes/selector_pago.dart';
import 'componentes/resolvedor_conflicto_producto.dart';
import 'componentes/hoja_vincular_codigo.dart';

class PantallaCaja extends StatefulWidget {
  final String? orderId;
  final String? orderFotoUrl;
  const PantallaCaja({super.key, this.orderId, this.orderFotoUrl});
  @override
  State<PantallaCaja> createState() => _PantallaCajaState();
}

class _PantallaCajaState extends State<PantallaCaja> {
  final _searchCtrl = TextEditingController();
  List<Producto> _resultados = [];
  bool _buscando = false;
  Timer? _searchDebounce;
  bool _modoEscaneoContinuo = false;
  DateTime? _ultimoScanTs;
  String? _ultimoScanCode;
  final Duration _rafagaCooldown = const Duration(milliseconds: 1700);
  final MobileScannerController _rafagaController = MobileScannerController(
    detectionSpeed: DetectionSpeed.unrestricted,
    returnImage: false,
  );

  @override
  void initState() {
    super.initState();
    Future.microtask(_mostrarBienvenidaPrimeraVez);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pos = context.read<ProveedorCaja>();
      pos.attachOrderLink(orderId: widget.orderId, fotoUrl: widget.orderFotoUrl);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _rafagaController.dispose();
    _modoEscaneoContinuo = false;
    super.dispose();
  }

  Future<void> _mostrarBienvenidaPrimeraVez() async {
    User? user;
    try {
      user = Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return;
    }
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final key = 'welcome_pending_${user.id}';
    final pending = prefs.getBool(key) ?? false;
    if (!pending || !mounted) return;

    final perfil = await ServicioSesion().obtenerPerfil(forceRefresh: true);
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


  void _buscarDebounced(String query, ProveedorCaja pos) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _buscar(query, pos);
    });
  }

  Future<void> _buscar(String query, ProveedorCaja pos) async {
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

  void _onRafagaDetect(BarcodeCapture capture, ProveedorCaja pos) async {
    if (!_modoEscaneoContinuo) return;
    if (capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null) return;

    final now = DateTime.now();
    if (_ultimoScanCode == code &&
        _ultimoScanTs != null &&
        now.difference(_ultimoScanTs!) < _rafagaCooldown) {
      return;
    }
    _ultimoScanCode = code;
    _ultimoScanTs = now;

    final productos = await pos.buscarPorCodigoAmbiguo(code);
    if (!mounted) return;

    if (productos.length == 1) {
      // Caso normal: un único match
      pos.agregarProducto(productos.first);
      HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.click);
    } else if (productos.length > 1) {
      // Pausa ráfaga para mostrar el selector
      _rafagaController.stop();
      final seleccionado = await showResolvedorConflictoProducto(
        context,
        codigo: code,
        productos: productos,
      );
      if (!mounted) return;
      if (seleccionado != null) {
        pos.agregarProducto(seleccionado);
        HapticFeedback.lightImpact();
      }
      // Reanudar ráfaga
      if (_modoEscaneoContinuo) _rafagaController.start();
    } else {
      // No encontrado → snackbar con opción de vincular
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No encontrado: $code'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Vincular',
          textColor: Colors.white,
          onPressed: () async {
            _rafagaController.stop();
            if (!mounted) return;
            await showHojaVincularCodigo(context, pos: pos, codigoBarras: code);
            if (_modoEscaneoContinuo && mounted) _rafagaController.start();
          },
        ),
      ));
    }
  }

  Future<void> _iniciarEscaneoSimple(ProveedorCaja pos) async {
    final code = await openScanner(context, title: 'Escanear Producto');
    if (code == null || !mounted) return;

    final productos = await pos.buscarPorCodigoAmbiguo(code);
    if (!mounted) return;

    if (productos.length == 1) {
      // Caso normal: producto único
      pos.agregarProducto(productos.first);
      return;
    } else if (productos.length > 1) {
      // Conflicto: varios productos con el mismo código
      final seleccionado = await showResolvedorConflictoProducto(
        context,
        codigo: code,
        productos: productos,
      );
      if (!mounted) return;
      if (seleccionado != null) pos.agregarProducto(seleccionado);
      return;
    }

    // Código desconocido → ofrecer vincular o crear
    if (!mounted) return;
    final accion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.search_off, color: Colors.amber),
          SizedBox(width: 8),
          Text('Producto no encontrado',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ]),
        content: Text(
          'No se encontró ningún producto con el código:\n\n"$code"',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, 'vincular'),
            icon: const Icon(Icons.link, size: 16, color: Colors.tealAccent),
            label: const Text('Vincular a existente',
                style: TextStyle(color: Colors.tealAccent)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () => Navigator.pop(ctx, 'crear'),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Crear nuevo'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (accion == 'vincular') {
      await showHojaVincularCodigo(context, pos: pos, codigoBarras: code);
    } else if (accion == 'crear') {
      final agregado = await context.push<bool>('/inventario/nuevo',
          extra: {'initialSku': code});
      if (!mounted) return;
      if (agregado == true) {
        final nuevo = await pos.buscarProducto(code);
        if (nuevo != null) pos.agregarProducto(nuevo);
      }
    }
  }

  void _activarModoRafaga(ProveedorCaja pos) {
    if (!_modoEscaneoContinuo) {
      setState(() => _modoEscaneoContinuo = true);
      _rafagaController.start();
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Modo Ráfaga activo'),
      backgroundColor: Colors.teal,
      duration: Duration(milliseconds: 1200),
    ));
  }

  Future<void> _abrirConsultaRapida(ProveedorCaja pos) async {
    if (!mounted) return;
    final buscadorCtrl = TextEditingController();
    Producto? producto;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> fetch(String q) async {
            final res = await pos.buscarProducto(q);
            setModalState(() => producto = res);
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: buscadorCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Buscar por código o nombre',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon:
                              const Icon(Icons.search, color: Colors.teal),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                        ),
                        onSubmitted: fetch,
                      ),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.qr_code_scanner, color: Colors.teal),
                      onPressed: () async {
                        final code = await openScanner(context,
                            title: 'Consulta rápida');
                        if (code != null) {
                          buscadorCtrl.text = code;
                          await fetch(code);
                        }
                      },
                    )
                  ],
                ),
                const SizedBox(height: 12),
                if (producto != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(producto!.nombre,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(producto!.presentaciones.first.name,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 6),
                        Text(
                            'Precio: S/.${producto!.precioBase.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Colors.tealAccent,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  )
                else
                  const Text('Busca o escanea para ver precio rápido',
                      style: TextStyle(color: Colors.white38)),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _agregarGenericoDialog(ProveedorCaja pos) async {
    if (!mounted) return;
    final nombreCtrl = TextEditingController(text: 'Producto rápido');
    final precioCtrl = TextEditingController(text: '1.00');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Producto genérico',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Nombre',
                labelStyle: TextStyle(color: Colors.white54),
              ),
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
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final precio =
          double.tryParse(precioCtrl.text.replaceAll(',', '.')) ?? 1.0;
      pos.agregarProductoGenerico(
          nombre: nombreCtrl.text.trim(), precio: precio);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProveedorCaja>(
      builder: (context, pos, _) {
        final isAdmin =
            context.watch<ServicioSesion>().rol == RolesApp.admin;
        if (_modoEscaneoContinuo) {
          return Scaffold(
            backgroundColor: const Color(0xFF0F0F1A),
            body: _buildRafagaLayout(pos),
            bottomNavigationBar: _BarraInferior(
              pos: pos,
              onCobrar: () => _iniciarCobro(context, pos),
            ),
          );
        }

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
                  if (pos.hasPedidoActivo && pos.orderFotoUrl != null)
                    _SuperposicionPedido(fotoUrl: pos.orderFotoUrl!),
                  // ── Cabecera Personalizada (UX Architect) ─────────────────
                  _EncabezadoCaja(
                    pos: pos,
                    isAdmin: isAdmin,
                    modoEscaneoContinuo: _modoEscaneoContinuo,
                    onEscaneoSimple: () => _iniciarEscaneoSimple(pos),
                    onModoRafaga: () => _activarModoRafaga(pos),
                    onRayito: () => _abrirConsultaRapida(pos),
                    onAgregarGenerico: () => _agregarGenericoDialog(pos),
                  ),

                  // ── Buscador / Escaneo ─────────────────────────────────────
                  SeccionEscaneo(
                    searchCtrl: _searchCtrl,
                    buscando: _buscando,
                    resultados: _resultados,
                    onQueryChanged: (q) => _buscarDebounced(q, pos),
                    onClear: () {
                      _searchCtrl.clear();
                      setState(() => _resultados = []);
                    },
                    onTapProducto: (p) {
                      pos.agregarProducto(p);
                      _searchCtrl.clear();
                      setState(() => _resultados = []);
                      HapticFeedback.lightImpact();
                    },
                    onDetalleProducto: (p) {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => ModalDetalleProducto(
                          producto: p,
                          onAddWithPresentation: (pres) =>
                              pos.agregarProducto(p, presentacion: pres),
                          onApplyManualPrice: (precio) async {
                            await pos.agregarProducto(
                              p,
                              presentacion:
                                  p.presentaciones.isNotEmpty
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
                  ),

                  const Divider(
                      height: 1,
                      color: Colors.white12,
                      indent: 12,
                      endIndent: 12),

                  // ── Carrito ───────────────────────────────────────────────────
                  Expanded(
                    child: ResumenCarrito(
                      pos: pos,
                      onScanProduct: () => _iniciarEscaneoSimple(pos),
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: _BarraInferior(
            pos: pos,
            onCobrar: () => _iniciarCobro(context, pos),
          ),
        );
      },
    );
  }

  Future<void> _iniciarCobro(BuildContext context, ProveedorCaja pos) async {
    if (!mounted) return;
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

  Future<void> _manejarPostVenta(Venta venta, ProveedorCaja pos) async {
    try {
      final turnoEstado = pos.cajaOmitida ? 'Inventario' : 'Abierto';
      String mensajeLargo = 'Total: S/.${venta.total.toStringAsFixed(2)}\n\n';
      if (venta.synced) {
        mensajeLargo += '✅ Sincronizado con servidor\n';
      } else {
        mensajeLargo +=
            '⚠️ Guardado localmente (sin internet)\nSincronizará automáticamente cuando haya conexión\n';
      }
      mensajeLargo += '¿Imprimir comprobante ahora?';

      if (!mounted) return;

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
        final impreso = await ServicioImpresion()
            .imprimirComprobante(venta, turnoEstado: turnoEstado);
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
          final tasa = await ServicioConfiguracion.obtenerIGVActual();
          final vendedorAlias = await ServicioImpresion.obtenerAliasVendedor();
          final pdf = await ServicioPdf.generateVentaPdf(
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
          await ServicioPdf.shareVentaPdf(pdf);
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
      await ServicioDespacho().preguntarYAbrirPicking(context, venta);

      // PASO 4: Limpiar carrito
      pos.finalizarVentaYLimpiar();
      if (mounted && _modoEscaneoContinuo) {
        setState(() => _modoEscaneoContinuo = false);
      }
    } catch (e) {
      RegistroApp.error('Error post-venta en UI', tag: 'POS', error: e);
    }
  }

  Widget _buildRafagaLayout(ProveedorCaja pos) {
    return SafeArea(
      bottom: false,
      child: Column(
      children: [
        Expanded(
          flex: 4,
          child: Stack(
            children: [
              MobileScanner(
                controller: _rafagaController,
                onDetect: (capture) => _onRafagaDetect(capture, pos),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  heroTag: 'closeRafaga',
                  onPressed: () {
                    _rafagaController.stop();
                    setState(() => _modoEscaneoContinuo = false);
                  },
                  child: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 6,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0F0F1A),
              border: Border(
                top: BorderSide(color: Colors.white12, width: 1),
              ),
            ),
            child: ResumenCarrito(
              pos: pos,
              onScanProduct: () => _iniciarEscaneoSimple(pos),
            ),
          ),
        ),
      ],
      ),
    );
  }
}

// ── Custom Pos Header (UX Architect) ──────────────────────────────────────────
class _EncabezadoCaja extends StatelessWidget {
  final ProveedorCaja pos;
  final bool isAdmin;
  final bool modoEscaneoContinuo;
  final VoidCallback onEscaneoSimple;
  final VoidCallback onModoRafaga;
  final VoidCallback onRayito;
  final VoidCallback onAgregarGenerico;
  const _EncabezadoCaja({
    required this.pos,
    required this.isAdmin,
    required this.modoEscaneoContinuo,
    required this.onEscaneoSimple,
    required this.onModoRafaga,
    required this.onRayito,
    required this.onAgregarGenerico,
  });

  @override
  Widget build(BuildContext context) {
    final bool online = pos.isOnline;
    final Color barColor = online 
        ? (isAdmin ? const Color(0xFF332A00) : const Color(0xFF0E2C26))
        : Colors.grey.shade900;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: barColor,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: Row(
                children: [
                  _PildoraCliente(
                    label: 'C${pos.activeCartIndex + 1}',
                    isAdmin: isAdmin,
                    onTap: () => _abrirSelectorCarritos(context, pos),
                  ),
                  const SizedBox(width: 6),
                  _BotonAgregarCliente(
                    onTap: () => _crearNuevoCliente(context, pos),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),
          _InsigniaIcono(child: IndicadorEstadoImpresora.custom()),
          const SizedBox(width: 8),
          _AccionIcono(
            icon: Icons.qr_code_scanner,
            onTap: onEscaneoSimple,
            active: modoEscaneoContinuo,
            tooltip: 'Escanear producto',
            isAdmin: isAdmin,
          ),
          const SizedBox(width: 8),
          _AccionIcono(
            icon: Icons.add_circle_outline,
            onTap: onAgregarGenerico,
            tooltip: 'Agregar producto rápido',
            isAdmin: isAdmin,
          ),
          const SizedBox(width: 8),
          _AccionIcono(
            icon: Icons.bolt,
            onTap: onModoRafaga,
            tooltip: 'Modo ráfaga',
            isAdmin: isAdmin,
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            color: Colors.grey.shade900,
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            onSelected: (value) {
              if (value == 'consulta') onRayito();
            },
            itemBuilder: (_) => _buildMenuItems(),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(
        value: 'consulta',
        child: Row(
          children: [
            Icon(Icons.flash_on_outlined, size: 18, color: Colors.white70),
            SizedBox(width: 8),
            Text('Consulta rápida'),
          ],
        ),
      ),
      const PopupMenuDivider(),
    ];

    return items;
  }

  void _crearNuevoCliente(BuildContext context, ProveedorCaja pos) {
    final next = List.generate(pos.maxCarritos, (i) => i)
        .firstWhere(
          (i) => i != pos.activeCartIndex && pos.isCartEmpty(i),
          orElse: () => -1,
        );

    if (next == -1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ya hay 5 clientes abiertos. Usa el menú para cambiar.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    pos.cambiarCarrito(next);
  }

  Future<void> _abrirSelectorCarritos(
      BuildContext context, ProveedorCaja pos) async {
    final bool isAdmin = ServicioSesion().rol == RolesApp.admin;
    final Color activeColor = isAdmin ? Colors.amberAccent : Colors.tealAccent;

    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(12),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Text('Clientes rápidos',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2)),
              const SizedBox(height: 6),
              ...List.generate(pos.maxCarritos, (i) {
                final isActive = i == pos.activeCartIndex;
                final count = pos.cartItemCount(i);
                return ListTile(
                  dense: true,
                  leading: Icon(
                    isActive
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isActive ? activeColor : Colors.white54,
                  ),
                  title: Text('C${i + 1}',
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    count == 0 ? 'Sin productos' : '$count en carrito',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing:
                      isActive ? const _InsigniaSuave(text: 'Activo') : null,
                  onTap: () => Navigator.pop(ctx, i),
                );
              }),
            ],
          ),
        ),
      ),
    );

    if (selected != null) pos.cambiarCarrito(selected);
  }
}

class _PildoraCliente extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isAdmin;
  const _PildoraCliente({required this.label, required this.onTap, this.isAdmin = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isAdmin ? Colors.amber.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isAdmin ? Colors.amber.withValues(alpha: 0.5) : Colors.white24),
        ),
        child: Text(label,
            style: TextStyle(
                color: isAdmin ? Colors.amberAccent : Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _BotonAgregarCliente extends StatelessWidget {
  final VoidCallback onTap;
  const _BotonAgregarCliente({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      icon: const Icon(Icons.add_circle_outline,
          color: Colors.white70, size: 22),
      tooltip: 'Nuevo cliente (nuevo carrito)',
      onPressed: onTap,
    );
  }
}

class _InsigniaSuave extends StatelessWidget {
  final String text;
  const _InsigniaSuave({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white70, fontSize: 11)),
    );
  }
}

class _SuperposicionPedido extends StatelessWidget {
  final String fotoUrl;
  const _SuperposicionPedido({required this.fotoUrl});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 12, bottom: 4),
        child: GestureDetector(
          onTap: () => _abrirImagen(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
              ),
              width: 90,
              height: 90,
              child: Image.network(
                fotoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade800,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image, color: Colors.white54),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _abrirImagen(BuildContext context) {
    bool invert = false;
    bool sharpen = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(_matrixFor(invert, sharpen)),
                  child: Image.network(
                    fotoUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      height: 200,
                      color: Colors.grey.shade900,
                      alignment: Alignment.center,
                      child: const Text('No se pudo cargar la foto',
                          style: TextStyle(color: Colors.white70)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() => invert = !invert);
                      },
                      icon: const Icon(Icons.invert_colors,
                          color: Colors.tealAccent),
                      label: Text(invert ? 'Color normal' : 'Invertir',
                          style: const TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() => sharpen = !sharpen);
                      },
                      icon: const Icon(Icons.auto_fix_high,
                          color: Colors.tealAccent),
                      label: Text(sharpen ? 'Normal' : 'Mejorar',
                          style: const TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Share.shareUri(Uri.parse(fotoUrl));
                      },
                      icon: const Icon(Icons.share, color: Colors.tealAccent),
                      label: const Text('Compartir',
                          style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('Cerrar'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      }),
    );
  }
}

List<double> _matrixFor(bool invert, bool sharpen) {
  // sharpen via simple contrast boost
  const normal = <double>[
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];
  const inverted = <double>[
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ];
  final base = invert ? inverted : normal;
  if (!sharpen) return base;
  // simple contrast +15%
  const c = 1.15;
  return List<double>.generate(
      20, (i) => base[i] * (i % 6 == 0 ? c : 1));
}

class _AccionIcono extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;
  final bool isAdmin;
  const _AccionIcono({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color accentColor = isAdmin ? Colors.amberAccent : Colors.tealAccent;
    
    final content = Icon(
      icon,
      color: active ? accentColor : Colors.white70,
      size: 20,
    );
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? accentColor : Colors.white12,
              width: active ? 1.4 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );
  }
}

class _InsigniaIcono extends StatelessWidget {
  final Widget child;
  const _InsigniaIcono({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}


// ── Bottom Bar ────────────────────────────────────────────────────────────────
class _BarraInferior extends StatelessWidget {
  final ProveedorCaja pos;
  final VoidCallback onCobrar;
  const _BarraInferior({required this.pos, required this.onCobrar});

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
              onPressed:
                  pos.items.isEmpty || !pos.cobroHabilitado ? null : onCobrar,
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
            if (!pos.cobroHabilitado)
              const Padding(
                padding: EdgeInsets.only(top: 6, left: 6),
                child: Text('Caja cerrada / modo inventario',
                    style: TextStyle(color: Colors.orange, fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Panel de Cobro ────────────────────────────────────────────────────────────
class _PanelCobro extends StatefulWidget {
  final ProveedorCaja pos;
  const _PanelCobro({required this.pos});
  @override
  State<_PanelCobro> createState() => _PanelCobroState();
}

class _PanelCobroState extends State<_PanelCobro> {
  final _montoCtrl = TextEditingController();
  final _docCtrl = TextEditingController();
  String? _nombreCliente;
  bool _isProcessing = false;
  String? _dniApiStatus;
  bool get _buscandoCliente => widget.pos.isLoadingDocument;
  bool _vueltoConfirmado = false;
  bool _montoEditado = false;
  bool get _requiereConfirmacionVuelto =>
      widget.pos.metodoPago == MetodoPago.efectivo;

  String _sanitizeDocumento(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9]'), '');
  }

  @override
  void initState() {
    super.initState();
    _montoCtrl.text = ''; // obliga a ingresar monto manual
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncVueltoFlag());
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _docCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscarCliente(String doc, bool esRuc) async {
    _dniApiStatus = null;
    _nombreCliente = null;
    setState(() {});

    await widget.pos.buscarDocumentoCliente(doc);
    final cliente = widget.pos.clienteActivo;
    if (!mounted) return;
    if (cliente != null) {
      _nombreCliente = cliente.nombre;
      _dniApiStatus = 'OK';
    } else {
      _dniApiStatus = 'Error';
    }
    setState(() {});
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

      // Si la venta está vinculada a un pedido, marcarlo como completado
      final pedidoId = widget.pos.orderListId;
      if (pedidoId != null) {
        unawaited(ServicioPedidos()
            .completarConVenta(orderId: pedidoId, correlativoComprobante: venta.id));
      }

      if (mounted) {
        // Retornar la venta al modal para que el flujo siga en el context principal
        Navigator.pop(context, venta);
      }
    } catch (e) {
      RegistroApp.error('Error al procesar cobro: $e', tag: 'POS');
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
    // Para efectivo: pedimos (1) monto escrito y (2) confirmar entrega de vuelto.
    // La validación de monto suficiente sigue ocurriendo en pos.canCheckout dentro de _cobrar.
    final puedeCobrar = pos.metodoPago != MetodoPago.efectivo
        ? true
        : (_montoEditado && _vueltoConfirmado);

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
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),

            _section(
              title: 'Total a cobrar',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('S/.${pos.totalCobrar.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Incluye IGV ${pos.ivaRate * 100 ~/ 1}%',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            SelectorPago(
              pos: pos,
              montoCtrl: _montoCtrl,
              montoEditado: _montoEditado,
              vueltoConfirmado: _vueltoConfirmado,
              requiereConfirmacionVuelto: _requiereConfirmacionVuelto,
              onMontoChanged: () {
                _montoEditado = _montoCtrl.text.trim().isNotEmpty;
                _syncVueltoFlag();
                setState(() {});
              },
              onQuickAmount: (value) {
                _montoCtrl.text = value.toStringAsFixed(2);
                _montoCtrl.selection =
                    TextSelection.collapsed(offset: _montoCtrl.text.length);
                _montoEditado = true;
                _syncVueltoFlag();
                setState(() {});
              },
              onMetodoChange: (m) {
                pos.setMetodoPago(m);
                setState(() {
                  _vueltoConfirmado = m != MetodoPago.efectivo;
                  _montoEditado = m != MetodoPago.efectivo;
                });
              },
              onConfirmVuelto: () => setState(() => _vueltoConfirmado = true),
            ),

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
                    onChanged: (v) {
                      final clean = _sanitizeDocumento(v);
                      if (clean.length == 8 || clean.length == 11) {
                        _docCtrl.text = clean;
                        _docCtrl.selection = TextSelection.collapsed(
                            offset: _docCtrl.text.length);
                        _buscarCliente(clean, clean.length == 11);
                      } else if (_nombreCliente != null || _dniApiStatus != null) {
                        setState(() {
                          _nombreCliente = null;
                          _dniApiStatus = null;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                _buscandoCliente
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                            color: Colors.teal, strokeWidth: 2))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_dniApiStatus != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                _dniApiStatus == 'OK'
                                    ? Icons.verified_user
                                    : _dniApiStatus == 'Error API'
                                        ? Icons.error_outline
                                        : Icons.cloud_off,
                                color: _dniApiStatus == 'OK'
                                    ? Colors.tealAccent
                                    : _dniApiStatus == 'Error API'
                                        ? Colors.redAccent
                                        : Colors.orange,
                                size: 18,
                              ),
                            ),
                          IconButton(
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
              ],
            ),
            if (_nombreCliente != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Resultado',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            letterSpacing: 0.2)),
                    const SizedBox(height: 4),
                    Text('Nombre: $_nombreCliente',
                        style: const TextStyle(
                            color: Colors.tealAccent,
                            fontWeight: FontWeight.w700)),
                    if (_docCtrl.text.isNotEmpty)
                      Text('Doc: ${_sanitizeDocumento(_docCtrl.text)}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: puedeCobrar ? _cobrar : null,
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
            if (!puedeCobrar && pos.metodoPago == MetodoPago.efectivo)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _montoEditado
                      ? 'Confirma que ya entregaste el vuelto para habilitar el cobro.'
                      : 'Ingresa el monto recibido para continuar.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  void _syncVueltoFlag() {
    final monto = double.tryParse(_montoCtrl.text.replaceAll(',', '.')) ?? 0;
    widget.pos.setMontoRecibido(monto);
    if (!_requiereConfirmacionVuelto) {
      _vueltoConfirmado = true;
    } else {
      _vueltoConfirmado = false;
    }
  }

  // REFACTOR: helper compartido para secciones del panel.
  Widget _section({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
