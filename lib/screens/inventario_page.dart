import 'package:flutter/material.dart';
import '../models/producto.dart';
import '../services/local_db_service.dart';
import '../services/supabase_service.dart';
import 'producto_form_page.dart';

class InventarioPage extends StatefulWidget {
  const InventarioPage({super.key});

  @override
  State<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends State<InventarioPage> {
  List<Producto> _productos = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarProductos();
  }

  Future<void> _cargarProductos() async {
    setState(() => _isLoading = true);
    // Intentar buscar todos o usar búsqueda vacía
    final results = await LocalDbService.buscarLocal(_searchController.text);
    setState(() {
      _productos = results;
      _isLoading = false;
    });
  }

  void _abrirFormulario({Producto? p}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductoFormPage(productoExistente: p),
      ),
    );
    if (result == true) _cargarProductos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('Gestión de Inventario'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.tealAccent,
        actions: [
          IconButton(
            onPressed: () => _abrirFormulario(),
            icon: const Icon(Icons.add_circle, size: 28),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _cargarProductos(),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, marca o SKU...',
                prefixIcon: const Icon(Icons.search, color: Colors.tealAccent),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
                : _productos.isEmpty
                    ? const Center(child: Text('No se encontraron productos', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _productos.length,
                        itemBuilder: (context, index) {
                          final p = _productos[index];
                          return Card(
                            color: const Color(0xFF1A1A1A),
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: const Icon(Icons.inventory, color: Colors.grey),
                              title: Text(p.nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              subtitle: Text('${p.marca} • ${p.presentaciones.length} presentaciones', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              trailing: const Icon(Icons.edit, color: Colors.tealAccent, size: 20),
                              onTap: () => _abrirFormulario(p: p),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
