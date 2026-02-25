import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bipenc/data/models/business_config.dart';
import 'package:bipenc/features/pos/pos_provider.dart';

class PrintService {
  /// Obtiene la configuración de negocio salvada en caché
  Future<BusinessConfig> _getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return BusinessConfig(
      nombre: prefs.getString('biz_nombre') ?? 'Librería BiPenc',
      ruc: prefs.getString('biz_ruc') ?? '00000000000',
      direccion: prefs.getString('biz_dir') ?? 'Ciudad Principal',
      telefono: prefs.getString('biz_tel') ?? '123456789',
      mensajeDespedida: prefs.getString('biz_msg') ?? '¡Gracias por su compra!',
    );
  }

  /// Imprime el ticket usando ESC/POS
  Future<bool> imprimirTicketCortesia(PosProvider estadoPos, {double ahorroMayorista = 0.0}) async {
    final conectado = await PrintBluetoothThermal.connectionStatus;
    if (!conectado) return false;

    final config = await _getConfig();
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    // --- ENCABEZADO ---
    bytes += generator.text(config.nombre.toUpperCase(),
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          bold: true,
        ));
    
    bytes += generator.text('RUC/NIT: ${config.ruc}', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text(config.direccion, styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Tel: ${config.telefono}', styles: const PosStyles(align: PosAlign.center));
    // VENDEDOR INFO
    final user = Supabase.instance.client.auth.currentUser;
    final vendedor = user?.email ?? 'Cajero';
    bytes += generator.text('Vendedor: $vendedor', styles: const PosStyles(align: PosAlign.left));
    bytes += generator.feed(1);
    
    // INFO COMPRA
    bytes += generator.text('Fecha: ${DateTime.now().toString().substring(0, 16)}');
    bytes += generator.text('--------------------------------', styles: const PosStyles(align: PosAlign.center));

    // --- CABECERA TABLA ---
    bytes += generator.row([
      PosColumn(text: 'Cant', width: 2),
      PosColumn(text: 'Desc', width: 6),
      PosColumn(text: 'P.U.', width: 2),
      PosColumn(text: 'Tot', width: 2),
    ]);
    bytes += generator.text('--------------------------------', styles: const PosStyles(align: PosAlign.center));

    // --- PRODUCTOS ---
    for (var item in estadoPos.items) {
      bytes += generator.row([
        PosColumn(text: item.cantidad.toString(), width: 2),
        // Truncamos la descripción si es muy larga
        // Truncamos el nombre si es muy larga
        PosColumn(text: item.product.nombre.length > 15 ? item.product.nombre.substring(0, 15) : item.product.nombre, width: 6),
        PosColumn(text: (item.subtotal / item.cantidad).toStringAsFixed(2), width: 2),
        PosColumn(text: item.subtotal.toStringAsFixed(2), width: 2),
      ]);
      bytes += generator.text('   ${item.product.nombre} ${item.precioManual != null ? "*" : ""}', styles: const PosStyles(align: PosAlign.left));
    }

    bytes += generator.text('--------------------------------', styles: const PosStyles(align: PosAlign.center));

    // --- RESUMEN DE PAGO ---
    bytes += generator.row([
      PosColumn(text: 'SUBTOTAL', width: 8, styles: const PosStyles(bold: true)),
      PosColumn(text: 'S/. ${estadoPos.totalCobrar.toStringAsFixed(2)}', width: 4, styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]);

    if (ahorroMayorista > 0) {
      bytes += generator.row([
        PosColumn(text: 'AHORRO MAYORISTA', width: 8, styles: const PosStyles(bold: true)),
        PosColumn(text: '-S/. ${ahorroMayorista.toStringAsFixed(2)}', width: 4, styles: const PosStyles(align: PosAlign.right, bold: true)),
      ]);
    }

    bytes += generator.feed(1);
    bytes += generator.row([
      PosColumn(text: 'TOTAL A PAGAR', width: 6, styles: const PosStyles(bold: true, height: PosTextSize.size2, width: PosTextSize.size2)),
      PosColumn(text: 'S/. ${(estadoPos.totalCobrar - ahorroMayorista).toStringAsFixed(2)}', width: 6, styles: const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2, width: PosTextSize.size2)),
    ]);

    // --- PIE Y QR (TICKET DE CORTESÍA) ---
    bytes += generator.feed(2);
    bytes += generator.text(config.mensajeDespedida, styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text('Pedidos por WhatsApp 👇', styles: const PosStyles(align: PosAlign.center));
    
    // Si la impresora soporta QR Code bitImage, se puede mandar. Para ESC/POS:
    String wameUrl = 'https://wa.me/${config.telefono.replaceAll(RegExp(r"[^\d]"), "")}';
    bytes += generator.qrcode(wameUrl);
    
    bytes += generator.feed(5); // Avance de 5 recortes para liberar el papel
    bytes += generator.cut();

    final result = await PrintBluetoothThermal.writeBytes(bytes);
    return result;
  }
}
