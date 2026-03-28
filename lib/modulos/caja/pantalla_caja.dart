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
import 'package:bipenc/ui/modales/modal_escaner.dart';
import 'package:bipenc/datos/modelos/venta.dart';
import 'package:bipenc/servicios/servicio_configuracion.dart';
import '../../servicios/servicio_pdf.dart';
import 'package:bipenc/ui/modales/modal_detalle_producto.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../servicios/servicio_despacho.dart';
import 'componentes/seccion_escaneo.dart';
import 'componentes/resumen_carrito.dart';
import 'componentes/resolvedor_conflicto_producto.dart';
import 'componentes/hoja_vincular_codigo.dart';
import 'componentes/encabezado_caja.dart';
import 'componentes/barra_inferior_caja.dart';
import 'componentes/panel_cobro.dart';
import 'componentes/superposicion_pedido.dart';

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
            bottomNavigationBar: BarraInferiorCaja(
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
                    SuperposicionPedido(fotoUrl: pos.orderFotoUrl!),
                  // ── Cabecera Personalizada (UX Architect) ─────────────────
                  EncabezadoCaja(
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
          bottomNavigationBar: BarraInferiorCaja(
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
      builder: (ctx) => PanelCobro(pos: pos),
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
