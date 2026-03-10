import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bipenc/services/camera_service.dart';
import 'package:bipenc/services/image_processing_service.dart';
import 'package:bipenc/data/models/producto.dart';
import 'package:bipenc/data/models/presentation.dart';
import 'package:bipenc/services/local_db_service.dart';
import 'package:bipenc/services/inventory_service.dart';
import 'package:bipenc/utils/app_logger.dart';
import 'package:bipenc/widgets/scanner_modal.dart';

import 'package:bipenc/services/supabase_service.dart';
import 'package:bipenc/core/constantes/categorias_producto.dart';

class ProductoFormScreen extends StatefulWidget {
  final Producto? producto;
  final String? initialSku;
  const ProductoFormScreen({super.key, this.producto, this.initialSku});

  @override
  State<ProductoFormScreen> createState() => _ProductoFormScreenState();
}

class _ProductoFormScreenState extends State<ProductoFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Campos del nuevo modelo
  final _skuCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _marcaCtrl = TextEditingController();
  final _precioBaseCtrl = TextEditingController();
  final _precioMayoristaCtrl = TextEditingController();
  final _precioEspecialCtrl = TextEditingController();
  final List<_PresentacionDraft> _presentacionesExtra = [];
  final _descripcionCtrl = TextEditingController();
  String _categoriaSeleccionada = CategoriasProducto.lista.first;
  List<String> _categoriasDinamicas =
      List<String>.from(CategoriasProducto.lista);
  List<String> _marcasSugeridas = const [];
  bool get _isEditing => widget.producto != null;

  // Imagen
  final CameraService _cameraService = CameraService();
  final ImageProcessingService _imageService = ImageProcessingService();
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
      final cats = await SupabaseService.obtenerCategorias();
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
      AppLogger.error('Error cargando categorías: $e', tag: 'INVENTORY');
    }
  }

  Future<void> _cargarMarcas() async {
    try {
      final brands = await InventoryService().getAllBrands();
      if (mounted && brands.isNotEmpty) {
        setState(() => _marcasSugeridas = brands);
      }
    } catch (e) {
      AppLogger.error('Error cargando marcas: $e', tag: 'INVENTORY');
    }
  }

  void _cargarPresentacionesExtra(Producto p) {
    for (final pres in p.presentaciones) {
      if (pres.id == 'unid' || pres.id == 'mayo' || pres.id == 'espe') continue;
      _presentacionesExtra.add(
        _PresentacionDraft(
          nombre: pres.name,
          factor: pres.conversionFactor.toStringAsFixed(0),
          precio: pres.getPriceByType('NORMAL').toStringAsFixed(2),
        ),
      );
    }
  }

  Future<void> _initCamera() async {
    await _cameraService.initialize();
    if (mounted) setState(() => _isCameraReady = true);
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
      builder: (ctx) => _CameraModal(cameraService: _cameraService),
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
      // Primero intenta con algoritmo avanzado, luego con manual
      File? recortado = await _imageService.recorteFondo(
        inputPath,
        tolerance: 60,
        fondoBlanco: false,
        touchPoint: touchPoint,
      );

      // Si falla el algoritmo avanzado, intentar con el manual
      recortado ??= await _imageService.recorteFondo(
        inputPath,
        tolerance: 80,
        fondoBlanco: false,
        touchPoint: touchPoint,
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
            await InventoryService().validateUniqueness(normalizedSku);

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
                  await InventoryService().getProductById(existingId ?? '');
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
        AppLogger.warning('Error validando SKU (continuando): $e',
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
        prices: [PricePoint(type: 'NORMAL', amount: precioBase)],
      ),
      if (precioMayorista > 0)
        Presentacion(
          id: 'mayo',
          skuCode: '$normalizedSku-MAYO',
          name: 'Mayorista',
          conversionFactor: 1,
          prices: [PricePoint(type: 'NORMAL', amount: precioMayorista)],
        ),
      if (precioEspecial > 0)
        Presentacion(
          id: 'espe',
          skuCode: '$normalizedSku-ESPE',
          name: 'Especial',
          conversionFactor: 1,
          prices: [PricePoint(type: 'NORMAL', amount: precioEspecial)],
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
          prices: [PricePoint(type: 'NORMAL', amount: precio)],
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
        final uploaded = await SupabaseService.subirImagen(_imagenFinal!);
        if (uploaded != null && uploaded.isNotEmpty) {
          imagenPath = uploaded;
        }
      } catch (e) {
        AppLogger.warning(
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
      await LocalDbService.upsertProducto(product);

      // AGREGAR: Sincronizar a Supabase (no bloquea si falla)
      try {
        await InventoryService().saveFullProduct(product);
        AppLogger.info('✅ Producto sincronizado a Supabase: ${product.skuCode}',
            tag: 'INVENTORY');
      } catch (supError) {
        AppLogger.warning(
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
            // ── Foto del Producto ──────────────────
            Column(
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _isProcesandoImagen ? null : _tomarYProcesarFoto,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.teal, width: 2),
                        image: _imagenFinal != null
                            ? DecorationImage(
                                image: FileImage(_imagenFinal!),
                                fit: BoxFit.contain)
                            : (widget.producto?.imagenPath
                                        ?.startsWith('http') ??
                                    false)
                                ? DecorationImage(
                                    image: NetworkImage(
                                        widget.producto!.imagenPath!),
                                    fit: BoxFit.contain)
                                : null,
                      ),
                      child: _isProcesandoImagen
                          ? const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(color: Colors.teal),
                                SizedBox(height: 8),
                                Text('Procesando...',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 12)),
                              ],
                            )
                          : _imagenFinal == null
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.camera_alt,
                                        size: 50, color: Colors.teal),
                                    const SizedBox(height: 8),
                                    Text('Foto del producto',
                                        style: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontSize: 12)),
                                  ],
                                )
                              : const Align(
                                  alignment: Alignment.bottomRight,
                                  child: Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(Icons.check_circle,
                                        color: Colors.teal, size: 28),
                                  ),
                                ),
                    ),
                  ),
                ),
                if (_imagenFinal != null && !_isProcesandoImagen)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: _ultimoCapturado == null
                              ? null
                              : () => _procesarImagen(_ultimoCapturado!),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('REINTENTAR RECORTE',
                              style: TextStyle(fontSize: 10)),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () async {
                            await CameraService().toggleFlash();
                            setState(() {});
                          },
                          icon: const Icon(Icons.flash_on,
                              color: Colors.yellowAccent, size: 20),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // ── SKU ───────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _campo(_skuCtrl, 'SKU / Código', Icons.qr_code,
                      hint: 'Ej: LAP-FA-001 (vacío = auto)'),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.black),
                  onPressed: () async {
                    final code =
                        await openScanner(context, title: 'Escanear SKU');
                    if (code != null) setState(() => _skuCtrl.text = code);
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Nombre ────────────────────────────
            _campo(_nombreCtrl, 'Nombre del Producto', Icons.label_outline,
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'El nombre es requerido'
                    : null),
            const SizedBox(height: 14),

            // ── Marca (dinámica y persistente) ──────────────
            _campo(_marcaCtrl, 'Marca', Icons.branding_watermark_outlined),
            if (_marcasSugeridas.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _marcasSugeridas
                    .where((m) => _marcaCtrl.text.trim().isEmpty
                        ? true
                        : m
                            .toLowerCase()
                            .contains(_marcaCtrl.text.toLowerCase()))
                    .take(8)
                    .map((m) => ActionChip(
                          label: Text(m),
                          onPressed: () => setState(() => _marcaCtrl.text = m),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _categoriaSeleccionada,
                    dropdownColor: Colors.grey.shade900,
                    style: const TextStyle(color: Colors.white),
                    decoration:
                        _inputDeco('Categoría', Icons.category_outlined),
                    items: [
                      ..._categoriasDinamicas.map(
                          (c) => DropdownMenuItem(value: c, child: Text(c))),
                      const DropdownMenuItem(
                        value: _kNuevaCategoriaStr,
                        child: Text(_kNuevaCategoriaStr,
                            style: TextStyle(
                                color: Colors.tealAccent,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == _kNuevaCategoriaStr) {
                        _mostrarDialogoSumaCategoria();
                      } else {
                        setState(() => _categoriaSeleccionada = v!);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style:
                      IconButton.styleFrom(backgroundColor: Colors.redAccent),
                  tooltip: 'Eliminar categoría',
                  onPressed: _categoriaSeleccionada.isEmpty
                      ? null
                      : _intentarEliminarCategoriaActual,
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Precios ───────────────────────────
            Row(
              children: [
                Expanded(
                  child: _campoPrecio(_precioBaseCtrl, 'Precio Unitario *',
                      validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0
                          ? 'Requerido'
                          : null),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _campoPrecio(_precioMayoristaCtrl, 'Precio Mayorista'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _campoPrecio(
                      _precioEspecialCtrl, 'Precio Especial / Distribuidor'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _campo(_descripcionCtrl, 'Descripción', Icons.description_outlined,
                hint: 'Detalles del producto...'),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _sugerirDescripcionRapida,
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('Sugerir descripción'),
              ),
            ),
            const SizedBox(height: 14),
            ExpansionTile(
              collapsedIconColor: Colors.white70,
              iconColor: Colors.tealAccent,
              title: const Text('Presentaciones adicionales (dinámicas)',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                  'Opcional: agrega las que necesites (docena, pack, caja, resma...)',
                  style: TextStyle(color: Colors.white54)),
              children: [
                ..._presentacionesExtra.asMap().entries.map((entry) {
                  final index = entry.key;
                  final p = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _campo(
                                  p.nombreCtrl,
                                  'Nombre presentación ${index + 1}',
                                  Icons.inventory_2_outlined,
                                  hint: 'Ej: Pack x25 / Docena / Caja x50',
                                ),
                              ),
                              IconButton(
                                tooltip: 'Eliminar presentación',
                                onPressed: () {
                                  setState(() {
                                    _presentacionesExtra[index].dispose();
                                    _presentacionesExtra.removeAt(index);
                                  });
                                },
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _campoNumero(
                                  p.factorCtrl,
                                  'Factor (unidades)',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _campoPrecio(
                                  p.precioCtrl,
                                  'Precio presentación',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _presentacionesExtra.add(_PresentacionDraft());
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar presentación'),
                  ),
                ),
                const SizedBox(height: 6),
              ],
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
        await SupabaseService.agregarCategoria(result);
      } catch (e) {
        AppLogger.warning('No se pudo subir categoría de inmediato: $e',
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
        await SupabaseService.eliminarCategoriaSiNoEstaEnUso(categoria);
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

  Widget _campo(TextEditingController ctrl, String label, IconData icon,
      {String? hint, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDeco(label, icon, hint: hint),
    );
  }

  Widget _campoPrecio(TextEditingController ctrl, String label,
      {String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _inputDeco(label, Icons.attach_money).copyWith(
        prefixText: 'S/. ',
        prefixStyle:
            const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _campoNumero(TextEditingController ctrl, String label) {
    return TextFormField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _inputDeco(label, Icons.functions_outlined),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: Icon(icon, color: Colors.teal),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.teal)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red)),
      );
}

class _PresentacionDraft {
  final TextEditingController nombreCtrl;
  final TextEditingController factorCtrl;
  final TextEditingController precioCtrl;

  _PresentacionDraft({
    String nombre = '',
    String factor = '',
    String precio = '',
  })  : nombreCtrl = TextEditingController(text: nombre),
        factorCtrl = TextEditingController(text: factor),
        precioCtrl = TextEditingController(text: precio);

  void dispose() {
    nombreCtrl.dispose();
    factorCtrl.dispose();
    precioCtrl.dispose();
  }
}

// ── Modal de Cámara ───────────────────────────────────────────────────────────
class _CameraModal extends StatelessWidget {
  final CameraService cameraService;
  const _CameraModal({required this.cameraService});

  @override
  Widget build(BuildContext context) {
    if (cameraService.controller == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.teal));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(cameraService.controller!),
        // Guía de encuadre
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.teal, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const Positioned(
          top: 60,
          left: 0,
          right: 0,
          child: Text(
              'Centra el producto en el recuadro\nsobre fondo liso para mejor resultado',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        Positioned(
          bottom: 50,
          left: 0,
          right: 0,
          child: Center(
            child: FloatingActionButton.large(
              backgroundColor: Colors.white,
              onPressed: () async {
                final file = await cameraService.takePicture();
                if (context.mounted) Navigator.pop(context, file);
              },
              child: const Icon(Icons.camera, color: Colors.black, size: 40),
            ),
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ],
    );
  }
}
