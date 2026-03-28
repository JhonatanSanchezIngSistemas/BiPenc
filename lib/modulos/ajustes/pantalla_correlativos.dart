import 'package:flutter/material.dart';
import 'package:bipenc/servicios/servicio_db_local.dart';
import 'package:bipenc/servicios/servicio_backend.dart';
import 'package:bipenc/servicios/servicio_configuracion.dart';

/// Gestión de series y correlativos por tipo de comprobante (boleta/factura).
/// Sincroniza con Supabase y persiste en SQLite.
class PantallaCorrelativos extends StatefulWidget {
  const PantallaCorrelativos({super.key});

  @override
  State<PantallaCorrelativos> createState() => _PantallaCorrelativosState();
}

class _PantallaCorrelativosState extends State<PantallaCorrelativos> {
  final _formKey = GlobalKey<FormState>();
  final _serieBoletaCtrl = TextEditingController(text: 'B001');
  final _serieFacturaCtrl = TextEditingController(text: 'F001');
  final _numeroBoletaCtrl = TextEditingController(text: '0');
  final _numeroFacturaCtrl = TextEditingController(text: '0');
  bool _modoPrueba = false;
  bool _loading = true;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final localBoleta =
        await ServicioDbLocal.getCorrelativoConfig(tipoDoc: '03');
    final localFactura =
        await ServicioDbLocal.getCorrelativoConfig(tipoDoc: '01');
    if (localBoleta != null) {
      _serieBoletaCtrl.text = localBoleta['serie']?.toString() ?? 'B001';
      _numeroBoletaCtrl.text =
          (localBoleta['ultimo_numero'] ?? 0).toString();
    }
    if (localFactura != null) {
      _serieFacturaCtrl.text = localFactura['serie']?.toString() ?? 'F001';
      _numeroFacturaCtrl.text =
          (localFactura['ultimo_numero'] ?? 0).toString();
    }
    _modoPrueba = await ServicioConfiguracion.getModoPrueba();

    // Pull Supabase y merge (server gana)
    final remotos = await ServicioBackend.obtenerConfigCorrelativos();
    if (remotos.isNotEmpty) {
      await ServicioDbLocal.syncCorrelativosDesdeSupabase(remotos);
      final b = remotos.firstWhere(
          (r) => (r['tipo_documento'] ?? '') == '03',
          orElse: () => {});
      final f = remotos.firstWhere(
          (r) => (r['tipo_documento'] ?? '') == '01',
          orElse: () => {});
      if (b.isNotEmpty) {
        _serieBoletaCtrl.text = b['serie'] ?? 'B001';
        _numeroBoletaCtrl.text = (b['ultimo_numero'] ?? 0).toString();
      }
      if (f.isNotEmpty) {
        _serieFacturaCtrl.text = f['serie'] ?? 'F001';
        _numeroFacturaCtrl.text = (f['ultimo_numero'] ?? 0).toString();
      }
    }
    setState(() => _loading = false);
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final boletaSerie = _serieBoletaCtrl.text.trim().toUpperCase();
    final boletaNum = int.tryParse(_numeroBoletaCtrl.text.trim()) ?? 0;
    final facturaSerie = _serieFacturaCtrl.text.trim().toUpperCase();
    final facturaNum = int.tryParse(_numeroFacturaCtrl.text.trim()) ?? 0;

    await ServicioDbLocal.setCorrelativoManual(
        tipoDoc: '03', serie: boletaSerie, ultimoNumero: boletaNum);
    await ServicioDbLocal.setCorrelativoManual(
        tipoDoc: '01', serie: facturaSerie, ultimoNumero: facturaNum);

    await ServicioBackend.upsertConfigCorrelativo(
        tipoDocumento: '03', serie: boletaSerie, ultimoNumero: boletaNum);
    await ServicioBackend.upsertConfigCorrelativo(
        tipoDocumento: '01', serie: facturaSerie, ultimoNumero: facturaNum);

    await ServicioConfiguracion.setModoPrueba(_modoPrueba);

    setState(() => _msg = 'Guardado y sincronizado correctamente');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Series y Correlativos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    _card(
                      title: 'Boletas (03)',
                      serieCtrl: _serieBoletaCtrl,
                      numeroCtrl: _numeroBoletaCtrl,
                    ),
                    const SizedBox(height: 12),
                    _card(
                      title: 'Facturas (01)',
                      serieCtrl: _serieFacturaCtrl,
                      numeroCtrl: _numeroFacturaCtrl,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      title: const Text('Modo Prueba'),
                      subtitle: const Text(
                          'Muestra "DOCUMENTO NO VÁLIDO / PRUEBA" en tickets'),
                      value: _modoPrueba,
                      onChanged: (v) => setState(() => _modoPrueba = v),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Guardar'),
                      onPressed: _guardar,
                    ),
                    if (_msg != null) ...[
                      const SizedBox(height: 8),
                      Text(_msg!,
                          style: const TextStyle(
                              color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _card({
    required String title,
    required TextEditingController serieCtrl,
    required TextEditingController numeroCtrl,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextFormField(
              controller: serieCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Serie (ej. B001)'),
              validator: (v) =>
                  v != null && v.trim().isNotEmpty ? null : 'Requerido',
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: numeroCtrl,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Último número emitido'),
              validator: (v) =>
                  int.tryParse(v ?? '') != null ? null : 'Ingresa un número',
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _serieBoletaCtrl.dispose();
    _serieFacturaCtrl.dispose();
    _numeroBoletaCtrl.dispose();
    _numeroFacturaCtrl.dispose();
    super.dispose();
  }
}
