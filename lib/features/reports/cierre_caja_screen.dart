import 'package:flutter/material.dart';
import '../../data/local/db_helper.dart';
import '../../data/models/venta.dart';
import 'package:url_launcher/url_launcher.dart';

class CierreCajaScreen extends StatefulWidget {
  const CierreCajaScreen({super.key});

  @override
  State<CierreCajaScreen> createState() => _CierreCajaScreenState();
}

class _CierreCajaScreenState extends State<CierreCajaScreen> {
  bool _isLoading = true;
  double _totalEfectivo = 0;
  double _totalYapePlin = 0;
  double _totalTarjeta = 0;
  List<Venta> _ventasHoy = [];

  @override
  void initState() {
    super.initState();
    _calcularCierreDiario();
  }

  Future<void> _calcularCierreDiario() async {
    // Obtenemos los últimos 100 tickets del día (ajustable en DBHelper)
    final ventas = await DBHelper().getUltimasVentas(limit: 100);
    
    // Filtramos solo los del día actual
    final hoy = DateTime.now();
    _ventasHoy = ventas.where((v) => 
      v.fecha.year == hoy.year && 
      v.fecha.month == hoy.month && 
      v.fecha.day == hoy.day
    ).toList();

    double efe = 0, yap = 0, tar = 0;
    for (var v in _ventasHoy) {
      if (v.metodoPago == MetodoPago.efectivo) efe += v.total;
      else if (v.metodoPago == MetodoPago.yapePlin) yap += v.total;
      else if (v.metodoPago == MetodoPago.tarjeta) tar += v.total;
    }

    if (mounted) {
      setState(() {
        _totalEfectivo = efe;
        _totalYapePlin = yap;
        _totalTarjeta = tar;
        _isLoading = false;
      });
    }
  }

  Future<void> _enviarReporteWhatsApp() async {
    final tTotal = _totalEfectivo + _totalYapePlin + _totalTarjeta;
    final msg = '''*REPORTE DE CAJA Z - BiPenc*
📅 Fecha: \${DateTime.now().toString().substring(0, 10)}
-----------------------------------
💵 Efectivo en Caja: \$\${_totalEfectivo.toStringAsFixed(2)}
📱 Yape/Plin: \$\${_totalYapePlin.toStringAsFixed(2)}
💳 Tarjetas: \$\${_totalTarjeta.toStringAsFixed(2)}
-----------------------------------
💰 TOTAL INGRESOS: \$\${tTotal.toStringAsFixed(2)}
🎟️ Tickets Emitidos: \${_ventasHoy.length}

_Generado automáticamente por BiPenc POS_''';

    final textUrl = Uri.encodeComponent(msg);
    final url = Uri.parse('whatsapp://send?text=\$textUrl');
    
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WhatsApp no está instalado o no se puede abrir.')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al lanzar WhatsApp.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final granTotal = _totalEfectivo + _totalYapePlin + _totalTarjeta;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Cierre de Caja (Z)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Text('TOTAL DEL DÍA', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
                    const SizedBox(height: 8),
                    Text('\$\${granTotal.toStringAsFixed(2)}', style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)),
                    const SizedBox(height: 8),
                    Text('\${_ventasHoy.length} operaciones realizadas', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Desglose Financiero', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(),
            _buildRow('Efectivo Físico', _totalEfectivo, Icons.money, Colors.green),
            _buildRow('Yape / Plin', _totalYapePlin, Icons.qr_code, Colors.purple),
            _buildRow('Tarjetas', _totalTarjeta, Icons.credit_card, Colors.orange),
            
            const SizedBox(height: 40),
            FilledButton.icon(
              onPressed: _enviarReporteWhatsApp,
              icon: const SizedBox(width: 24, height: 24, child: Icon(Icons.share)), // Simulación icono WA
              label: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Compartir Reporte por WhatsApp', style: TextStyle(fontSize: 16)),
              ),
              style: FilledButton.styleFrom(backgroundColor: Colors.teal),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, double amount, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontSize: 18)),
          const Spacer(),
          Text('\$\${amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
