import 'package:flutter/material.dart';

class TabUsuarios extends StatefulWidget {
  final List<Map<String, dynamic>> usuarios;
  final Future<void> Function(String id, String field, String value) onUpdate;
  final Future<void> Function(String id, Map<String, dynamic> data) onEdit;
  final Future<void> Function(String email, String nombre, String apellido, String rol) onInvite;
  final Future<void> Function(String id, String estado) onEstado;

  const TabUsuarios({
    super.key,
    required this.usuarios,
    required this.onUpdate,
    required this.onEdit,
    required this.onInvite,
    required this.onEstado,
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
          child: Row(
            children: [
              Expanded(
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
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _invitarUsuarioDialog(context),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Invitar'),
              ),
            ],
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
                    final estado = (u['estado'] ?? 'ACTIVO').toString().toUpperCase();

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
                        subtitle: Text('Alias: $alias • Estado: $estado',
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DropdownButton<String>(
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
                            const SizedBox(width: 6),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: Colors.white54),
                              color: const Color(0xFF1A1A2E),
                              onSelected: (value) async {
                                await widget.onEstado(id, value);
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'ACTIVO',
                                  child: Text('ACTIVAR', style: TextStyle(color: Colors.greenAccent)),
                                ),
                                const PopupMenuItem(
                                  value: 'INACTIVO',
                                  child: Text('DESACTIVAR', style: TextStyle(color: Colors.redAccent)),
                                ),
                              ],
                            ),
                          ],
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

  Future<void> _invitarUsuarioDialog(BuildContext context) async {
    final emailCtrl = TextEditingController();
    final nombreCtrl = TextEditingController();
    final apellidoCtrl = TextEditingController();
    String rol = 'VENTAS';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Invitar usuario', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _simpleField(emailCtrl, 'Email'),
            const SizedBox(height: 8),
            _simpleField(nombreCtrl, 'Nombre'),
            const SizedBox(height: 8),
            _simpleField(apellidoCtrl, 'Apellido'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: rol,
              dropdownColor: const Color(0xFF1A1A2E),
              items: const [
                DropdownMenuItem(value: 'VENTAS', child: Text('VENTAS')),
                DropdownMenuItem(value: 'ADMIN', child: Text('ADMIN')),
              ],
              onChanged: (value) => rol = value ?? 'VENTAS',
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF141C2B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enviar')),
        ],
      ),
    );

    if (ok == true) {
      await widget.onInvite(
        emailCtrl.text.trim(),
        nombreCtrl.text.trim(),
        apellidoCtrl.text.trim(),
        rol,
      );
    }
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
