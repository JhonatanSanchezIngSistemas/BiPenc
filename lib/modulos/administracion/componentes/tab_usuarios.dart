import 'package:flutter/material.dart';

class TabUsuarios extends StatefulWidget {
  final List<Map<String, dynamic>> usuarios;
  final Future<void> Function(String id, String field, String value) onUpdate;
  final Future<void> Function(String id, Map<String, dynamic> data) onEdit;

  const TabUsuarios({
    super.key,
    required this.usuarios,
    required this.onUpdate,
    required this.onEdit,
  });

  @override
  State<TabUsuarios> createState() => _TabUsuariosState();
}

class _TabUsuariosState extends State<TabUsuarios> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtrados = widget.usuarios.where((u) {
      if (query.isEmpty) return true;
      final nombre = (u['nombre'] ?? '').toString().toLowerCase();
      final apellido = (u['apellido'] ?? '').toString().toLowerCase();
      final alias = (u['alias'] ?? '').toString().toLowerCase();
      return nombre.contains(query) ||
          apellido.contains(query) ||
          alias.contains(query);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar usuario (nombre, alias)',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF141C2B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: filtrados.isEmpty
              ? const Center(
                  child: Text('Sin usuarios coincidentes',
                      style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtrados.length,
                  itemBuilder: (context, i) {
                    final u = filtrados[i];
                    final id = (u['id'] ?? '').toString();
                    final nombre = (u['nombre'] ?? '').toString();
                    final apellido = (u['apellido'] ?? '').toString();
                    final alias = (u['alias'] ?? '').toString();
                    final rol = (u['rol'] ?? 'VENTAS').toString().toUpperCase();

                    return Card(
                      color: Colors.grey.shade900,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.white10),
                      ),
                      child: ListTile(
                        title: Text('$nombre $apellido',
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text('Alias: $alias',
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        trailing: DropdownButton<String>(
                          value: rol,
                          dropdownColor: Colors.grey.shade900,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(value: 'ADMIN', child: Text('ADMIN')),
                            DropdownMenuItem(value: 'VENTAS', child: Text('VENTAS')),
                          ],
                          onChanged: (value) async {
                            if (value == null || value == rol) return;
                            await widget.onUpdate(id, 'rol', value);
                          },
                        ),
                        onTap: () => _editarUsuarioDialog(context, u),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _editarUsuarioDialog(BuildContext context, Map<String, dynamic> u) async {
    final id = (u['id'] ?? '').toString();
    final nombreCtrl = TextEditingController(text: (u['nombre'] ?? '').toString());
    final apellidoCtrl = TextEditingController(text: (u['apellido'] ?? '').toString());
    final aliasCtrl = TextEditingController(text: (u['alias'] ?? '').toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Editar usuario', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _simpleField(nombreCtrl, 'Nombre'),
            const SizedBox(height: 8),
            _simpleField(apellidoCtrl, 'Apellido'),
            const SizedBox(height: 8),
            _simpleField(aliasCtrl, 'Alias'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );

    if (ok == true) {
      await widget.onEdit(id, {
        'nombre': nombreCtrl.text.trim(),
        'apellido': apellidoCtrl.text.trim(),
        'alias': aliasCtrl.text.trim(),
      });
    }
  }

  Widget _simpleField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF141C2B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
