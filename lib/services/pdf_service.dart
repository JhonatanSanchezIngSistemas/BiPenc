import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../data/models/producto.dart';
import '../utils/fiscal_utils.dart';

class PdfService {
  static Future<File> generateVentaPdf({
    required List<ItemCarrito> items,
    required double total,
    required String vendedor,
    required String correlativo,
    String? cliente,
    String? dniRuc,
    String tipo = 'TICKET',
    String? metodoPago,
    double? montoRecibido,
    double? vuelto,
    double tasaIgv = 0.18,
    double? subtotalSinIgv,
    double? igvValue,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final fechaStr = DateFormat('dd/MM/yyyy HH:mm').format(now);
    final desglose = FiscalUtils.calcularDesglose(total, tasa: tasaIgv);
    final subtotalCalc = subtotalSinIgv ?? desglose.$1;
    final igvCalc = igvValue ?? desglose.$2;
    final igvPercentLabel = (tasaIgv * 100).toStringAsFixed(0);
    final totalItems = items.fold<int>(0, (s, i) => s + i.cantidad);
    final prefs = await SharedPreferences.getInstance();

    final pdfNombre = prefs.getString('pdf_nombre') ?? prefs.getString('biz_nombre') ?? 'BIPENC LIBRERÍA';
    final pdfRuc = prefs.getString('pdf_ruc') ?? prefs.getString('biz_ruc') ?? '00000000000';
    final pdfDireccion = prefs.getString('pdf_dir') ?? prefs.getString('biz_dir') ?? 'Ciudad Principal';
    final pdfFooter = prefs.getString('pdf_footer') ?? '¡GRACIAS POR SU PREFERENCIA!';
    final pdfAutor = prefs.getString('pdf_autor') ?? '';
    final pdfLogoPath = prefs.getString('pdf_logo_path') ?? '';
    final pdfTagline = prefs.getString('pdf_tagline') ?? 'Calidad y Servicio';
    final pdfTel = prefs.getString('pdf_tel') ?? '';
    final pdfShowQr = prefs.getBool('pdf_show_qr') ?? true;
    String safe(String s) => s
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('ñ', 'n')
        .replaceAll('Ñ', 'N')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '');

    pw.MemoryImage? logoImage;
    try {
      if (pdfLogoPath.isNotEmpty) {
        final logoFile = File(pdfLogoPath);
        if (await logoFile.exists()) {
          final logoBytes = await logoFile.readAsBytes();
          logoImage = pw.MemoryImage(logoBytes);
        }
      }
      logoImage ??= pw.MemoryImage(
        (await rootBundle.load('assets/logo/logo.png')).buffer.asUint8List(),
      );
    } catch (_) {
      logoImage = null;
    }

    final qrContent = _buildQrSunatContent(
      ruc: pdfRuc,
      tipo: tipo,
      correlativo: correlativo,
      total: total,
      igv: igvCalc,
      dniRuc: dniRuc,
    );

    final itemCardWidth = (pageFormat.width - 40) / 2; // padding lateral 20px

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
        ),
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (logoImage != null)
                          pw.Container(
                            decoration: pw.BoxDecoration(
                              borderRadius: pw.BorderRadius.circular(8),
                              border: pw.Border.all(color: PdfColors.teal200, width: 0.5),
                            ),
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Image(logoImage, width: 70, height: 70),
                          ),
                        if (logoImage != null) pw.SizedBox(height: 8),
                        pw.Text(safe(pdfNombre),
                            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
                        pw.Text(safe(pdfTagline), style: const pw.TextStyle(fontSize: 10)),
                        pw.Text('RUC: ${safe(pdfRuc)}', style: const pw.TextStyle(fontSize: 10)),
                        if (pdfTel.isNotEmpty)
                          pw.Text('TEL/WA: ${safe(pdfTel)}', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(safe(pdfDireccion), style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(tipo,
                            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                        pw.Text(correlativo, style: const pw.TextStyle(fontSize: 12)),
                        pw.SizedBox(height: 8),
                        pw.Text('Fecha: $fechaStr', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text('Vendedor: $vendedor', style: const pw.TextStyle(fontSize: 10)),
                        if (metodoPago != null && metodoPago.isNotEmpty)
                          pw.Text('Pago: ${safe(_labelMetodoPago(metodoPago))}', style: const pw.TextStyle(fontSize: 10)),
                        if (dniRuc != null && dniRuc.isNotEmpty)
                          pw.Text('${_labelDocumento(dniRuc)}: ${safe(dniRuc)}', style: const pw.TextStyle(fontSize: 10)),
                        if (cliente != null)
                          pw.Text('Cliente: ${safe(cliente.toUpperCase())}', style: const pw.TextStyle(fontSize: 10)),
                        if (qrContent != null && pdfShowQr)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 12),
                            child: pw.Container(
                              padding: const pw.EdgeInsets.all(6),
                              decoration: pw.BoxDecoration(
                                  border: pw.Border.all(color: PdfColors.teal200),
                                  borderRadius: pw.BorderRadius.circular(8)),
                              child: pw.BarcodeWidget(
                                barcode: pw.Barcode.qrCode(),
                                data: qrContent,
                                width: 90,
                                height: 90,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                pw.SizedBox(height: 18),
                pw.Divider(color: PdfColors.grey500),

                // Items en dos columnas (cards compactas)
                pw.Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: items.map((item) {
                    final totalItem = item.precioActual * item.cantidad;
                    return pw.Container(
                      width: itemCardWidth,
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey50,
                        border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
                        borderRadius: pw.BorderRadius.circular(10),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(safe('${item.presentacion.name} ${item.producto.nombre}'),
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                          pw.SizedBox(height: 4),
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('Cant: ${item.cantidad}', style: const pw.TextStyle(fontSize: 10)),
                              pw.Text('P.U: ${item.precioActual.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 10)),
                            ],
                          ),
                          pw.Text('Total: S/ ${totalItem.toStringAsFixed(2)}',
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        ],
                      ),
                    );
                  }).toList(),
                ),

                pw.SizedBox(height: 18),
                pw.Divider(color: PdfColors.grey500),

                // Totales + QR optional
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Resumen', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.Text('Items: $totalItems'),
                          pw.Text('Correlativo: $correlativo'),
                          pw.Text('Operación Gravada: S/ ${subtotalCalc.toStringAsFixed(2)}'),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(12),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.blueGrey50,
                          borderRadius: pw.BorderRadius.circular(12),
                          border: pw.Border.all(color: PdfColors.blueGrey200, width: 0.8),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('SUBTOTAL: S/ ${subtotalCalc.toStringAsFixed(2)}'),
                            pw.Text('IGV ($igvPercentLabel%): S/ ${igvCalc.toStringAsFixed(2)}'),
                            if (metodoPago != null &&
                                metodoPago.toLowerCase() == 'efectivo' &&
                                montoRecibido != null &&
                                montoRecibido > 0)
                              pw.Text('RECIBIDO: S/ ${montoRecibido.toStringAsFixed(2)}'),
                            if (metodoPago != null &&
                                metodoPago.toLowerCase() == 'efectivo' &&
                                montoRecibido != null &&
                                montoRecibido > 0)
                              pw.Text('VUELTO: S/ ${(vuelto ?? (montoRecibido - total)).clamp(0, double.infinity).toStringAsFixed(2)}'),
                            pw.SizedBox(height: 4),
                            pw.Text('TOTAL: S/ ${total.toStringAsFixed(2)}',
                                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                pw.Spacer(),
                pw.Center(child: pw.Text(safe(pdfFooter))),
                if (pdfAutor.isNotEmpty) pw.Center(child: pw.Text(safe(pdfAutor))),
              ],
            ),
          );
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final cleanCorrelativo = correlativo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('${output.path}/BIPENC_$cleanCorrelativo.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static Future<void> shareVentaPdf(File file) async {
    await Share.shareXFiles([XFile(file.path)], text: 'Comprobante de Venta BIPENC');
  }

  static Future<void> enviarPorWhatsApp(File file, String telefono, String mensaje) async {
    // Para PDF, compartimos el archivo directamente indicando WhatsApp si es posible
    // o simplemente usamos Share.shareXFiles que es lo más robusto en Android/iOS
    await Share.shareXFiles(
      [XFile(file.path)],
      text: mensaje,
    );
  }

  static String _labelDocumento(String value) {
    final doc = value.replaceAll(RegExp(r'\\D'), '');
    if (doc.length == 11) return 'RUC';
    if (doc.length == 8) return 'DNI';
    return 'DOC';
  }

  static String _labelMetodoPago(String metodo) {
    final m = metodo.trim().toLowerCase();
    if (m == 'yapeplin' || m == 'yape_plin' || m == 'yape/plin') return 'YAPE/PLIN';
    if (m == 'tarjeta') return 'TARJETA';
    if (m == 'efectivo') return 'EFECTIVO';
    return metodo.toUpperCase();
  }

  static String? _buildQrSunatContent({
    required String ruc,
    required String tipo,
    required String correlativo,
    required double total,
    required double igv,
    String? dniRuc,
  }) {
    if (correlativo.trim().isEmpty) return null;
    final serie = correlativo.contains('-')
        ? correlativo.split('-').first
        : 'B001';
    final corr = correlativo.contains('-')
        ? correlativo.split('-').last
        : correlativo;
    final tipoDoc = tipo.toUpperCase().contains('FACTURA') ? '01' : '03';
    final parts = [
      ruc,
      tipoDoc,
      serie,
      corr,
      igv.toStringAsFixed(2),
      total.toStringAsFixed(2),
      dniRuc ?? '',
      DateTime.now().millisecondsSinceEpoch.toString(),
    ];
    return parts.join('|');
  }
}
