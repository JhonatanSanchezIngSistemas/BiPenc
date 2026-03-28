import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../servicios/servicio_db_local.dart';
import '../../servicios/servicio_backend.dart';

class PantallaCierreCaja extends StatefulWidget {
  const PantallaCierreCaja({super.key});

  @override
  State<PantallaCierreCaja> createState() => _PantallaCierreCajaState();
}

class _PantallaCierreCajaState extends State<PantallaCierreCaja> {
  bool _isLoading = true;

  int? _turnoId;
  String? _turnoAbiertoAt;
  double _montoApertura = 0;

  double _totalEfectivo = 0;
  double _totalYapePlin = 0;
  double _totalTarjeta = 0;
  int _conteoVentas = 0;

  double get _granTotal => _totalEfectivo + _totalYapePlin + _totalTarjeta;
  double get _teoricoEfectivoCaja => _montoApertura + _totalEfectivo;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    final resumen = await ServicioDbLocal.obtenerResumenTurnoActual();
    final turno = resumen['turno'] as Map<String, dynamic>?;
    if (!mounted) return;
    setState(() {
      _turnoId = turno == null ? null : (turno['id'] as num).toInt();
      _turnoAbiertoAt = turno?['abierto_at']?.toString();
      _montoApertura = turno == null ? 0 : ((turno['monto_apertura'] ?? 0) as num).toDouble();
      _conteoVentas = (resumen['conteo_ventas'] as int?) ?? 0;
      _totalEfectivo = ((resumen['total_efectivo'] ?? 0) as num).toDouble();
      _totalYapePlin = ((resumen['total_yapeplin'] ?? 0) as num).toDouble();
      _totalTarjeta = ((resumen['total_tarjeta'] ?? 0) as num).toDouble();
      _isLoading = false;
    });
  }

  Future<void> _abrirTurno() async {
    final ctrl = TextEditingController(text: '0.00');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abrir turno de caja'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Monto de apertura (efectivo)',
            border: OutlineInputBorder(),
            prefixText: 'S/. ',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Abrir')),
        ],
      ),
    );
    if (ok != true) return;

    final monto = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
    final alias = await ServicioBackend.obtenerAliasVendedorActual();
    await ServicioDbLocal.abrirTurnoCaja(montoApertura: monto, aliasUsuario: alias);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Turno de caja abierto')),
    );
  }

  Future<void> _cerrarTurno() async {
    if (_turnoId == null) return;
    final ctrl = TextEditingController(text: _teoricoEfectivoCaja.toStringAsFixed(2));
    final obsCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar turno de caja'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Teórico en caja: S/. ${_teoricoEfectivoCaja.toStringAsFixed(2)}'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto real contado',
                  border: OutlineInputBorder(),
                  prefixText: 'S/. ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: obsCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Observaciones (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cerrar turno')),
        ],
      ),
    );
    if (ok != true) return;

    final real = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0;
    final alias = await ServicioBackend.obtenerAliasVendedorActual();
    final closed = await ServicioDbLocal.cerrarTurnoCaja(
      turnoId: _turnoId!,
      montoCierreReal: real,
      aliasUsuario: alias,
      observaciones: obsCtrl.text.trim().isEmpty ? null : obsCtrl.text.trim(),
    );
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(closed ? 'Turno cerrado correctamente' : 'No se pudo cerrar el turno'),
        backgroundColor: closed ? Colors.green : Colors.redAccent,
      ),
    );
  }

  Future<void> _enviarReporteWhatsApp() async {
    if (_turnoId == null) return;
    final msg = '''*REPORTE TURNO CAJA - BiPenc*
🕒 Apertura: ${_turnoAbiertoAt ?? '-'}
-----------------------------------
💵 Apertura: S/.${_montoApertura.toStringAsFixed(2)}
💵 Efectivo Ventas: S/.${_totalEfectivo.toStringAsFixed(2)}
📱 Yape/Plin: S/.${_totalYapePlin.toStringAsFixed(2)}
💳 Tarjetas: S/.${_totalTarjeta.toStringAsFixed(2)}
-----------------------------------
🎟️ Tickets: $_conteoVentas
💰 Total Ventas: S/.${_granTotal.toStringAsFixed(2)}
🧾 Teórico en Caja: S/.${_teoricoEfectivoCaja.toStringAsFixed(2)}
''';

    final textUrl = Uri.encodeComponent(msg);
    final url = Uri.parse('https://wa.me/?text=$textUrl');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir WhatsApp')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0E1422), Color(0xFF101827), Color(0xFF0F0F1A)],
            ),
          ),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final theme = Theme.of(context);
    final hayTurnoAbierto = _turnoId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Caja por Turno'), backgroundColor: const Color(0xFF121B2B)),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E1422), Color(0xFF101827), Color(0xFF0F0F1A)],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              color: hayTurnoAbierto
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hayTurnoAbierto ? 'Turno abierto' : 'Sin turno abierto',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('Apertura: ${_turnoAbiertoAt ?? '-'}'),
                    Text('Monto apertura: S/. ${_montoApertura.toStringAsFixed(2)}'),
                    const SizedBox(height: 12),
                    if (!hayTurnoAbierto)
                      FilledButton.icon(
                        onPressed: _abrirTurno,
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('Abrir turno'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _cerrarTurno,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Cerrar turno'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildRow('Tickets válidos', _conteoVentas.toDouble(), Icons.receipt_long, Colors.blue, isCurrency: false),
            _buildRow('Efectivo ventas', _totalEfectivo, Icons.money, Colors.green),
            _buildRow('Yape / Plin', _totalYapePlin, Icons.qr_code, Colors.purple),
            _buildRow('Tarjetas', _totalTarjeta, Icons.credit_card, Colors.orange),
            const Divider(height: 30),
            _buildRow('Total ventas', _granTotal, Icons.payments_outlined, Colors.teal),
            _buildRow('Teórico en caja', _teoricoEfectivoCaja, Icons.account_balance_wallet_outlined, Colors.indigo),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: hayTurnoAbierto ? _enviarReporteWhatsApp : null,
              icon: const Icon(Icons.share),
              label: const Text('Compartir reporte por WhatsApp'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                setState(() => _isLoading = true);
                try {
                  await ServicioBackend.subirVentasPendientes();
                  await ServicioBackend.procesarSyncQueue();
                  await ServicioBackend.procesarSyncQueueV2();
                  final purged = await ServicioDbLocal.purgarDatosAntiguos();
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text('Sincronización exitosa. Datos purgados: $purged')),
                  );
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Sincronizar ahora'),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(
    String label,
    double value,
    IconData icon,
    Color color, {
    bool isCurrency = true,
  }) {
    final text = isCurrency ? 'S/. ${value.toStringAsFixed(2)}' : value.toInt().toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.1),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
