import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/camera_service.dart';
import '../../services/image_processing_service.dart';
import '../../data/models/product.dart';
import '../../data/local/db_helper.dart';

class ProductoFormScreen extends StatefulWidget {
  const ProductoFormScreen({super.key});

  @override
  State<ProductoFormScreen> createState() => _ProductoFormScreenState();
}

class _ProductoFormScreenState extends State<ProductoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers de datos básicos
  final _descController = TextEditingController();
  final _marcaController = TextEditingController();
  final _codigoController = TextEditingController();
  final _categoriaController = TextEditingController();

  // Lista dinámica para Presentaciones
  final List<PresentacionInput> _presentacionesInputs = [
    PresentacionInput(nombre: 'Unidad', cantidad: 1) // Base por defecto
  ];

  // Servicios de IA y Sensores
  final CameraService _cameraService = CameraService();
  final ImageProcessingService _imageService = ImageProcessingService();
  
  XFile? _imagenCapturada;
  bool _isCameraReady = false;
  bool _isProcessingImage = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    await _cameraService.initialize();
    if (mounted) {
      setState(() => _isCameraReady = true);
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    _marcaController.dispose();
    _codigoController.dispose();
    _categoriaController.dispose();
    _cameraService.dispose();
    _imageService.close();
    super.dispose();
  }

  /// Flujo Visual Completo: Apertura Nativa -> Captura -> Compresión WebP -> Análisis IA
  Future<void> _tomarYProcesarFoto() async {
    if (!_isCameraReady) return;

    // Abrimos un BottomSheet a pantalla completa con el lente de la cámara
    final XFile? captured = await showModalBottomSheet<XFile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) => _CameraPreviewModal(cameraService: _cameraService),
    );

    if (captured != null) {
      setState(() => _isProcessingImage = true);

      // 1. Compresión Masiva WebP (Escudo de ancho de banda)
      final compressedFile = await _imageService.comprimirImagen(captured);
      final finalImage = compressedFile ?? captured;

      // 2. IA de Segmentación Visual 
      // Calculamos la máscara para separar el producto del fondo
      final SegmentationMask? mask = await _imageService.processImageBackground(finalImage.path);

      setState(() {
        _imagenCapturada = finalImage;
        _isProcessingImage = false;
      });

      if (mounted) {
        // Notificamos sutilmente que la IA detectó las siluetas
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mask != null 
              ? 'IA: Silueta base del producto mapeada correctamente.' 
              : 'Foto guardada (Segmentación no disponible)'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    }
  }

  void _agregarPresentacion() {
    setState(() {
      _presentacionesInputs.add(PresentacionInput());
    });
  }

  void _guardarProducto() async {
    if (_formKey.currentState!.validate()) {
      if (_presentacionesInputs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debe existir al menos una Presentación.')),
        );
        return;
      }
      
      // Armamos la lista de presentaciones tipadas
      final presList = _presentacionesInputs.map((pi) => Presentacion(
        nombre: pi.nombre,
        cantidadPorEmpaque: pi.cantidad,
        precioUnitario: pi.precioU,
        precioMayor: pi.precioM,
      )).toList();

      String? finalImagePath;
      if (_imagenCapturada != null) {
        try {
          // Guardado interno definitivo (Cero Galería local)
          final docDir = await getApplicationDocumentsDirectory();
          final imgName = 'prod_${DateTime.now().millisecondsSinceEpoch}.webp';
          final newPath = '${docDir.path}/$imgName';
          
          await File(_imagenCapturada!.path).copy(newPath);
          finalImagePath = newPath;
          
        } catch (e) {
          debugPrint('Error en la gestión de imagen: $e');
        } finally {
          // AUTO-LIMPIEZA GARANTIZADA: El bloque finally asegura que el archivo
          // temporal se elimine incluso si la copia falla o el disco está lleno.
          try {
             final tmpFile = File(_imagenCapturada!.path);
             if (await tmpFile.exists()) {
               await tmpFile.delete();
             }
          } catch(e) {
             debugPrint('Error en el Garbage Collector de fotos: $e');
          }
        }
      }

      // Ensamblamos el Producto Raíz
      final product = Product(
        id: DateTime.now().millisecondsSinceEpoch.toString(), // ID único temporal
        descripcion: _descController.text,
        marca: _marcaController.text,
        codigoBarras: _codigoController.text.isEmpty ? 'SIN_CODIGO' : _codigoController.text,
        categoria: _categoriaController.text,
        imagenUrl: finalImagePath,
        requiereAutorizacion: false, // Por ahora fijo
        presentaciones: presList,
      );
      
      try {
        await DBHelper().insertProduct(product);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Producto guardado en Base de Datos Local.'), backgroundColor: Colors.teal),
          );
          context.pop(true); // Retorna a inventario indicando que hubo éxito
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar Producto')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _guardarProducto,
        icon: const Icon(Icons.save),
        label: const Text('Guardar'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // --- SECCIÓN 1: VISTA PREVIA IA Y CÁMARA ---
            Center(
              child: GestureDetector(
                onTap: _tomarYProcesarFoto,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).primaryColor, width: 2),
                    image: _imagenCapturada != null
                        ? DecorationImage(
                            image: FileImage(File(_imagenCapturada!.path)),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _isProcessingImage 
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 8),
                          Text('IA Analizando...', style: TextStyle(fontSize: 12))
                        ],
                      )
                    : _imagenCapturada == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt, size: 50, color: Theme.of(context).primaryColor),
                            const Text('Tocar para foto', style: TextStyle(fontWeight: FontWeight.bold))
                          ],
                        )
                      : const Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(Icons.stars, color: Colors.amber, size: 30), // Indicador de IA lista
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // --- SECCIÓN 2: DATOS BÁSICOS ---
            Text('Datos Principales', style: Theme.of(context).textTheme.titleLarge),
            const Divider(),
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Descripción del Producto', border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return const Iterable<String>.empty();
                      }
                      // Simulación de diccionario local cargado de BD
                      const marcasExistentes = ['Faber-Castell', 'Standford', 'Pilot', 'Artesco', 'Vinifan'];
                      return marcasExistentes.where((String option) {
                        return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                      });
                    },
                    onSelected: (String selection) {
                      _marcaController.text = selection;
                    },
                    fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                      // Sincronizamos con el controlador global del form
                      controller.text = _marcaController.text;
                      controller.addListener(() => _marcaController.text = controller.text);
                      
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        onEditingComplete: onEditingComplete,
                        decoration: const InputDecoration(labelText: 'Marca', border: OutlineInputBorder()),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _categoriaController,
                    decoration: const InputDecoration(labelText: 'Categoría', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _codigoController,
              decoration: InputDecoration(
                labelText: 'Código de Barras', 
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () { /* TODO: Integrar mobile_scanner */ },
                ),
              ),
            ),
            const SizedBox(height: 32),

            // --- SECCIÓN 3: GESTOR DE PRESENTACIONES DINÁMICAS ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Presentaciones', style: Theme.of(context).textTheme.titleLarge),
                TextButton.icon(
                  onPressed: _agregarPresentacion,
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir'),
                ),
              ],
            ),
            const Divider(),
            ..._presentacionesInputs.asMap().entries.map((entry) {
              int index = entry.key;
              PresentacionInput pInput = entry.value;
              return Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              initialValue: pInput.nombre,
                              decoration: const InputDecoration(labelText: 'Nombre (Ej. Docena)', isDense: true),
                              onChanged: (v) => pInput.nombre = v,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: pInput.cantidad.toString(),
                              decoration: const InputDecoration(labelText: 'Cnt.', isDense: true),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => pInput.cantidad = int.tryParse(v) ?? 1,
                            ),
                          ),
                          if (index > 0)
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => setState(() => _presentacionesInputs.removeAt(index)),
                            )
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              decoration: const InputDecoration(labelText: 'Precio Unit.', isDense: true, prefixText: '\$'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (v) => pInput.precioU = double.tryParse(v) ?? 0.0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              decoration: const InputDecoration(labelText: 'P. Mayor (Opc)', isDense: true, prefixText: '\$'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (v) => pInput.precioM = double.tryParse(v) ?? 0.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 80), // Espacio para el FAB
          ],
        ),
      ),
    );
  }
}

/// Helper para manejar el estado temporal de los TextFields dinámicos.
class PresentacionInput {
  String nombre;
  int cantidad;
  double precioU;
  double precioM;
  PresentacionInput({this.nombre = '', this.cantidad = 1, this.precioU = 0.0, this.precioM = 0.0});
}

/// Modal a pantalla completa para el visor en vivo del lente.
class _CameraPreviewModal extends StatelessWidget {
  final CameraService cameraService;
  const _CameraPreviewModal({required this.cameraService});

  @override
  Widget build(BuildContext context) {
    if (cameraService.controller == null) return const Center(child: CircularProgressIndicator());
    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(cameraService.controller!),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: FloatingActionButton.large(
              onPressed: () async {
                final file = await cameraService.takePicture();
                if (context.mounted) Navigator.pop(context, file); // Cierra vista e inyecta la foto
              },
              backgroundColor: Colors.white,
              child: const Icon(Icons.camera, color: Colors.black, size: 40),
            ),
          ),
        ),
        Positioned(
          top: 40,
          right: 20,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 30),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ],
    );
  }
}
