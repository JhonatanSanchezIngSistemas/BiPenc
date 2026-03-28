import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show consolidateHttpClientResponseBytes;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:bipenc/datos/modelos/producto.dart';
import 'package:bipenc/utilidades/fiscal.dart';
import 'package:bipenc/servicios/servicio_db_local.dart';
import 'package:bipenc/servicios/servicio_backend.dart';

/// Generador de PDF minimalista, 2 columnas y sin grillas.
class ServicioPdf {
  static Future<File> generateVentaPdf({
    required List<ItemCarrito> items,
    required double total,
    required String vendedor,
    required String correlativo,
    String? ventaId,
    String? cliente,
    String? dniRuc,
    String tipo = 'BOLETA ELECTRÓNICA',
    String? metodoPago,
    double tasaIgv = 0.18,
    double? subtotalSinIgv,
    double? igvValue,
    String? qrData,
    String? hashCpb,
    double? montoRecibido,
    double? vuelto,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final cfg = await ServicioDbLocal.getEmpresaConfig();
    final empresa = _Empresa.fromMap(cfg);

    // Items fallback a venta_items si la lista viene vacía
    final mappedItems = items.isNotEmpty
        ? _mapItems(items)
        : await _fetchVentaItemsFallback(ventaId: ventaId, correlativo: correlativo);

    final desglose = UtilFiscal.calcularDesglose(total, tasa: tasaIgv);
    final subtotalCalc = subtotalSinIgv ?? desglose.$1;
    final igvCalc = igvValue ?? desglose.$2;
    final fechaStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    final logo = await _loadLogo(empresa.logoUrl);

    final pdf = pw.Document();

    final qrString = qrData ?? _buildSunatQr(
      rucEmisor: empresa.ruc,
      tipoDoc: tipo.toUpperCase().contains('FACTURA') ? '01' : '03',
      correlativo: correlativo,
      total: total,
      igv: igvCalc,
      fechaEmision: DateTime.now(),
      hashCpb: hashCpb,
      dniRuc: dniRuc,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(20),
        header: (_) => _header(empresa, logo, tipo, correlativo, fechaStr, vendedor, metodoPago),
        build: (context) => [
          pw.SizedBox(height: 8),
          _clienteBox(cliente, dniRuc),
          pw.SizedBox(height: 10),
          _productosSection(mappedItems),
          pw.SizedBox(height: 10),
          _totales(subtotalCalc, igvCalc, total, montoRecibido, vuelto),
          pw.SizedBox(height: 10),
          _qrSection(qrString),
          pw.SizedBox(height: 12),
          _terminos(empresa.terminosPdf),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              empresa.footerText,
              style: const pw.TextStyle(fontSize: 9),
              textAlign: pw.TextAlign.center,
            ),
          )
        ],
      ),
    );

    final tempDir = await getTemporaryDirectory();
    final safeCorr = correlativo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('${tempDir.path}/BIPENC_$safeCorr.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _header(_Empresa e, pw.MemoryImage? logo, String tipo,
      String correlativo, String fecha, String vendedor, String? metodoPago) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null)
          pw.Container(
            width: 65,
            height: 65,
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(e.razonSocial, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Text('RUC: ${e.ruc}', style: const pw.TextStyle(fontSize: 10)),
              pw.Text(e.direccion, style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 4),
              pw.Text(tipo, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text('N° $correlativo', style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Fecha: $fecha', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('Vendedor: $vendedor', style: const pw.TextStyle(fontSize: 10)),
            if (metodoPago != null)
              pw.Text('Pago: $metodoPago', style: const pw.TextStyle(fontSize: 10)),
          ],
        )
      ],
    );
  }

  static pw.Widget _clienteBox(String? cliente, String? dniRuc) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('CLIENTE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            pw.Text((cliente ?? 'PÚBLICO GENERAL').toUpperCase(),
                style: const pw.TextStyle(fontSize: 10)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text((dniRuc != null && dniRuc.length == 11) ? 'RUC' : 'DNI',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
            pw.Text(dniRuc ?? '00000000', style: const pw.TextStyle(fontSize: 10)),
          ])
        ],
      ),
    );
  }

  static pw.Widget _productosSection(List<_FilaItem> items) {
    if (items.isEmpty) return pw.SizedBox();

    return pw.Column(
      children: [
        // Header de la tabla (sin bordes)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5)),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(flex: 2, child: pw.Text('CÓDIGO', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
              pw.Expanded(flex: 5, child: pw.Text('DESCRIPCIÓN', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
              pw.Expanded(flex: 1, child: pw.Text('CANT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.right)),
              pw.Expanded(flex: 1, child: pw.Text('P.UNIT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.right)),
              pw.Expanded(flex: 2, child: pw.Text('SUBTOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.right)),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        // Lista de items
        for (final r in items) ...[
          _itemLine(r),
          pw.SizedBox(height: 2),
        ],
        pw.Divider(thickness: 0.5, color: PdfColors.black),
      ],
    );
  }

  static pw.Widget _itemLine(_FilaItem r) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(flex: 2, child: pw.Text(r.sku, style: const pw.TextStyle(fontSize: 9))),
        pw.Expanded(flex: 5, child: pw.Text(r.nombre, style: const pw.TextStyle(fontSize: 9))),
        pw.Expanded(flex: 1, child: pw.Text(r.cant.toString(), style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
        pw.Expanded(flex: 1, child: pw.Text(r.precio, style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
        pw.Expanded(flex: 2, child: pw.Text(r.subtotal, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
      ],
    );
  }

  static pw.Widget _totales(double base, double igv, double total, 
      [double? recibido, double? vuelto]) {
    pw.Widget line(String label, double v) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(width: 10),
            pw.Text('S/. ${v.toStringAsFixed(2)}',
                style: const pw.TextStyle(fontSize: 10)),
          ],
        );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        line('Operación Gravada', base),
        line('IGV (18%)', igv),
        if (recibido != null && recibido > 0) line('Recibido', recibido),
        if (vuelto != null && vuelto > 0) line('Vuelto', vuelto),
        pw.SizedBox(height: 4),
        pw.Text('TOTAL: S/. ${total.toStringAsFixed(2)}',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _qrSection(String? data) {
    if (data == null || data.isEmpty) return pw.SizedBox();
    return pw.BarcodeWidget(
      barcode: pw.Barcode.qrCode(),
      data: data,
      width: 90,
      height: 90,
    );
  }

  static String _buildSunatQr({
    required String rucEmisor,
    required String tipoDoc,
    required String correlativo,
    required double total,
    required double igv,
    required DateTime fechaEmision,
    String? hashCpb,
    String? dniRuc,
  }) {
    final parts = correlativo.split('-');
    final serie = parts.isNotEmpty ? parts.first : '';
    final numero = parts.length > 1 ? parts[1] : correlativo;
    final fechaStr = DateFormat('yyyy-MM-dd').format(fechaEmision);
    final List<String> fields = [
      rucEmisor,
      tipoDoc,
      serie,
      numero,
      igv.toStringAsFixed(2),
      total.toStringAsFixed(2),
      fechaStr,
      (hashCpb ?? '').trim(),
    ];
    if (dniRuc != null && dniRuc.isNotEmpty) {
      fields.add(dniRuc);
    }
    return fields.join('|');
  }

  static pw.Widget _terminos(String terminos) {
    if (terminos.isEmpty) return pw.SizedBox();
    return pw.Text(terminos,
        style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.justify);
  }

  static List<_FilaItem> _mapItems(List<ItemCarrito> items) => items
      .map((i) => _FilaItem(
            cant: i.cantidad,
            nombre: i.producto.nombre,
            sku: i.producto.skuCode,
            precio: i.precioActual.toStringAsFixed(2),
            subtotal: i.subtotal.toStringAsFixed(2),
          ))
      .toList();

  static Future<List<_FilaItem>> _fetchVentaItemsFallback(
      {String? ventaId, String? correlativo}) async {
    final res = await ServicioBackend.fetchVentaItemsSimple(
        ventaId: ventaId, correlativo: correlativo);
    return res
        .map((e) => _FilaItem(
              cant: (e['cantidad'] as num?)?.toInt() ?? 0,
              nombre: (e['descripcion'] ?? e['producto_id'] ?? '').toString(),
              sku: (e['sku'] ?? e['producto_id'] ?? '').toString(),
              precio: ((e['precio_unitario'] ?? 0) as num).toStringAsFixed(2),
              subtotal: ((e['subtotal'] ?? 0) as num).toStringAsFixed(2),
            ))
        .toList();
  }

  static Future<void> shareVentaPdf(File file) async {
    await Share.shareXFiles([XFile(file.path)], text: 'Comprobante BiPenc');
  }

  static Future<pw.MemoryImage?> _loadLogo(String? pathOrUrl) async {
    if (pathOrUrl == null || pathOrUrl.isEmpty) {
      // fallback al logo de assets si existe
      try {
        final bytes = (await rootBundle.load('assets/logo/logo.png')).buffer.asUint8List();
        return pw.MemoryImage(bytes);
      } catch (_) {
        return null;
      }
    }

    try {
      if (pathOrUrl.startsWith('http')) {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(pathOrUrl));
        final response = await request.close();
        if (response.statusCode == 200) {
          final bytes = await consolidateHttpClientResponseBytes(response);
          return pw.MemoryImage(bytes);
        }
        return null;
      }

      final file = File(pathOrUrl);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        return pw.MemoryImage(bytes);
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

class _FilaItem {
  final int cant;
  final String nombre;
  final String sku;
  final String precio;
  final String subtotal;
  _FilaItem({
    required this.cant,
    required this.nombre,
    required this.sku,
    required this.precio,
    required this.subtotal,
  });
}

class _Empresa {
  final String? logoUrl;
  final String ruc;
  final String razonSocial;
  final String direccion;
  final String footerText;
  final String terminosPdf;
  _Empresa({
    this.logoUrl,
    required this.ruc,
    required this.razonSocial,
    required this.direccion,
    required this.footerText,
    required this.terminosPdf,
  });
  factory _Empresa.fromMap(Map<String, dynamic>? m) {
    return _Empresa(
      logoUrl: m?['logo_url']?.toString(),
      ruc: (m?['ruc'] ?? '00000000000').toString(),
      razonSocial: (m?['razon_social'] ?? 'BiPenc').toString(),
      direccion: (m?['direccion'] ?? 'Ciudad Principal').toString(),
      footerText: (m?['footer_text'] ??
              'Gracias por su compra en BiPenc - Representación impresa de la Boleta Electrónica')
          .toString(),
      terminosPdf: (m?['terminos_pdf'] ?? '').toString(),
    );
  }
}
