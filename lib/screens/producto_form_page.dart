import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/producto.dart';
import '../repositories/producto_repository.dart';
import '../services/session_service.dart';
import '../utils/app_logger.dart';

/// Formulario para crear o editar un producto con sus presentaciones.
/// Soporta subida de imagen a Supabase Storage, dropdown de categorías,
/// y gestión dinámica de presentaciones.
class ProductoFormPage extends StatefulWidget {
  final Producto? productoExistente;

  const ProductoFormPage({super.key, this.productoExistente});

  @override
  State<ProductoFormPage> createState() => _ProductoFormPageState();
}

class _ProductoFormPageState extends State<ProductoFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _skuController = TextEditingController();
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();

  String _categoriaSeleccionada = CategoriasProducto.lista.first;
  List<_PresentationEntry> _presentaciones = [];
  File? _imagenLocal;
  String? _imagenUrlExistente;
  bool _isSaving = false;

  final ImagePicker _picker = ImagePicker();
  final _repo = ProductoRepository();
  final _session = SessionService();

  bool get _esEdicion => widget.productoExistente != null;

  @override
  void initState() {
    super.initState();
    _initForm();
  }

  void _initForm() {
    final p = widget.productoExistente;
    if (p != null) {
      _skuController.text = p.id;
      _nameController.text = p.nombre;
      _brandController.text = p.marca;
      _categoriaSeleccionada = CategoriasProducto.lista.contains(p.categoria)
          ? p.categoria
          : CategoriasProducto.lista.first;
      _imagenUrlExistente = p.imagenPath;
      _presentaciones = p.presentaciones
          .map((pres) => _PresentationEntry.fromPresentacion(pres))
          .toList();
    } else {
      // Presentación por defecto
      _presentaciones = [
        _PresentationEntry(
          id: 'unid',
          name: TextEditingController(text: 'Unidad'),
          factor: TextEditingController(text: '1'),
          price: TextEditingController(),
          barcode: TextEditingController(),
        ),
      ];
    }
  }

  @override
  void dispose() {
    _skuController.dispose();
    _nameController.dispose();
    _brandController.dispose();
    for (final e in _presentaciones) {
      e.dispose();
    }
    super.dispose();
  }

  // ──────────────────────────────────────────────
  // Imagen
  // ──────────────────────────────────────────────

  Future<void> _seleccionarImagen(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 800,
      );
      if (picked != null && mounted) {
        setState(() => _imagenLocal = File(picked.path));
      }
    } catch (e) {
      AppLogger.error('Error seleccionando imagen', tag: 'FORM', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al acceder a la cámara/galería: $e')),
        );
      }
    }
  }

  void _mostrarOpcionesImagen() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.tealAccent),
              title: const Text('Tomar foto', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _seleccionarImagen(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.tealAccent),
              title: const Text('Elegir de galería', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _seleccionarImagen(ImageSource.gallery);
              },
            ),
            if (_imagenLocal != null || _imagenUrlExistente != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Eliminar imagen', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  setState(() {
                    _imagenLocal = null;
                    _imagenUrlExistente = null;
                  });
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Escáner de códigos de barras
  // ──────────────────────────────────────────────

  Future<void> _escanear(TextEditingController controller) async {
    final String? code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ScannerModal(),
    );
    if (code != null && mounted) {
      setState(() => controller.text = code);
    }
  }

  // ──────────────────────────────────────────────
  // Presentaciones
  // ──────────────────────────────────────────────

  void _agregarPresentacion({String id = '', String nombre = '', int factor = 1, double precio = 0}) {
    setState(() {
      _presentaciones.add(_PresentationEntry(
        id: id.isNotEmpty ? id : 'pres_${DateTime.now().millisecondsSinceEpoch}',
        name: TextEditingController(text: nombre),
        factor: TextEditingController(text: factor.toString()),
        price: TextEditingController(text: precio > 0 ? precio.toStringAsFixed(2) : ''),
        barcode: TextEditingController(),
      ));
    });
  }

  void _agregarPresentacionEstandar(String tipo) {
    final yaExiste = _presentaciones.any((p) => p.id == tipo);
    if (yaExiste) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ya existe la presentación "$tipo"'), duration: const Duration(seconds: 1)),
      );
      return;
    }
    switch (tipo) {
      case 'mayo':
        _agregarPresentacion(id: 'mayo', nombre: 'Mayorista', factor: 1);
        break;
      case 'c12':
        _agregarPresentacion(id: 'c12', nombre: 'Caja x12', factor: 12);
        break;
      case 'c72':
        _agregarPresentacion(id: 'c72', nombre: 'Caja x72', factor: 72);
        break;
      default:
        _agregarPresentacion();
    }
  }

  void _eliminarPresentacion(int index) {
    if (_presentaciones.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe existir al menos una presentación')),
      );
      return;
    }
    setState(() {
      _presentaciones[index].dispose();
      _presentaciones.removeAt(index);
    });
  }

  // ──────────────────────────────────────────────
  // Guardado
  // ──────────────────────────────────────────────

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    // Validar que haya al menos una presentación con precio válido
    for (int i = 0; i < _presentaciones.length; i++) {
      final e = _presentaciones[i];
      final precio = double.tryParse(e.price.text.replaceAll(',', '.'));
      if (precio == null || precio <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('El precio de la presentación ${i + 1} debe ser mayor a 0')),
        );
        return;
      }
      final factor = int.tryParse(e.factor.text);
      if (factor == null || factor <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('El factor de la presentación ${i + 1} es inválido')),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final presentaciones = _presentaciones.map((e) => Presentacion(
        id: e.id,
        nombre: e.name.text.trim(),
        factor: int.parse(e.factor.text.trim()),
        precio: double.parse(e.price.text.replaceAll(',', '.')),
        codigoBarras: e.barcode.text.isNotEmpty ? e.barcode.text.trim() : null,
      )).toList();

      final producto = Producto(
        id: _skuController.text.trim().toUpperCase(),
        nombre: _nameController.text.trim().toUpperCase(),
        marca: _brandController.text.trim().toUpperCase(),
        categoria: _categoriaSeleccionada,
        presentaciones: presentaciones,
        // Mantener URL existente si no hay imagen nueva
        imagenPath: _imagenLocal == null ? _imagenUrlExistente : null,
      );

      final perfil = _session.perfil;
      final error = _esEdicion
          ? await _repo.actualizar(
              producto: producto,
              userAlias: perfil?.alias ?? '???',
              userRol: perfil?.rol ?? 'VENTAS',
              imagen: _imagenLocal,
            )
          : await _repo.guardar(
              producto: producto,
              userAlias: perfil?.alias ?? '???',
              userRol: perfil?.rol ?? 'VENTAS',
              imagen: _imagenLocal,
            );

      if (!mounted) return;

      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_esEdicion ? '✅ Producto actualizado correctamente' : '✅ Producto guardado correctamente'),
            backgroundColor: const Color(0xFF2ECC71),
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $error'), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      AppLogger.error('Error inesperado al guardar producto', tag: 'FORM', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error inesperado: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ──────────────────────────────────────────────
  // UI
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.tealAccent),
        ),
        title: Text(
          _esEdicion ? 'Editar Producto' : 'Nuevo Producto',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent))),
            )
          else
            TextButton(
              onPressed: _guardar,
              child: const Text('GUARDAR', style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildImageSection(),
            const SizedBox(height: 20),
            _buildInfoSection(),
            const SizedBox(height: 24),
            _buildPresentacionesSection(),
            const SizedBox(height: 32),
            _buildGuardarButton(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Sección de imagen ──
  Widget _buildImageSection() {
    Widget imageContent;

    if (_imagenLocal != null) {
      imageContent = Image.file(_imagenLocal!, fit: BoxFit.cover);
    } else if (_imagenUrlExistente != null && _imagenUrlExistente!.startsWith('http')) {
      imageContent = CachedNetworkImage(
        imageUrl: _imagenUrlExistente!,
        fit: BoxFit.cover,
        placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Colors.tealAccent)),
        errorWidget: (_, __, ___) => _buildImagePlaceholder(),
      );
    } else {
      imageContent = _buildImagePlaceholder();
    }

    return GestureDetector(
      onTap: _mostrarOpcionesImagen,
      child: Container(
        height: 160,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF1E1E2C),
          border: Border.all(
            color: Colors.tealAccent.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: imageContent),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.camera_alt, color: Colors.tealAccent, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _imagenLocal != null || _imagenUrlExistente != null
                          ? 'Cambiar imagen'
                          : 'Agregar imagen (opcional)',
                      style: const TextStyle(color: Colors.tealAccent, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_outlined, color: Colors.tealAccent.withOpacity(0.3), size: 48),
        const SizedBox(height: 8),
        Text('Toca para agregar imagen', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
      ],
    );
  }

  // ── Sección de información ──
  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('INFORMACIÓN DEL PRODUCTO',
              style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 16),

          // SKU con escáner
          _buildTextField(
            controller: _skuController,
            label: 'SKU / Código',
            icon: Icons.qr_code,
            textCapitalization: TextCapitalization.characters,
            suffix: IconButton(
              icon: const Icon(Icons.qr_code_scanner, color: Colors.tealAccent, size: 22),
              tooltip: 'Escanear código',
              onPressed: () => _escanear(_skuController),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'El SKU es requerido';
              if (v.trim().length < 3) return 'Mínimo 3 caracteres';
              return null;
            },
          ),
          const SizedBox(height: 14),

          // Nombre
          _buildTextField(
            controller: _nameController,
            label: 'Nombre del Producto',
            icon: Icons.inventory_2_outlined,
            textCapitalization: TextCapitalization.words,
            validator: (v) => v == null || v.trim().isEmpty ? 'El nombre es requerido' : null,
          ),
          const SizedBox(height: 14),

          // Marca
          _buildTextField(
            controller: _brandController,
            label: 'Marca',
            icon: Icons.branding_watermark_outlined,
            textCapitalization: TextCapitalization.words,
            validator: (v) => v == null || v.trim().isEmpty ? 'La marca es requerida' : null,
          ),
          const SizedBox(height: 14),

          // Categoría — Dropdown
          _buildDropdownCategoria(),
        ],
      ),
    );
  }

  Widget _buildDropdownCategoria() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Categoría', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _categoriaSeleccionada,
              dropdownColor: const Color(0xFF1E1E2C),
              style: const TextStyle(color: Colors.white),
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.tealAccent),
              items: CategoriasProducto.lista.map((cat) {
                return DropdownMenuItem(
                  value: cat,
                  child: Row(
                    children: [
                      Icon(_iconoCategoria(cat), color: Colors.tealAccent, size: 20),
                      const SizedBox(width: 10),
                      Text(cat),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _categoriaSeleccionada = val);
              },
            ),
          ),
        ),
      ],
    );
  }

  // ── Sección de presentaciones ──
  Widget _buildPresentacionesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PRESENTACIONES',
                      style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  SizedBox(height: 2),
                  Text('Cómo se vende el producto y su precio',
                      style: TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Chips de presentaciones estándar
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildChipAgregar('+ Mayorista', 'mayo'),
              const SizedBox(width: 8),
              _buildChipAgregar('+ Caja x12', 'c12'),
              const SizedBox(width: 8),
              _buildChipAgregar('+ Caja x72', 'c72'),
              const SizedBox(width: 8),
              _buildChipAgregar('+ Personalizada', 'custom'),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Lista de presentaciones
        ...List.generate(_presentaciones.length, (i) {
          return _buildPresentacionCard(i, _presentaciones[i]);
        }),
      ],
    );
  }

  Widget _buildChipAgregar(String label, String tipo) {
    return ActionChip(
      label: Text(label, style: const TextStyle(color: Colors.tealAccent, fontSize: 12)),
      backgroundColor: Colors.tealAccent.withOpacity(0.08),
      side: BorderSide(color: Colors.tealAccent.withOpacity(0.3)),
      onPressed: () => _agregarPresentacionEstandar(tipo),
    );
  }

  Widget _buildPresentacionCard(int index, _PresentationEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado de la presentación
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Text('${index + 1}', style: const TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              const Text('Presentación', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (index > 0 || _presentaciones.length > 1)
                GestureDetector(
                  onTap: () => _eliminarPresentacion(index),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.close, color: Colors.redAccent, size: 16),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Nombre + Factor
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _buildSmallField(
                  controller: entry.name,
                  hint: 'Ej: Unidad, Caja x12...',
                  label: 'Nombre',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: _buildSmallField(
                  controller: entry.factor,
                  hint: '1',
                  label: 'Factor',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Precio + Código de barras
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildSmallField(
                  controller: entry.price,
                  hint: '0.00',
                  label: 'Precio S/',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  prefixText: 'S/ ',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: _buildSmallField(
                  controller: entry.barcode,
                  hint: 'Código de barras',
                  label: 'Cód. Barras (opc.)',
                  suffix: IconButton(
                    icon: const Icon(Icons.qr_code_scanner, size: 18, color: Colors.tealAccent),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _escanear(entry.barcode),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGuardarButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _guardar,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.tealAccent,
          foregroundColor: Colors.black,
          disabledBackgroundColor: Colors.tealAccent.withOpacity(0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _isSaving
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
            : Text(
                _esEdicion ? 'ACTUALIZAR PRODUCTO' : 'GUARDAR PRODUCTO',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
      ),
    );
  }

  // ── Helpers de campos ──

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    Widget? suffix,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      textCapitalization: textCapitalization,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade500),
        prefixIcon: Icon(icon, color: Colors.tealAccent, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.tealAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildSmallField({
    required TextEditingController controller,
    required String hint,
    required String label,
    TextInputType? keyboardType,
    Widget? suffix,
    String? prefixText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            prefixText: prefixText,
            prefixStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: suffix,
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.tealAccent, width: 1),
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconoCategoria(String cat) {
    switch (cat) {
      case 'Cuadernos': return Icons.menu_book_rounded;
      case 'Lapiceros': return Icons.edit;
      case 'Arte': return Icons.palette;
      case 'Útiles': return Icons.build_circle_outlined;
      case 'Papelería': return Icons.article_outlined;
      case 'Mochilas': return Icons.backpack_outlined;
      case 'Tecnología': return Icons.devices_outlined;
      default: return Icons.category_outlined;
    }
  }
}

// ──────────────────────────────────────────────
// Modelo interno de entrada de presentación
// ──────────────────────────────────────────────

class _PresentationEntry {
  final String id;
  final TextEditingController name;
  final TextEditingController factor;
  final TextEditingController price;
  final TextEditingController barcode;

  _PresentationEntry({
    required this.id,
    required this.name,
    required this.factor,
    required this.price,
    required this.barcode,
  });

  factory _PresentationEntry.fromPresentacion(Presentacion p) {
    return _PresentationEntry(
      id: p.id,
      name: TextEditingController(text: p.nombre),
      factor: TextEditingController(text: p.factor.toString()),
      price: TextEditingController(text: p.precio > 0 ? p.precio.toStringAsFixed(2) : ''),
      barcode: TextEditingController(text: p.codigoBarras ?? ''),
    );
  }

  void dispose() {
    name.dispose();
    factor.dispose();
    price.dispose();
    barcode.dispose();
  }
}

// ──────────────────────────────────────────────
// Modal de escáner
// ──────────────────────────────────────────────

class _ScannerModal extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.65,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('Escanear Código', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
          ),
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                final b = capture.barcodes;
                if (b.isNotEmpty && b.first.rawValue != null) {
                  Navigator.pop(context, b.first.rawValue);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
