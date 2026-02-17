import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/producto.dart';
import '../services/supabase_service.dart';

class ProductoFormPage extends StatefulWidget {
  const ProductoFormPage({super.key});

  @override
  State<ProductoFormPage> createState() => _ProductoFormPageState();
}

class _ProductoFormPageState extends State<ProductoFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _skuController = TextEditingController();
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _priceController = TextEditingController();
  final _wholesalePriceController = TextEditingController();
  
  File? _image;
  bool _isSaving = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _takePhoto() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );

    if (photo != null) {
      setState(() {
        _image = File(photo.path);
      });
    }
  }

  Future<void> _scanBarcode() async {
    final String? code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Escanear SKU', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white)),
                ],
              ),
            ),
            Expanded(
              child: MobileScanner(
                onDetect: (capture) {
                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                    Navigator.pop(ctx, barcodes.first.rawValue);
                  }
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Text('Apunta la cámara al código de barras', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );

    if (code != null) {
      setState(() {
        _skuController.text = code;
      });
      // Opcional: Podríamos disparar la verificación aquí mismo
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final String sku = _skuController.text;
      
      // 1. Verificar si el SKU ya existe
      final existingProductData = await SupabaseService.obtenerProductoPorSku(sku);
      
      bool isUpdate = false;
      String finalSku = sku;

      if (existingProductData != null && mounted) {
        final action = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('SKU ya existe', style: TextStyle(color: Colors.tealAccent)),
            content: Text('El código "$sku" ya está registrado. ¿Qué deseas hacer?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'duplicate'),
                child: const Text('DUPLICAR (Nuevo ID)', style: TextStyle(color: Colors.orangeAccent)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'update'),
                style: FilledButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
                child: const Text('ACTUALIZAR'),
              ),
            ],
          ),
        );

        if (action == 'cancel' || action == null) {
          setState(() => _isSaving = false);
          return;
        }

        if (action == 'update') {
          isUpdate = true;
        } else if (action == 'duplicate') {
          finalSku = '${sku}_${DateTime.now().millisecondsSinceEpoch}';
          isUpdate = false;
        }
      }

      // 2. Subir imagen si hay una nueva
      String? cloudImageUrl;
      if (_image != null) {
        cloudImageUrl = await SupabaseService.subirImagen(_image!);
      } else if (isUpdate && existingProductData != null) {
        // Mantener la imagen existente si no se tomó una nueva
        cloudImageUrl = existingProductData['imagen_url'];
      }

      final productToSave = Producto(
        id: finalSku,
        nombre: _nameController.text,
        marca: _brandController.text,
        categoria: 'General',
        precioBase: double.parse(_priceController.text),
        precioMayorista: double.parse(_wholesalePriceController.text),
        imagenPath: cloudImageUrl,
      );

      final success = await SupabaseService.upsertProducto(productToSave, isUpdate: isUpdate);

      if (success && mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isUpdate ? 'Producto actualizado' : 'Producto creado en la nube'),
            backgroundColor: Colors.teal,
          ),
        );
      } else if (mounted) {
        throw Exception('Error al guardar en Supabase');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('Nuevo Producto'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.tealAccent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Selector de Imagen
              GestureDetector(
                onTap: _takePhoto,
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.tealAccent.withOpacity(0.3),
                      width: 2,
                    ),
                    image: _image != null
                        ? DecorationImage(
                            image: FileImage(_image!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _image == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.camera_alt_outlined,
                              color: Colors.tealAccent,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Subir Foto',
                              style: TextStyle(
                                color: Colors.tealAccent.withOpacity(0.7),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : Container(
                          alignment: Alignment.bottomRight,
                          padding: const EdgeInsets.all(12),
                          child: CircleAvatar(
                            backgroundColor: Colors.black54,
                            child: IconButton(
                              icon: const Icon(Icons.edit, color: Colors.tealAccent),
                              onPressed: _takePhoto,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 32),

              // Campos del Formulario
              _buildTextField(
                controller: _skuController,
                label: 'Código de Barras (SKU)',
                icon: Icons.qr_code_scanner_outlined,
                validator: (v) => v!.isEmpty ? 'Campo requerido' : null,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.camera_alt, color: Colors.tealAccent),
                  onPressed: _scanBarcode,
                ),
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _nameController,
                label: 'Nombre del Producto',
                icon: Icons.inventory_2_outlined,
                validator: (v) => v!.isEmpty ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _brandController,
                label: 'Marca',
                icon: Icons.branding_watermark_outlined,
                validator: (v) => v!.isEmpty ? 'Campo requerido' : null,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _priceController,
                      label: 'Precio S/',
                      icon: Icons.sell_outlined,
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? 'Requerido' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      controller: _wholesalePriceController,
                      label: 'Mayorista S/',
                      icon: Icons.groups_outlined,
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? 'Requerido' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),

              // Botón Guardar
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveProduct,
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(_isSaving ? 'GUARDANDO...' : 'GUARDAR EN NUBE'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.tealAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500),
        prefixIcon: Icon(icon, color: Colors.tealAccent, size: 22),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.tealAccent, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent),
      ),
    );
  }
}
