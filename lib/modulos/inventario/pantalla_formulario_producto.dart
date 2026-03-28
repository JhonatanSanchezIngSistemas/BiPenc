import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bipenc/servicios/servicio_camara.dart';
import 'package:bipenc/servicios/servicio_procesamiento_imagen.dart';
import 'package:bipenc/datos/modelos/producto.dart';
import 'package:bipenc/datos/modelos/presentacion.dart';
import 'package:bipenc/servicios/servicio_db_local.dart';
import 'package:bipenc/servicios/servicio_inventario.dart';
import 'package:bipenc/utilidades/registro_app.dart';
import 'package:bipenc/ui/modales/modal_escaner.dart';
import 'package:bipenc/servicios/servicio_sesion.dart';

import 'package:bipenc/servicios/servicio_backend.dart';
import 'package:bipenc/base/constantes/categorias_producto.dart';
import 'componentes/borrador_presentacion.dart';
import 'componentes/modal_camara_producto.dart';
import 'componentes/seccion_foto_producto.dart';
import 'componentes/seccion_datos_producto.dart';
import 'componentes/seccion_precios_presentaciones.dart';

class PantallaFormularioProducto extends StatefulWidget {
  final Producto? producto;
  final String? initialSku;
  const PantallaFormularioProducto({super.key, this.producto, this.initialSku});

  @override
  State<PantallaFormularioProducto> createState() => _PantallaFormularioProductoState();
}

class _PantallaFormularioProductoState extends State<PantallaFormularioProducto> {
  final _formKey = GlobalKey<FormState>();

  // Campos del nuevo modelo
  final _skuCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _marcaCtrl = TextEditingController();
  final _precioBaseCtrl = TextEditingController();
  final _precioMayoristaCtrl = TextEditingController();
  final _precioEspecialCtrl = TextEditingController();
  final List<BorradorPresentacion> _presentacionesExtra = [];
  final _descripcionCtrl = TextEditingController();
  String _categoriaSeleccionada = CategoriasProducto.lista.first;
  List<String> _categoriasDinamicas =
      List<String>.from(CategoriasProducto.lista);
  List<String> _marcasSugeridas = const [];
  bool get _isEditing => widget.producto != null;

  // Imagen
  final ServicioCamara _cameraService = ServicioCamara();
  final ServicioProcesamientoImagen _imageService = ServicioProcesamientoImagen();
  File? _imagenFinal;
  bool _isCameraReady = false;
  bool _isProcesandoImagen = false;
  XFile? _ultimoCapturado;

  static const _kNuevaCategoriaStr = '+ Nueva Categoría...';

  @override
  void initState() {
    super.initState();
    _initCamera();
    _cargarCategorias();

    if (_isEditing) {
      final p = widget.producto!;
      _skuCtrl.text = p.id;
      _nombreCtrl.text = p.nombre;
      _marcaCtrl.text = p.marca;
      _precioBaseCtrl.text = p.precioBase.toStringAsFixed(2);
      _precioMayoristaCtrl.text = p.precioMayorista.toStringAsFixed(2);
      _precioEspecialCtrl.text = p.precioEspecial.toStringAsFixed(2);
      _descripcionCtrl.text = p.descripcion ?? '';
      _categoriaSeleccionada = p.categoria;
      _cargarPresentacionesExtra(p);
      if (p.imagenPath != null) {
        if (p.imagenPath!.startsWith('http')) {
          // Si es URL, se manejará en el Widget de imagen (NetworkImage)
        } else {
          _imagenFinal = File(p.imagenPath!);
        }
      }
    } else {
      // Si se llegó desde el POS con un SKU escaneado, pre-rellenar
      if (widget.initialSku != null && widget.initialSku!.isNotEmpty) {
        _skuCtrl.text = widget.initialSku!;
      } else {
        _skuCtrl.text = '';
      }
    }
    _cargarMarcas();
  }

  Future<void> _cargarCategorias() async {
    try {
      final cats = await ServicioBackend.obtenerCategorias();
      if (cats.isNotEmpty && mounted) {
        setState(() {
          _categoriasDinamicas = List<String>.from(cats);
          // Verificar si la seleccionada sigue siendo válida
          if (!_categoriasDinamicas.contains(_categoriaSeleccionada)) {
            _categoriaSeleccionada = _categoriasDinamicas.first;
          }
        });
      }
    } catch (e) {
      RegistroApp.error('Error cargando categorías: $e', tag: 'INVENTORY');
    }
  }

  Future<void> _cargarMarcas() async {
    try {
      final brands = await ServicioInventario().getAllBrands();
      if (mounted && brands.isNotEmpty) {
        setState(() => _marcasSugeridas = brands);
      }
    } catch (e) {
      RegistroApp.error('Error cargando marcas: $e', tag: 'INVENTORY');
    }
  }

  void _cargarPresentacionesExtra(Producto p) {
    for (final pres in p.presentaciones) {
      if (pres.id == 'unid' || pres.id == 'mayo' || pres.id == 'espe') continue;
      _presentacionesExtra.add(
        BorradorPresentacion(
          nombre: pres.name,
          factor: pres.conversionFactor.toStringAsFixed(0),
          precio: pres.getPriceByType('NORMAL').toStringAsFixed(2),
        ),
      );
    }
  }

  Future<void> _initCamera() async {
    await _cameraService.initialize();
    if (mounted) {
      final ready = _cameraService.controller?.value.isInitialized == true;
      setState(() => _isCameraReady = ready);
    }
  }

  @override
  void dispose() {
    _skuCtrl.dispose();
    _nombreCtrl.dispose();
    _marcaCtrl.dispose();
    _precioBaseCtrl.dispose();
    _precioMayoristaCtrl.dispose();
    _precioEspecialCtrl.dispose();
    for (final p in _presentacionesExtra) {
      p.dispose();
    }
    _descripcionCtrl.dispose();
    _cameraService.dispose();
    super.dispose();
  }

  // ── Captura + Recorte Real ─────────────────────────────────────────────

  Future<void> _tomarYProcesarFoto() async {
    if (!_isCameraReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cámara no disponible'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    final XFile? captured = await showModalBottomSheet<XFile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) => ModalCamaraProducto(cameraService: _cameraService),
    );

    if (captured == null) return;
    _ultimoCapturado = captured;
    await _procesarImagen(captured);
  }

  Future<void> _procesarImagen(XFile captured, {Point<int>? touchPoint}) async {
    setState(() => _isProcesandoImagen = true);

    try {
      // OPTIMIZACIÓN RAM PARA DISPOSITIVOS GAMA MEDIA/BAJA
      final compressed = await _imageService.comprimirImagen(captured);
      final inputPath = (compressed ?? captured).path;

      // Paso 2: Aplicar recorte con el algoritmo mejorado
      // Primero intenta con ML Kit; luego fallback manual con dos tolerancias
      File? recortado = await _imageService.recorteFondo(
        inputPath,
        tolerance: 60,
        fondoBlanco: false,
        touchPoint: touchPoint,
        useMLKit: true,
      );

      // Fallback manual agresivo
      recortado ??= await _imageService.recorteFondo(
        inputPath,
        tolerance: 70,
        fondoBlanco: false,
        touchPoint: touchPoint,
        useMLKit: false,
      );

      final docDir = await getApplicationDocumentsDirectory();
      final finalPath =
          '${docDir.path}/prod_${DateTime.now().millisecondsSinceEpoch}.png';
      final finalFile = recortado != null
          ? await recortado.copy(finalPath)
          : await File(inputPath).copy(finalPath);

      _limpiarTemp([if (compressed != null) compressed.path]);

      setState(() {
        _imagenFinal = finalFile;
        _isProcesandoImagen = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(recortado != null
              ? '✅ Fondo eliminado correctamente'
              : '⚠️ No se pudo procesar. Se guardó original.'),
          backgroundColor: recortado != null ? Colors.teal : Colors.orange,
        ));
      }
    } catch (e) {
      setState(() => _isProcesandoImagen = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al procesar imagen: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _limpiarTemp(List<String> paths) {
    for (final p in paths) {
      try {
        File(p).deleteSync();
      } catch (_) {}
    }
  }

  // ── Guardar Producto ───────────────────────────────────────────────────

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    // Validar que haya imagen antes de guardar (opcional pero recomendado)
    // Si no hay imagen, continuamos con imagenUrl vacío

    // Construir SKU: si el usuario lo dejó vacío, auto-generamos uno
    final sku = _skuCtrl.text.trim().isEmpty
        ? 'BP-${DateTime.now().millisecondsSinceEpoch % 100000}'
        : _skuCtrl.text.trim();
    final normalizedSku = sku.toUpperCase();

    // ✅ NUEVO: Validar que el SKU sea único (a menos que estemos editando)
    if (!_isEditing) {
      try {
        final (skuExists, existingId) =
            await ServicioInventario().validateUniqueness(normalizedSku);

        if (skuExists && mounted) {
          // SKU ya existe. Ofrecer opciones
          final shouldEditExisting = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Row(children: [
                Icon(Icons.warning, color: Colors.amber),
                SizedBox(width: 8),
                Text('SKU Duplicado', style: TextStyle(color: Colors.white)),
              ]),
              content: Text(
                'El código "$sku" ya existe en el sistema (ID: $existingId).\n\n'
                '¿Deseas editar el producto existente o usar otro código?',
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Usar otro código',
                      style: TextStyle(color: Colors.white54)),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Editar existente'),
                ),
              ],
            ),
          );

          if (shouldEditExisting == true) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Cargando producto $existingId...'),
                  backgroundColor: Colors.blue,
                ),
              );

              // Cargar el producto completo y navegar a edición
              final p =
                  await ServicioInventario().getProductById(existingId ?? '');
              if (mounted && p != null) {
                // Reemplazamos la ruta actual con el editor del producto existente
                context.pushReplacement('/inventario/editar', extra: p);
              }
            }
          }
          return; // No continuar con el guardado
        }
      } catch (e) {
        // Error validando SKU (probablemente red)
        RegistroApp.warning('Error validando SKU (continuando): $e',
            tag: 'INVENTORY');
      }
    }

    final precioBase =
        double.tryParse(_precioBaseCtrl.text.replaceAll(',', '.')) ?? 0.0;
    final precioMayorista =
        double.tryParse(_precioMayoristaCtrl.text.replaceAll(',', '.')) ?? 0.0;
    final precioEspecial =
        double.tryParse(_precioEspecialCtrl.text.replaceAll(',', '.')) ?? 0.0;

    if (precioBase <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('El precio base debe ser mayor a 0'),
            backgroundColor: Colors.red),
      );
      return;
    }

    final presentaciones = <Presentacion>[
      Presentacion(
        id: 'unid',
        skuCode: normalizedSku,
        name: 'Unidad',
        conversionFactor: 1,
        barcode: normalizedSku,
        prices: [PuntoPrecio(type: 'NORMAL', amount: precioBase)],
      ),
      if (precioMayorista > 0)
        Presentacion(
          id: 'mayo',
          skuCode: '$normalizedSku-MAYO',
          name: 'Mayorista',
          conversionFactor: 1,
          prices: [PuntoPrecio(type: 'NORMAL', amount: precioMayorista)],
        ),
      if (precioEspecial > 0)
        Presentacion(
          id: 'espe',
          skuCode: '$normalizedSku-ESPE',
          name: 'Especial',
          conversionFactor: 1,
          prices: [PuntoPrecio(type: 'NORMAL', amount: precioEspecial)],
        ),
    ];

    for (int i = 0; i < _presentacionesExtra.length; i++) {
      final draft = _presentacionesExtra[i];
      final nombre = draft.nombreCtrl.text.trim();
      final factor =
          double.tryParse(draft.factorCtrl.text.trim().replaceAll(',', '.')) ??
              0;
      final precio =
          double.tryParse(draft.precioCtrl.text.trim().replaceAll(',', '.')) ??
              0;

      if (nombre.isEmpty && factor <= 0 && precio <= 0) continue;
      if (nombre.isEmpty || factor <= 1 || precio <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Cada presentación adicional requiere nombre, factor > 1 y precio > 0'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final nameSlug = nombre
          .toUpperCase()
          .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      final presId = 'pres_${i + 1}';

      presentaciones.add(
        Presentacion(
          id: presId,
          skuCode: '$normalizedSku-$nameSlug',
          name: nombre,
          conversionFactor: factor,
          prices: [PuntoPrecio(type: 'NORMAL', amount: precio)],
        ),
      );
    }

    // Normalizamos: nuevos productos usan SKU como ID para evitar desalineación id/sku.
    final currentId = widget.producto?.id ?? '';
    final productId = _isEditing
        ? (currentId.startsWith('LOCAL-') ? normalizedSku : currentId)
        : normalizedSku;

    String? imagenPath = _imagenFinal?.path ?? widget.producto?.imagenPath;
    if (_imagenFinal != null) {
      try {
        final uploaded = await ServicioBackend.subirImagen(_imagenFinal!);
        if (uploaded != null && uploaded.isNotEmpty) {
          imagenPath = uploaded;
        }
      } catch (e) {
        RegistroApp.warning(
            'No se pudo subir imagen ahora, se conserva local: $e',
            tag: 'INVENTORY');
      }
    }

    final product = Producto(
      id: productId,
      skuCode: normalizedSku,
      nombre: _nombreCtrl.text.trim(),
      marca: _marcaCtrl.text.trim(),
      categoria: _categoriaSeleccionada,
      presentaciones: presentaciones,
      imagenPath: imagenPath,
      descripcion: _descripcionCtrl.text.trim(),
      estado: 'VERIFICADO',
    );

    try {
      await ServicioDbLocal.upsertProducto(product);
      if (_isEditing) {
        unawaited(ServicioDbLocal.logAudit(
          accion: 'EDITAR_PRODUCTO',
          usuario: ServicioSesion().perfil?.alias,
          detalle:
              'SKU $normalizedSku nombre ${_nombreCtrl.text.trim()} precioBase ${_precioBaseCtrl.text}',
        ));
      }

      // AGREGAR: Sincronizar a Supabase (no bloquea si falla)
      try {
        await ServicioInventario().saveFullProduct(product);
        RegistroApp.info('✅ Producto sincronizado a Supabase: ${product.skuCode}',
            tag: 'INVENTORY');
      } catch (supError) {
        RegistroApp.warning(
            '⚠️ Guardado local OK, pero falló Supabase: $supError',
            tag: 'INVENTORY');
        // Continuar (se sincronizará después con T1.5 background sync)
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ Producto guardado'),
              backgroundColor: Colors.teal),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al guardar: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Producto' : 'Registrar Producto'),
        backgroundColor: Colors.grey.shade900,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isProcesandoImagen ? null : _guardar,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.save),
        label: const Text('Guardar',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SeccionFotoProducto(
              imagenLocal: _imagenFinal,
              imagenUrl: widget.producto?.imagenPath,
              isProcesando: _isProcesandoImagen,
              onTomarFoto: _isProcesandoImagen ? null : _tomarYProcesarFoto,
              onReintentarRecorte: _ultimoCapturado == null
                  ? null
                  : () => _procesarImagen(_ultimoCapturado!),
              onToggleFlash: () async {
                await ServicioCamara().toggleFlash();
                setState(() {});
              },
            ),
            const SizedBox(height: 24),
            SeccionDatosProducto(
              skuCtrl: _skuCtrl,
              nombreCtrl: _nombreCtrl,
              marcaCtrl: _marcaCtrl,
              descripcionCtrl: _descripcionCtrl,
              marcasSugeridas: _marcasSugeridas,
              categorias: _categoriasDinamicas,
              categoriaSeleccionada: _categoriaSeleccionada,
              nuevaCategoriaLabel: _kNuevaCategoriaStr,
              onEscanearSku: () async {
                final code = await openScanner(context, title: 'Escanear SKU');
                if (code != null) setState(() => _skuCtrl.text = code);
              },
              onNuevaCategoria: _mostrarDialogoSumaCategoria,
              onCategoriaSeleccionada: (value) =>
                  setState(() => _categoriaSeleccionada = value),
              onEliminarCategoria: _categoriaSeleccionada.isEmpty
                  ? () {}
                  : _intentarEliminarCategoriaActual,
              puedeEliminarCategoria: _categoriaSeleccionada.isNotEmpty,
              onSugerirDescripcion: _sugerirDescripcionRapida,
              onSeleccionarMarca: (m) =>
                  setState(() => _marcaCtrl.text = m),
            ),
            const SizedBox(height: 14),
            SeccionPreciosPresentaciones(
              precioBaseCtrl: _precioBaseCtrl,
              precioMayoristaCtrl: _precioMayoristaCtrl,
              precioEspecialCtrl: _precioEspecialCtrl,
              presentaciones: _presentacionesExtra,
              onAgregarPresentacion: () {
                setState(() => _presentacionesExtra.add(BorradorPresentacion()));
              },
              onEliminarPresentacion: (index) {
                setState(() {
                  _presentacionesExtra[index].dispose();
                  _presentacionesExtra.removeAt(index);
                });
              },
            ),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }

  Future<void> _mostrarDialogoSumaCategoria() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Nueva Categoría',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Ej: Termos, Regalos...',
            hintStyle: TextStyle(color: Colors.white24),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCELAR')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('AÑADIR'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await ServicioBackend.agregarCategoria(result);
      } catch (e) {
        RegistroApp.warning('No se pudo subir categoría de inmediato: $e',
            tag: 'INVENTORY');
      }

      setState(() {
        if (!_categoriasDinamicas.contains(result)) {
          _categoriasDinamicas.add(result);
        }
        _categoriasDinamicas = _categoriasDinamicas.toSet().toList();
        _categoriasDinamicas.sort();
        _categoriaSeleccionada = result;
      });
    } else {
      // Si canceló, volvemos a la primera válida
      if (_categoriasDinamicas.isNotEmpty &&
          !_categoriasDinamicas.contains(_categoriaSeleccionada)) {
        setState(() => _categoriaSeleccionada = _categoriasDinamicas.first);
      }
    }
  }

  void _sugerirDescripcionRapida() {
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) return;
    final marca =
        _marcaCtrl.text.trim().isEmpty ? 'Genérica' : _marcaCtrl.text.trim();
    final categoria = _categoriaSeleccionada.trim().isEmpty
        ? 'General'
        : _categoriaSeleccionada.trim();
    _descripcionCtrl.text =
        '$nombre de marca $marca para uso en $categoria. Producto editable y sujeto a actualización de precio/presentación.';
  }

  Future<void> _intentarEliminarCategoriaActual() async {
    final categoria = _categoriaSeleccionada.trim();
    if (categoria.isEmpty) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Eliminar categoría',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Se intentará eliminar "$categoria" si no tiene productos asociados.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    final eliminado =
        await ServicioBackend.eliminarCategoriaSiNoEstaEnUso(categoria);
    if (!mounted) return;
    if (!eliminado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo eliminar: categoría en uso o sin conexión'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await _cargarCategorias();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Categoría "$categoria" eliminada')),
    );
  }

}
