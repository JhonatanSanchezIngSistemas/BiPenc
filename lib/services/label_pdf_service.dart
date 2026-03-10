import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:bipenc/data/models/producto.dart';

class LabelPdfService {
  /// Genera un PDF A4 con etiquetas en cuadrícula.
  /// Cada etiqueta incluye code128 (SKU), nombre y 3 precios (normal/mayorista/especial).
  static Future<File> generateEtiquetasPdf(
    List<Producto> productos, {
    int columns = 3,
    double horizontalPadding = 6,
    double verticalPadding = 6,
  }) async {
    final doc = pw.Document();
    final pageWidth = PdfPageFormat.a4.availableWidth;
    final colWidth =
        (pageWidth - (horizontalPadding * 2 * columns)) / columns;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(12),
        build: (ctx) {
          final tiles = productos
              .map((p) => _labelCard(p, colWidth, horizontalPadding, verticalPadding))
              .toList();
          return [
            pw.Wrap(
              spacing: horizontalPadding,
              runSpacing: verticalPadding,
              children: tiles,
            ),
          ];
        },
      ),
    );

    final tmp = await getTemporaryDirectory();
    final file =
        File('${tmp.path}/etiquetas_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static Future<void> share(File file) async {
    await Share.shareXFiles([XFile(file.path)], text: 'Etiquetas de precios');
  }

  static pw.Widget _labelCard(
      Producto p, double width, double hPad, double vPad) {
    final price1 = p.precioBase.toStringAsFixed(2);
    final price2 = p.precioMayorista.toStringAsFixed(2);
    final price3 = p.precioEspecial.toStringAsFixed(2);

    return pw.Container(
      width: width,
      padding: pw.EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: 0.4),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(p.nombre.toUpperCase(),
              style:
                  pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          if (p.marca.isNotEmpty)
            pw.Text(p.marca,
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.SizedBox(height: 4),
          pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: p.skuCode.isNotEmpty ? p.skuCode : p.id,
            width: width - hPad * 2,
            height: 28,
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _priceChip('P1', price1),
              _priceChip('P2', price2),
              _priceChip('P3', price3),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _priceChip(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey50,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: PdfColors.blueGrey300, width: 0.4),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(
                  fontSize: 7, color: PdfColors.blueGrey700)),
          pw.SizedBox(width: 3),
          pw.Text('S/ $value',
              style: pw.TextStyle(
                  fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}

