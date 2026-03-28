import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:bipenc/servicios/servicio_configuracion.dart';
import 'package:bipenc/utilidades/fiscal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bipenc/base/llaves.dart';
import 'package:bipenc/datos/modelos/configuracion_negocio.dart';
import 'package:bipenc/datos/modelos/venta.dart';
import 'package:bipenc/modulos/caja/proveedor_caja.dart';
import 'package:bipenc/servicios/cola_impresion.dart';
import 'package:bipenc/utilidades/registro_app.dart';

part 'impresion/impresion_conexion.dart';
part 'impresion/impresion_imagen.dart';
part 'impresion/impresion_tickets.dart';

abstract class _ImpresionBase {
  final _connectionController = StreamController<bool>.broadcast();
  bool _estaConectado = false;
  Future<void>? _ongoingReconnect;
  int _failedReconnectCount = 0;
  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
}

class ServicioImpresion extends _ImpresionBase
    with _ConexionImpresion, _ImpresionImagen, _ImpresionTickets {
  // ── SINGLETON ──
  static final ServicioImpresion _instance = ServicioImpresion._();
  factory ServicioImpresion() => _instance;
  ServicioImpresion._() {
    _initAutoConnect();
  }

  // ── HARDWARE CONFIG (PT-210) ─────────────────────────────────────────────
  static const String whitelistedMacFallback = '04:7F:0E:4D:18:0F';
  static const int _lineChars58 = 32;
  static const int _lineChars80 = 48;
  static const String _forcedCodePage = 'CP1252';
  static const bool _disableQrOnThermal = true;

  // ── ESTADO ──────────────────────────────────────────────────────────────
  Stream<bool> get connectionStream => _connectionController.stream;

  bool get estaConectado => _estaConectado;

  // ── DEBUG ─────────────────────────────────────────────────────────────────
  static bool debugForceError = false;

  // ── VENDEDOR ──────────────────────────────────────────────────────────────
  static Future<String> _getVendedorAlias() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return 'SISTEMA';
      final response = await Supabase.instance.client
          .from('perfiles')
          .select('alias, nombre')
          .eq('id', user.id)
          .maybeSingle();
      if (response != null) {
        final alias = response['alias'] as String?;
        final nombre = response['nombre'] as String?;
        return alias ??
            nombre ??
            user.email?.split('@').first.toUpperCase() ??
            'VENDEDOR';
      }
      return user.email?.split('@').first.toUpperCase() ?? 'VENDEDOR';
    } catch (e, st) {
      RegistroApp.warn('No se pudo obtener alias vendedor', tag: 'PRINT', error: e, stackTrace: st);
      return 'VENDEDOR';
    }
  }

  static Future<String> obtenerAliasVendedor() async => _getVendedorAlias();

  // ── UTILIDADES ────────────────────────────────────────────────────────────
  static List<String> _wrapText(String text, int maxLength) {
    final lines = <String>[];
    final words = text.split(' ');
    var currentLine = '';

    for (final word in words) {
      if (word.isEmpty) continue;
      if (word.length > maxLength) {
        if (currentLine.isNotEmpty) {
          lines.add(currentLine);
          currentLine = '';
        }
        for (int i = 0; i < word.length; i += maxLength) {
          final end =
              (i + maxLength < word.length) ? i + maxLength : word.length;
          lines.add(word.substring(i, end));
        }
        continue;
      }
      if ((currentLine.length + word.length + (currentLine.isEmpty ? 0 : 1)) <=
          maxLength) {
        currentLine += (currentLine.isEmpty ? '' : ' ') + word;
      } else {
        if (currentLine.isNotEmpty) lines.add(currentLine);
        currentLine = word;
      }
    }
    if (currentLine.isNotEmpty) lines.add(currentLine);
    return lines;
  }

  static String normalizeForEscPos(String input) {
    return input
        .replaceAll('\n', ' ')
        .replaceAll('💳', ' TARJETA ')
        .replaceAll('📱', ' YAPE/PLIN ')
        .replaceAll('💵', ' EFECTIVO ')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
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
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('\t', ' ')
        .trimRight()
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '');
  }

  @visibleForTesting
  static String formatFechaTicket(DateTime fecha) =>
      DateFormat('dd/MM/yyyy HH:mm').format(fecha);

  @visibleForTesting
  static String buildTicketPreview({
    required List<ItemCarrito> items,
    required double total,
    required String serie,
    String? correlativo,
    String? cliente,
    String? dniRuc,
    String tipo = 'TICKET',
    String? vendedor,
    String turnoEstado = 'Abierto',
    String? metodoPago,
    double? montoRecibido,
    double? vuelto,
    double? subtotalSinIgv,
    double? igvValue,
    double tasaIgv = 0.18,
    DateTime? fechaVenta,
  }) {
    final fecha = formatFechaTicket(fechaVenta ?? DateTime.now());
    final correlativoFinal = (correlativo != null && correlativo.contains('-'))
        ? correlativo
        : '$serie-${correlativo ?? "00000"}';
    final subtotal = subtotalSinIgv ?? (total / (1 + tasaIgv));
    final igv = igvValue ?? (total - subtotal);
    final totalItems = items.fold<int>(0, (s, i) => s + i.cantidad);
    final shouldShowVuelto = metodoPago != null &&
        metodoPago.toLowerCase() == 'efectivo' &&
        montoRecibido != null &&
        montoRecibido > 0;
    final sb = StringBuffer()
      ..writeln(fecha)
      ..writeln(tipo.toUpperCase())
      ..writeln(correlativoFinal)
      ..writeln('Cliente: ${(cliente ?? "PUBLICO GENERAL").toUpperCase()}');
    if (dniRuc != null && dniRuc.isNotEmpty && dniRuc != '00000000') {
      sb.writeln('${_labelDocumentoStatic(dniRuc)}: $dniRuc');
    }
    if (vendedor != null && vendedor.isNotEmpty) {
      sb.writeln('Atendido: $vendedor');
      sb.writeln('Turno: $turnoEstado');
    }
    if (metodoPago != null && metodoPago.isNotEmpty) {
      sb.writeln('Pago: ${_labelMetodoPagoStatic(metodoPago)}');
    }
    sb.writeln('Items: $totalItems');
    sb.writeln('Subtotal: ${subtotal.toStringAsFixed(2)}');
    sb.writeln('IGV: ${igv.toStringAsFixed(2)}');
    if (shouldShowVuelto) {
      final vueltoCalc =
          (vuelto ?? (montoRecibido - total)).clamp(0, double.infinity);
      sb.writeln('Recibido: ${montoRecibido.toStringAsFixed(2)}');
      sb.writeln('Vuelto: ${vueltoCalc.toStringAsFixed(2)}');
    }
    sb.writeln('TOTAL: ${total.toStringAsFixed(2)}');
    if (correlativoFinal.contains('-')) {
      sb.writeln('QR: SI');
    }
    return sb.toString();
  }

  /// Public wrapper para usar preview de ticket fuera de tests.
  static String renderTicketPreview({
    required List<ItemCarrito> items,
    required double total,
    required String serie,
    String? correlativo,
    String? cliente,
    String? dniRuc,
    String tipo = 'TICKET',
    String? vendedor,
    String turnoEstado = 'Abierto',
    String? metodoPago,
    double? montoRecibido,
    double? vuelto,
    double? subtotalSinIgv,
    double? igvValue,
    double tasaIgv = 0.18,
    DateTime? fechaVenta,
  }) {
    return buildTicketPreview(
      items: items,
      total: total,
      serie: serie,
      correlativo: correlativo,
      cliente: cliente,
      dniRuc: dniRuc,
      tipo: tipo,
      vendedor: vendedor,
      turnoEstado: turnoEstado,
      metodoPago: metodoPago,
      montoRecibido: montoRecibido,
      vuelto: vuelto,
      subtotalSinIgv: subtotalSinIgv,
      igvValue: igvValue,
      tasaIgv: tasaIgv,
      fechaVenta: fechaVenta,
    );
  }

  String _normalize(String input) => normalizeForEscPos(input);

  List<int> _printCentered(
    Generator generator,
    String text, {
    bool bold = false,
    int width = _lineChars58,
  }) {
    final out = <int>[];
    final normalized = _normalize(text);
    final lines = _wrapText(normalized, width);
    for (final line in lines) {
      out.addAll(generator.text(
        line,
        styles: PosStyles(
          bold: bold,
          align: PosAlign.center,
        ),
      ));
    }
    return out;
  }

  String _lineTotal(String label, num amount, {int width = 32}) {
    final left = '$label:';
    final right = 'S/. ${amount.toStringAsFixed(2)}';
    final spaces = width - left.length - right.length;
    if (spaces <= 1) return '$left $right';
    return '$left${' ' * spaces}$right';
  }

  List<String> _buildItemLines({
    required ItemCarrito item,
    required int qtyCol,
    required int productCol,
    required int amountCol,
    required int lineWidth,
  }) {
    return _buildItemLinesCore(
      nombre: item.producto.nombre,
      cantidad: item.cantidad,
      precioUnitario: item.precioActual,
      subtotal: item.subtotal,
      qtyCol: qtyCol,
      productCol: productCol,
      amountCol: amountCol,
      lineWidth: lineWidth,
    );
  }

  static List<String> _buildItemLinesCore({
    required String nombre,
    required int cantidad,
    required double precioUnitario,
    required double subtotal,
    required int qtyCol,
    required int productCol,
    required int amountCol,
    required int lineWidth,
  }) {
    final normalizedName = normalizeForEscPos(
      (nombre.trim().isEmpty ? 'PRODUCTO' : nombre).toUpperCase(),
    );
    final nameLines = _wrapText(normalizedName, productCol);
    final out = <String>[];

    final qtyText = '${cantidad}x';
    final amountText = 'S/.${subtotal.toStringAsFixed(2)}';

    if (nameLines.isEmpty) {
      out.add(
        '${qtyText.padRight(qtyCol)} ${'PRODUCTO'.padRight(productCol)} ${amountText.padLeft(amountCol)}',
      );
    } else {
      out.add(
        '${qtyText.padRight(qtyCol)} ${_safePadRight(nameLines.first, productCol)} ${amountText.padLeft(amountCol)}',
      );
      for (int i = 1; i < nameLines.length; i++) {
        out.add(
          '${''.padRight(qtyCol)} ${_safePadRight(nameLines[i], productCol)} ${''.padLeft(amountCol)}',
        );
      }
    }

    final detailLeft = 'P.U.: ${precioUnitario.toStringAsFixed(2)}';
    final detailRight = 'Sub: ${subtotal.toStringAsFixed(2)}';
    out.add(_lineJoin(detailLeft, detailRight, lineWidth));
    return out;
  }

  static String _safePadRight(String value, int width) {
    if (value.length >= width) return value.substring(0, width);
    return value.padRight(width);
  }

  static String _lineJoin(String left, String right, int width) {
    final l = left.trim();
    final r = right.trim();
    final spaces = width - l.length - r.length;
    if (spaces >= 2) {
      return '$l${' ' * spaces}$r';
    }
    final shortLeft = l.length > width - r.length - 1
        ? l.substring(0, (width - r.length - 1).clamp(0, l.length))
        : l;
    return '$shortLeft $r';
  }

  @visibleForTesting
  static List<String> buildItemPreviewLines({
    required String nombre,
    required int cantidad,
    required double precioUnitario,
    required double subtotal,
    required int lineWidth,
    required bool is80mm,
  }) {
    final qtyCol = is80mm ? 6 : 4;
    final amountCol = is80mm ? 14 : 12;
    final productCol = (lineWidth - qtyCol - amountCol - 2).clamp(10, 40);
    return _buildItemLinesCore(
      nombre: nombre,
      cantidad: cantidad,
      precioUnitario: precioUnitario,
      subtotal: subtotal,
      qtyCol: qtyCol,
      productCol: productCol,
      amountCol: amountCol,
      lineWidth: lineWidth,
    );
  }

  @visibleForTesting
  static List<String> wrapForTicket(String text, int width) {
    return _wrapText(normalizeForEscPos(text), width);
  }

  static String _labelDocumentoStatic(String value) {
    final doc = value.replaceAll(RegExp(r'\D'), '');
    if (doc.length == 11) return 'RUC';
    if (doc.length == 8) return 'DNI';
    return 'DOC';
  }

  static String _labelMetodoPagoStatic(String metodo) {
    final m = metodo.trim().toLowerCase();
    if (m == 'yapeplin' || m == 'yape_plin') return 'YAPE/PLIN';
    if (m == 'tarjeta') return 'TARJETA';
    if (m == 'efectivo') return 'EFECTIVO';
    return metodo.toUpperCase();
  }

}
