import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../servicios/servicio_db_local.dart';
import '../../servicios/servicio_backend.dart';

class PantallaConfigEmpresa extends StatefulWidget {
  const PantallaConfigEmpresa({super.key});

  @override
  State<PantallaConfigEmpresa> createState() => _PantallaConfigEmpresaState();
}

class _PantallaConfigEmpresaState extends State<PantallaConfigEmpresa> {
  final _formKey = GlobalKey<FormState>();
  final _rucCtrl = TextEditingController();
  final _razonCtrl = TextEditingController();
  final _dirCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _ticketHeaderCtrl = TextEditingController();
  final _ticketFooterCtrl = TextEditingController();
  final _pdfTerminosCtrl = TextEditingController();
  File? _logoFile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final local = await ServicioDbLocal.getEmpresaConfig();
    final cfg = local ?? await ServicioBackend.getEmpresaConfig();
    if (cfg != null) {
      _rucCtrl.text = cfg['ruc']?.toString() ?? '';
      _razonCtrl.text = cfg['razon_social']?.toString() ?? '';
      _dirCtrl.text = cfg['direccion']?.toString() ?? '';
      _telCtrl.text = cfg['telefono']?.toString() ?? '';
      _ticketHeaderCtrl.text = cfg['ticket_header']?.toString() ?? '';
      _ticketFooterCtrl.text = cfg['ticket_footer']?.toString() ?? '';
      _pdfTerminosCtrl.text = cfg['pdf_terminos']?.toString() ?? '';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) setState(() => _logoFile = File(file.path));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final map = {
      'ruc': _rucCtrl.text.trim(),
      'razon_social': _razonCtrl.text.trim(),
      'direccion': _dirCtrl.text.trim(),
      'telefono': _telCtrl.text.trim(),
      'ticket_header': _ticketHeaderCtrl.text.trim(),
      'ticket_footer': _ticketFooterCtrl.text.trim(),
      'pdf_terminos': _pdfTerminosCtrl.text.trim(),
    };
    await ServicioDbLocal.upsertEmpresaConfig(map);
    await ServicioBackend.upsertEmpresaConfig(map);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración guardada')));
    }
  }

  @override
  void dispose() {
    _rucCtrl.dispose();
    _razonCtrl.dispose();
    _dirCtrl.dispose();
    _telCtrl.dispose();
    _ticketHeaderCtrl.dispose();
    _ticketFooterCtrl.dispose();
    _pdfTerminosCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Identidad y Comprobantes')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundImage:
                      _logoFile != null ? FileImage(_logoFile!) : null,
                  child: _logoFile == null
                      ? const Icon(Icons.image_outlined)
                      : null,
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _pickLogo,
                  icon: const Icon(Icons.upload),
                  label: const Text('Subir logo'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _field('RUC', _rucCtrl),
            _field('Razón Social', _razonCtrl),
            _field('Dirección', _dirCtrl),
            _field('Teléfono', _telCtrl),
            _field('Encabezado Ticket', _ticketHeaderCtrl),
            _field('Pie Ticket', _ticketFooterCtrl),
            _field('Términos (PDF)', _pdfTerminosCtrl, maxLines: 4),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Guardar'),
            ),
            const SizedBox(height: 16),
            const Text('Previsualización rápida (ticket)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Card(
              color: Colors.grey.shade900,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${_ticketHeaderCtrl.text}\n${_razonCtrl.text}\nRUC: ${_rucCtrl.text}\n${_direccionPreview()}\n${_ticketFooterCtrl.text}',
                  style: const TextStyle(color: Colors.white70, fontFamily: 'monospace'),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
        validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
      ),
    );
  }

  String _direccionPreview() {
    final dir = _dirCtrl.text.trim();
    final tel = _telCtrl.text.trim();
    if (dir.isEmpty && tel.isEmpty) return '';
    if (dir.isEmpty) return 'Tel: $tel';
    if (tel.isEmpty) return dir;
    return '$dir | Tel: $tel';
  }
}
