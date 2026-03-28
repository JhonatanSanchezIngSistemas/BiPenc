import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../servicios/servicio_pdf.dart';

class TabCierreCaja extends StatefulWidget {
  final double totalHoy;
  final double efectivoHoy;
  final double yapePlinHoy;
  final int conteoVentas;
  final Future<void> Function()? onRefresh;

  const TabCierreCaja({
    super.key,
    required this.totalHoy,
    required this.efectivoHoy,
    required this.yapePlinHoy,
    required this.conteoVentas,
    this.onRefresh,
  });

  @override
  State<TabCierreCaja> createState() => _TabCierreCajaState();
}

class _TabCierreCajaState extends State<TabCierreCaja> {
  bool _exportingPdf = false;

  Future<void> _enviarWhatsApp() async {
    final fecha = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final msg = '''*CIERRE DE CAJA - $fecha*

Ventas: ${widget.conteoVentas}
Efectivo: S/.${widget.efectivoHoy.toStringAsFixed(2)}
Yape/Plin: S/.${widget.yapePlinHoy.toStringAsFixed(2)}
TOTAL: S/.${widget.totalHoy.toStringAsFixed(2)}
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

  Future<void> _exportarPdf() async {
    if (_exportingPdf) return;
    setState(() => _exportingPdf = true);
    try {
      final file = await ServicioPdf.generateResumenCierrePdf(
        fecha: DateTime.now(),
        total: widget.totalHoy,
        efectivo: widget.efectivoHoy,
        yapePlin: widget.yapePlinHoy,
        ventas: widget.conteoVentas,
      );
      await Share.shareXFiles([XFile(file.path)], text: 'Resumen cierre de caja');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo generar el PDF'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fechaLabel = DateFormat('EEEE, d MMMM yyyy', 'es').format(DateTime.now());

    return RefreshIndicator(
      onRefresh: widget.onRefresh ?? () async {},
      displacement: 20,
      color: Colors.tealAccent,
      backgroundColor: Colors.grey.shade900,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Header del Resumen
          Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.tealAccent,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(color: Colors.tealAccent.withValues(alpha: 0.5), blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CONTROL DE CIERRE',
                    style: TextStyle(
                      color: Colors.tealAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 2.0,
                    ),
                  ),
                  Text(
                    fechaLabel.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Grid de Métricas con Estilo Diamond
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.4,
            children: [
              _metricDiamondCard(
                label: 'BALANCE TOTAL',
                value: widget.totalHoy,
                color: Colors.amberAccent,
                icon: Icons.account_balance_wallet,
                isTotal: true,
              ),
              _metricDiamondCard(
                label: 'EFECTIVO',
                value: widget.efectivoHoy,
                color: Colors.tealAccent,
                icon: Icons.payments_outlined,
              ),
              _metricDiamondCard(
                label: 'DIGITAL (Y/P)',
                value: widget.yapePlinHoy,
                color: Colors.purpleAccent,
                icon: Icons.qr_code_2,
              ),
              _countDiamondCard(
                label: 'OPERACIONES',
                value: widget.conteoVentas,
                icon: Icons.receipt_long_outlined,
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Sección de Exportación
          const Text(
            'EXPORTAR REPORTES',
            style: TextStyle(
              color: Colors.white24,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _BotonExport(
                  onTap: _enviarWhatsApp,
                  icon: Icons.chat_bubble_outline,
                  label: 'WhatsApp',
                  color: Colors.greenAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BotonExport(
                  onTap: _exportingPdf ? null : _exportarPdf,
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'PDF Oficial',
                  color: Colors.redAccent,
                  isLoading: _exportingPdf,
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          
          // Disclaimer/Info
          Center(
            child: Text(
              'Este resumen incluye todas las ventas confirmadas hasta el momento.\nLos pedidos cancelados no afectan el balance.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.15), fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  // --- DIAMOND UI COMPONENTS ---

  Widget _metricDiamondCard({
    required String label,
    required double value,
    required Color color,
    required IconData icon,
    bool isTotal = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              bottom: -10,
              child: Icon(icon, size: 60, color: color.withValues(alpha: 0.05)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
                      Icon(icon, color: color, size: 16),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('S/.', style: TextStyle(color: Colors.white24, fontSize: 10)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          value.toStringAsFixed(2),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isTotal ? 22 : 18,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Courier', // Look mas contable
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countDiamondCard({required String label, required int value, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
              Icon(icon, color: Colors.white38, size: 16),
            ],
          ),
          Text(
            '$value',
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _BotonExport extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final String label;
  final Color color;
  final bool isLoading;

  const _BotonExport({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.color,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          color: color.withValues(alpha: 0.05),
        ),
        child: Center(
          child: isLoading
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: color))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: 8),
                    Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
        ),
      ),
    );
  }
}
