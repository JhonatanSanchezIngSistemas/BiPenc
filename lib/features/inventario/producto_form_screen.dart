import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bipenc/services/camera_service.dart';
import 'package:bipenc/services/image_processing_service.dart';
import 'package:bipenc/data/models/product.dart';
import 'package:bipenc/data/local/db_helper.dart';

class ProductoFormScreen extends StatefulWidget {
  const ProductoFormScreen({super.key});

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
  String _categoriaSeleccionada = 'Escritura';
  List<String> _categoriasDinamicas = [];

  // Imagen
  final CameraService _cameraService = CameraService();
  final ImageProcessingService _imageService = ImageProcessingService();
  File? _imagenFinal;
  bool _isCameraReady = false;
  bool _isProcesandoImagen = false;

  static const _marcasSugeridas = [
    'Faber-Castell', 'Pilot', 'Stabilo', 'Staedtler', 'Pentel',
    'Pelikan', 'Stanford', 'Norma', 'Artesco', 'BIC', 'Maped', 'Casio',
  ];

  static const _kNuevaCategoriaStr = '+ Nueva Categoría...';

  @override
  void initState() {
    super.initState();
    _initCamera();
    _cargarCategorias();
    // Auto-generar SKU temporal que el usuario puede editar
    _skuCtrl.text = 'BP-${Random().nextInt(9000) + 1000}';
  }

  Future<void> _cargarCategorias() async {
    final cats = await DBHelper().getAllCategories();
    if (mounted) {
      setState(() {
        _categoriasDinamicas = cats;
        if (cats.isNotEmpty) _categoriaSeleccionada = cats.first;
      });
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
    _cameraService.dispose();
    super.dispose();
  }

  // ── Captura + Recorte Real ─────────────────────────────────────────────

  Future<void> _tomarYProcesarFoto() async {
    if (!_isCameraReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cámara no disponible'), backgroundColor: Colors.orange),
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

    setState(() => _isProcesandoImagen = true);

    try {
      // OPTIMIZACIÓN RAM PARA SAMSUNG A36: 
      // Paso 1: Comprimir a WebP PRIMERO para liberar RAM de la imagen RAW
      final compressed = await _imageService.comprimirImagen(captured);
      final inputPath = (compressed ?? captured).path;

      // Paso 2: Aplicar recorte de fondo sobre la imagen ya comprimida 
      // (Menos resolución -> Procesamiento más rápido y ligero)
      final recortado = await _imageService.recortarFondo(inputPath, tolerance: 65);

      // Paso 3: Guardado definitivo en documentos de la app
      final docDir = await getApplicationDocumentsDirectory();
      final finalPath = '${docDir.path}/prod_${DateTime.now().millisecondsSinceEpoch}.png';
      final finalFile = recortado != null
          ? await recortado.copy(finalPath)
          : await File(inputPath).copy(finalPath);

      // Limpieza de temporales
      _limpiarTemp([captured.path, if (compressed != null) compressed.path]);

      setState(() {
        _imagenFinal = finalFile;
        _isProcesandoImagen = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(recortado != null
              ? '✅ Fondo eliminado correctamente.'
              : '⚠️ No se pudo procesar el fondo automáticamente. Se guardó la foto original.'),
          backgroundColor: recortado != null ? Colors.teal : Colors.orange,
        ));
      }
    } catch (e) {
      setState(() => _isProcesandoImagen = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al procesar imagen: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _limpiarTemp(List<String> paths) {
    for (final p in paths) {
      try { File(p).deleteSync(); } catch (_) {}
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

    final precioBase = double.tryParse(_precioBaseCtrl.text.replaceAll(',', '.')) ?? 0.0;
    final precioMayorista = double.tryParse(_precioMayoristaCtrl.text.replaceAll(',', '.')) ?? 0.0;

    if (precioBase <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El precio base debe ser mayor a 0'), backgroundColor: Colors.red),
      );
      return;
    }

    final product = Product(
      sku: sku,
      nombre: _nombreCtrl.text.trim(),
      marca: _marcaCtrl.text.trim(),
      categoria: _categoriaSeleccionada,
      precioBase: precioBase,
      precioMayorista: precioMayorista,
      imagenUrl: _imagenFinal?.path ?? '',
    );

    try {
      await DBHelper().insertProduct(product);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Producto guardado'), backgroundColor: Colors.teal),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
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
        title: const Text('Registrar Producto'),
        backgroundColor: Colors.grey.shade900,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isProcesandoImagen ? null : _guardar,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.save),
        label: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Foto del Producto ──────────────────
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
                        ? DecorationImage(image: FileImage(_imagenFinal!), fit: BoxFit.contain)
                        : null,
                  ),
                  child: _isProcesandoImagen
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Colors.teal),
                            SizedBox(height: 8),
                            Text('Eliminando fondo...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        )
                      : _imagenFinal == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.camera_alt, size: 50, color: Colors.teal),
                                const SizedBox(height: 8),
                                Text('Foto del producto', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                              ],
                            )
                          : const Align(
                              alignment: Alignment.bottomRight,
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.check_circle, color: Colors.teal, size: 28),
                              ),
                            ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── SKU ───────────────────────────────
            _campo(_skuCtrl, 'SKU / Código', Icons.qr_code, hint: 'Ej: BP-1001 ó deja el sugerido'),
            const SizedBox(height: 14),

            // ── Nombre ────────────────────────────
            _campo(_nombreCtrl, 'Nombre del Producto', Icons.label_outline,
                validator: (v) => v == null || v.trim().isEmpty ? 'El nombre es requerido' : null),
            const SizedBox(height: 14),

            // ── Marca (autocomplete) ──────────────
            Autocomplete<String>(
              optionsBuilder: (tv) => tv.text.isEmpty
                  ? const []
                  : _marcasSugeridas.where((m) => m.toLowerCase().contains(tv.text.toLowerCase())),
              onSelected: (s) => _marcaCtrl.text = s,
              fieldViewBuilder: (ctx, ctrl, fn, oec) {
                ctrl.text = _marcaCtrl.text;
                ctrl.addListener(() => _marcaCtrl.text = ctrl.text);
                return _buildTextField(ctrl, 'Marca', Icons.branding_watermark_outlined, focusNode: fn, onEditingComplete: oec);
              },
            ),
            const SizedBox(height: 14),

            // ── Categoría ─────────────────────────
            DropdownButtonFormField<String>(
              value: _categoriaSeleccionada,
              dropdownColor: Colors.grey.shade900,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('Categoría', Icons.category_outlined),
              items: [
                ..._categoriasDinamicas.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                const DropdownMenuItem(
                  value: _kNuevaCategoriaStr,
                  child: Text(_kNuevaCategoriaStr, style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
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
            const SizedBox(height: 14),

            // ── Precios ───────────────────────────
            Row(
              children: [
                Expanded(
                  child: _campoPrecio(_precioBaseCtrl, 'Precio Unitario *',
                      validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Requerido' : null),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _campoPrecio(_precioMayoristaCtrl, 'Precio Mayorista (3+)'),
                ),
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
        title: const Text('Nueva Categoría', style: TextStyle(color: Colors.white)),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('AÑADIR'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await DBHelper().insertCategory(result);
      await _cargarCategorias();
      setState(() => _categoriaSeleccionada = result);
    } else {
      // Si canceló, volvemos a la primera válida
      if (_categoriasDinamicas.isNotEmpty) {
        setState(() => _categoriaSeleccionada = _categoriasDinamicas.first);
      }
    }
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

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon,
      {FocusNode? focusNode, VoidCallback? onEditingComplete}) {
    return TextField(
      controller: ctrl,
      focusNode: focusNode,
      onEditingComplete: onEditingComplete,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDeco(label, icon),
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
        prefixStyle: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
      ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: Icon(icon, color: Colors.teal),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.teal)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red)),
      );
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
            width: 240, height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.teal, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const Positioned(
          top: 60, left: 0, right: 0,
          child: Text('Centra el producto en el recuadro\nsobre fondo liso para mejor resultado',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        Positioned(
          bottom: 50, left: 0, right: 0,
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
          top: 16, right: 16,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ],
    );
  }
}
