import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/producto.dart';
import '../utils/precio_engine.dart';

class PdfService {
  static Future<File> generateVentaPdf({
    required List<ItemCarrito> items,
    required double total,
    required String vendedor,
    required String correlativo,
    String? cliente,
    String? dniRuc,
    String tipo = 'TICKET',
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final desglose = PrecioEngine.calcularDesgloseFiscal(total);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text('BIPENC LIBRERÍA',
                      style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Center(child: pw.Text('Calidad y Servicio al Mejor Precio')),
                pw.Center(child: pw.Text('RUC: 10XXXXXXXXX')),
                pw.SizedBox(height: 20),
                pw.Divider(),
                pw.Center(
                  child: pw.Text('$tipo DE VENTA',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Center(child: pw.Text(correlativo)),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Text('FECHA: ${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}'),
                pw.Text('VENDEDOR: $vendedor'),
                if (cliente != null) pw.Text('CLIENTE: ${cliente.toUpperCase()}'),
                if (dniRuc != null) pw.Text('DNI/RUC: $dniRuc'),
                pw.SizedBox(height: 20),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  children: [
                    pw.TableRow(
                      children: [
                        _buildPdfHeaderCell('Descripción'),
                        _buildPdfHeaderCell('Cant.'),
                        _buildPdfHeaderCell('Total'),
                      ],
                    ),
                    ...items.map((item) => pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text('${item.presentacion.nombre} ${item.producto.nombre}'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(item.cantidad.toString()),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text('S/ ${(item.precioActual * item.cantidad).toStringAsFixed(2)}'),
                        ),
                      ],
                    )),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('SUBTOTAL: S/ ${desglose.subtotal.toStringAsFixed(2)}'),
                        pw.Text('IGV (18%): S/ ${desglose.igv.toStringAsFixed(2)}'),
                        pw.SizedBox(height: 5),
                        pw.Text('TOTAL A PAGAR: S/ ${total.toStringAsFixed(2)}',
                            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                pw.Spacer(),
                pw.Center(child: pw.Text('¡GRACIAS POR SU PREFERENCIA!')),
                pw.Center(child: pw.Text('BIPENC - Ing. Jhonatan Gamarra')),
              ],
            ),
          );
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/BIPENC_$correlativo.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static Future<void> shareVentaPdf(File file) async {
    await Share.shareXFiles([XFile(file.path)], text: 'Comprobante de Venta BIPENC');
  }

  static pw.Widget _buildPdfHeaderCell(String text) {
    return pw.Container(
      decoration: const pw.BoxDecoration(color: PdfColors.teal),
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
      ),
    );
  }
}
