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

class ServicioImpresion {
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
  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  bool _estaConectado = false;
  bool get estaConectado => _estaConectado;
  Future<void>? _ongoingReconnect;

  // ── TIMERS ───────────────────────────────────────────────────────────────
  int _failedReconnectCount = 0;
  Timer? _reconnectTimer;
  Timer? _watchdogTimer;

  // ── INIT ─────────────────────────────────────────────────────────────────
  void _initAutoConnect() {
    if (!_isPrintSupported()) return;
    intentarReconectar();
    _startWatchdog();
  }

  void _startWatchdog() {
    if (!_isPrintSupported()) return;
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      final stillConnected = await PrintBluetoothThermal.connectionStatus;
      if (!stillConnected && _estaConectado) {
        _estaConectado = false;
        _connectionController.add(false);
        RegistroApp.warn('Watchdog: BT desconectado. Reconectando...', tag: 'BT');
        await intentarReconectar();
      }
    });
  }

  // ── RECONEXIÓN ───────────────────────────────────────────────────────────
  Future<bool> _ensureBluetoothPermissions() async {
    if (!Platform.isAndroid) return true;

    final scanStatus = await Permission.bluetoothScan.status;
    final connectStatus = await Permission.bluetoothConnect.status;

    if (scanStatus.isGranted && connectStatus.isGranted) return true;

    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    final granted = statuses[Permission.bluetoothScan]?.isGranted == true &&
        statuses[Permission.bluetoothConnect]?.isGranted == true;

    if (!granted) {
      RegistroApp.warn('Permisos Bluetooth denegados', tag: 'BT');
      try {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('⚠️ Permisos Bluetooth necesarios para imprimir.'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 6),
          ),
        );
      } catch (e, st) {
        RegistroApp.warn('No se pudo mostrar aviso de permisos BT',
            tag: 'BT', error: e, stackTrace: st);
      }
    }
    return granted;
  }

  Future<void> intentarReconectar() async {
    if (!_isPrintSupported()) return;
    if (_ongoingReconnect != null) {
      await _ongoingReconnect;
      return;
    }
    _ongoingReconnect = _doReconnect();
    try {
      await _ongoingReconnect;
    } finally {
      _ongoingReconnect = null;
    }
  }

  Future<void> _doReconnect() async {
    if (!_isPrintSupported()) return;
    final hasPermissions = await _ensureBluetoothPermissions();
    if (!hasPermissions) {
      _actualizarConectado(false);
      return;
    }

    final connected = await PrintBluetoothThermal.connectionStatus;
    if (connected) {
      _actualizarConectado(true);
      return;
    }
    await _intentarConBackoff();
  }

  /// Convierte un logo a monocromo (dithering Floyd-Steinberg) para ticket térmico.
  /// Devuelve bytes PNG listos para esc_pos.
  Future<List<int>?> logoMonocromo(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      final src = img.decodeImage(bytes);
      if (src == null) return null;

      // Escala a 384px (impresora 58mm) para evitar buffer overflow
      final resized = img.copyResize(src,
          width: 384, interpolation: img.Interpolation.linear);
      final gray = img.grayscale(resized);
      final dithered = _applyDitherOrThreshold(gray);
      return img.encodePng(dithered, level: 6);
    } catch (e) {
      RegistroApp.warn('Logo monocromo falló: $e', tag: 'BT');
      return null;
    }
  }

  /// Usa dithering de la librería `image` si está disponible; si no, aplica
  /// un simple umbral binario para garantizar compatibilidad hacia atrás.
  img.Image _applyDitherOrThreshold(img.Image gray) {
    try {
      return img.ditherImage(gray, kernel: img.DitherKernel.floydSteinberg);
    } catch (e, st) {
      RegistroApp.warn('Dither no disponible, aplicando umbral',
          tag: 'BT', error: e, stackTrace: st);
      // Fallback robusto: threshold manual a 128
      final clone = img.Image.from(gray);
      for (int y = 0; y < clone.height; y++) {
        for (int x = 0; x < clone.width; x++) {
          final pixel = clone.getPixel(x, y);
          final luma = img.getLuminance(pixel);
          final value = luma < 128 ? 0 : 255;
          clone.setPixelRgba(x, y, value, value, value, 255);
        }
      }
      return clone;
    }
  }

  Future<bool> _intentarConBackoff({
    int maxIntentos = 3,
    int delayInicialMs = 500,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final savedMac = prefs.getString('printer_mac') ??
        prefs.getString('printerMac') ??
        prefs.getString('bluetooth_mac');
    final macToConnect = (savedMac != null && savedMac.isNotEmpty)
        ? savedMac
        : whitelistedMacFallback;

    final paired = await PrintBluetoothThermal.pairedBluetooths;
    final printer = paired.firstWhere(
      (d) => d.macAdress == macToConnect,
      orElse: () {
        final guessed = paired.where((d) {
          final name = d.name.toLowerCase();
          return name.contains('pt-') ||
              name.contains('pt210') ||
              name.contains('thermal') ||
              name.contains('printer');
        }).toList();
        if (guessed.isNotEmpty) return guessed.first;
        return BluetoothInfo(name: 'NONE', macAdress: '');
      },
    );

    if (printer.macAdress.isEmpty) {
      _actualizarConectado(false);
      if (savedMac != null) _notificarNecesidadEmparejamiento();
      return false;
    }

    for (int i = 0; i < maxIntentos; i++) {
      try {
        final res = await PrintBluetoothThermal.connect(
          macPrinterAddress: printer.macAdress,
        );

        if (res) {
          _actualizarConectado(true);
          RegistroApp.info('BT reconectado en intento ${i + 1}', tag: 'BT');
          _reconnectTimer?.cancel();
          _reconnectTimer = null;
          _failedReconnectCount = 0;
          ColaImpresion.procesarCola().catchError(
            (e) => RegistroApp.error('Error procesando cola BT',
                tag: 'BT', error: e),
          );
          return true;
        }
      } catch (e) {
        RegistroApp.warn('Intento BT $i falló: $e', tag: 'BT');
      }

      if (i < maxIntentos - 1) {
        await Future.delayed(Duration(milliseconds: delayInicialMs * (1 << i)));
      }
    }

    _actualizarConectado(false);
    _failedReconnectCount++;

    if (_failedReconnectCount > 3) {
      RegistroApp.error('Impresora sin respuesta. Reintento en 30 min',
          tag: 'BT');
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(minutes: 30), () {
        _failedReconnectCount = 0;
        intentarReconectar();
      });
    }

    return false;
  }

  void _actualizarConectado(bool valor) {
    _estaConectado = valor;
    _connectionController.add(valor);
  }

  Future<bool> _ensureConnected() async {
    bool conectado = await PrintBluetoothThermal.connectionStatus;
    if (!conectado) {
      await intentarReconectar();
      conectado = await PrintBluetoothThermal.connectionStatus;
    }
    return conectado;
  }

  void _notificarNecesidadEmparejamiento() {
    try {
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
              'Impresora no vinculada. Empareja Bluetooth desde ajustes del dispositivo.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 8),
        ),
      );
    } catch (e) {
      RegistroApp.error('Error mostrando snackbar', tag: 'UI', error: e);
    }
  }

  // ── DEBUG ─────────────────────────────────────────────────────────────────
  static bool debugForceError = false;

  // ── CONFIGURACIÓN DE NEGOCIO ──────────────────────────────────────────────
  Future<ConfiguracionNegocio> _getConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return ConfiguracionNegocio(
      nombre: prefs.getString('thermal_nombre') ??
          prefs.getString('biz_nombre') ??
          'Librería BiPenc',
      ruc: prefs.getString('thermal_ruc') ??
          prefs.getString('biz_ruc') ??
          '00000000000',
      direccion: prefs.getString('thermal_dir') ??
          prefs.getString('biz_dir') ??
          'Ciudad Principal',
      telefono:
          prefs.getString('thermal_tel') ?? prefs.getString('biz_tel') ?? '',
      mensajeDespedida: prefs.getString('thermal_msg') ??
          prefs.getString('biz_msg') ??
          '¡Gracias por su compra!',
      serie: prefs.getString('biz_serie') ?? 'B001',
    );
  }

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

  // ── API PÚBLICA ───────────────────────────────────────────────────────────
  Future<bool> imprimirTicketCortesia(
    ProveedorCaja estadoPos, {
    double ahorroMayorista = 0.0,
  }) {
    return imprimirVenta(
      items: estadoPos.items,
      total: estadoPos.totalCobrar,
      ahorroMayorista: ahorroMayorista,
    );
  }

  /// Imprime un comprobante formal con QR code
  Future<bool> imprimirComprobante(Venta venta,
      {String turnoEstado = 'Abierto'}) async {
    RegistroApp.info('Iniciando impresión de comprobante: ${venta.id}',
        tag: 'PRINT');
    final vendedor = await _getVendedorAlias();
    final correlativo = _formatCorrelativo(venta);
    return imprimirVenta(
      items: venta.items,
      total: venta.total,
      subtotalSinIgv: venta.operacionGravada,
      igvValue: venta.igv,
      tipo: venta.tipoComprobante == TipoComprobante.factura
          ? 'FACTURA ELECTRÓNICA'
          : 'BOLETA ELECTRÓNICA',
      correlativo: venta.correlativo?.isNotEmpty == true
          ? venta.correlativo
          : correlativo,
      cliente: venta.nombreCliente,
      dniRuc: venta.documentoCliente,
      vendedor: vendedor,
      turnoEstado: turnoEstado,
      ventaId: venta.id,
      metodoPago: venta.metodoPago.name,
      montoRecibido: venta.montoRecibido,
      vuelto: venta.vuelto,
      fechaVenta: venta.fecha,
      incluirQr: !_disableQrOnThermal,
      hashCpb: venta.hashCpb,
    );
  }

  /// Imprime una imagen (ej. foto de lista) en la térmica BT.
  Future<bool> imprimirImagenLista(String pathOrUrl) async {
    try {
      final conectado = await _ensureConnected();
      if (!conectado) return false;

      final prefs = await SharedPreferences.getInstance();
      final paperSize = (prefs.getString('thermal_paper_size') ?? '80').trim();
      final is80mm = paperSize == '80';
      final maxWidthPx = is80mm ? 576 : 384;

      // Descargar o leer archivo
      final bytes = await (pathOrUrl.startsWith('http')
          ? (() async {
              final resp = await http
                  .get(Uri.parse(pathOrUrl))
                  .timeout(const Duration(seconds: 8));
              if (resp.statusCode != 200) {
                throw Exception(
                    'HTTP ${resp.statusCode} al descargar imagen (${resp.reasonPhrase})');
              }
              return resp.bodyBytes;
            })()
          : File(pathOrUrl).readAsBytes());
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('Imagen inválida');

      final resized = img.copyResize(
        decoded,
        width: maxWidthPx,
        interpolation: img.Interpolation.average,
      );
      final gray = img.grayscale(resized);
      final mono = _applyDitherOrThreshold(gray);

      final profile = await CapabilityProfile.load();
      final generator =
          Generator(is80mm ? PaperSize.mm80 : PaperSize.mm58, profile);
      List<int> data = [];
      data += generator.imageRaster(mono, align: PosAlign.center);
      data += generator.feed(2);

      return await PrintBluetoothThermal.writeBytes(
        Uint8List.fromList(data),
      );
    } catch (e) {
      RegistroApp.error('Error imprimiendo imagen: $e', tag: 'PRINT', error: e);
      return false;
    }
  }

  String _formatCorrelativo(Venta venta) {
    final raw = (venta.correlativo?.trim().isNotEmpty == true)
        ? venta.correlativo!.trim()
        : venta.id.trim();
    if (raw.contains('-')) return raw;
    return raw.length >= 8
        ? raw.substring(raw.length - 8)
        : raw.padLeft(8, '0');
  }

  /// Genera el contenido del QR code para SUNAT
  String _generarQRContent({
    required String ruc,
    required String tipoDoc,
    required String serie,
    required String correlativo,
    required double total,
    required double igv,
    required DateTime fechaEmision,
    String? dniRuc,
    String? hashCpb,
  }) {
    final fechaStr = DateFormat('yyyy-MM-dd').format(fechaEmision);
    // Formato SUNAT: RUC|TipoDoc|Serie|Numero|IGV|Total|Fecha|Hash
    final parts = [
      ruc,
      tipoDoc,
      serie,
      correlativo,
      igv.toStringAsFixed(2),
      total.toStringAsFixed(2),
      fechaStr,
      (hashCpb ?? '').trim(),
    ];
    // Cliente: opcional (no es parte de los 8 mínimos)
    if (dniRuc != null && dniRuc.isNotEmpty) {
      parts.add(dniRuc);
    }
    return parts.join('|');
  }

  /// Método genérico para imprimir una venta con QR code mejorado
  Future<bool> imprimirVenta({
    required List<ItemCarrito> items,
    required double total,
    double ahorroMayorista = 0.0,
    String? correlativo,
    String? cliente,
    String? dniRuc,
    String tipo = 'TICKET',
    String? vendedor,
    String turnoEstado = 'Abierto',
    String? ventaId,
    String? metodoPago,
    double? montoRecibido,
    double? vuelto,
    double? subtotalSinIgv,
    double? igvValue,
    double? tasaIgv,
    DateTime? fechaVenta,
    bool incluirQr = true,
    String? hashCpb,
  }) async {
    RegistroApp.debug('Verificando conexión BT para imprimir', tag: 'PRINT');
    bool conectado = await PrintBluetoothThermal.connectionStatus;
    if (!conectado) {
      RegistroApp.info('Bluetooth no conectado, intentando reconectar...',
          tag: 'PRINT');
      await intentarReconectar();
      conectado = await PrintBluetoothThermal.connectionStatus;
    }

    if (!conectado) {
      RegistroApp.error('Fallo de conexión BT. Abortando impresión.',
          tag: 'PRINT');
    }

    final config = await _getConfig();
    final prefs = await SharedPreferences.getInstance();
    final paperSize = (prefs.getString('thermal_paper_size') ?? '80').trim();
    final is80mm = paperSize == '80';
    final lineWidth = is80mm ? _lineChars80 : _lineChars58;
    final profile = await CapabilityProfile.load();
    final generator =
        Generator(is80mm ? PaperSize.mm80 : PaperSize.mm58, profile);
    List<int> bytes = [];
    final safeCodePage = _sanitizeCodePage(
      prefs.getString('thermal_code_page') ?? _forcedCodePage,
    );

    // ── INICIALIZACIÓN ───────────────────────────────────────────────────
    bytes += generator.reset();
    bytes += generator.setGlobalCodeTable(safeCodePage);

    // ── ENCABEZADO ────────────────────────────────────────────────────────
    bytes += _printCentered(generator, _normalize(config.nombre.toUpperCase()),
        bold: true, width: lineWidth);
    bytes += _printCentered(generator, 'RUC: ${config.ruc}', bold: true);
    bytes += _printCentered(generator, config.direccion, width: lineWidth);
    if (config.telefono.isNotEmpty) {
      bytes += _printCentered(generator, 'TEL: ${config.telefono}',
          width: lineWidth);
    }
    bytes += generator.hr(ch: '-');

    // ── INFO TICKET ────────────────────────────────────────────────────────
    final fecha = fechaVenta ?? DateTime.now();
    final fechaStr = formatFechaTicket(fecha);

    bytes += _printCentered(generator, fechaStr, width: lineWidth);
    bytes += generator.feed(1);
    final modoPrueba = await ServicioConfiguracion.getModoPrueba();
    final titulo = modoPrueba
        ? 'DOCUMENTO NO VÁLIDO / PRUEBA'
        : _normalize(tipo.toUpperCase());
    bytes += _printCentered(generator, titulo, bold: true, width: lineWidth);

    final correlativoFinal = (correlativo != null && correlativo.contains('-'))
        ? correlativo
        : '${config.serie}-${correlativo ?? "00000"}';
    bytes += _printCentered(generator, correlativoFinal,
        bold: true, width: lineWidth);
    bytes += generator.feed(1);

    // ── CLIENTE Y METODO PAGO ─────────────────────────────────────────────
    bytes += generator.text(
        _normalize('Cliente: ${(cliente ?? "PUBLICO GENERAL").toUpperCase()}'));
    if (dniRuc != null && dniRuc.isNotEmpty && dniRuc != '00000000') {
      bytes +=
          generator.text(_normalize('${_labelDocumento(dniRuc)}: $dniRuc'));
    }
    if (vendedor != null && vendedor.isNotEmpty) {
      bytes += generator.text(_normalize('Atendido: $vendedor'));
    }
    if (metodoPago != null && metodoPago.isNotEmpty) {
      bytes +=
          generator.text(_normalize('Pago: ${_labelMetodoPago(metodoPago)}'));
    }
    bytes += generator.hr(ch: '-');

    // ── PRODUCTOS ─────────────────────────────────────────────────────────
    final qtyCol = is80mm ? 6 : 4;
    final amountCol = is80mm ? 14 : 12;
    final productCol = (lineWidth - qtyCol - amountCol - 2).clamp(10, 40);
    final headerLine =
        '${'CANT'.padRight(qtyCol)} ${'PRODUCTO'.padRight(productCol)} ${'IMPORTE'.padLeft(amountCol)}';
    bytes += generator.text(
      _normalize(headerLine),
      styles: const PosStyles(bold: true),
    );
    bytes += generator.hr(ch: '-');

    // Column configuration
    for (final item in items) {
      final lines = _buildItemLines(
        item: item,
        qtyCol: qtyCol,
        productCol: productCol,
        amountCol: amountCol,
        lineWidth: lineWidth,
      );
      for (final line in lines) {
        bytes += generator.text(_normalize(line));
      }
      bytes += generator.feed(0);
    }
    bytes += generator.hr(ch: '-');
    // REMOVED: bytes += _printCentered(generator, 'Items: $totalItems', width: lineWidth);

    // ── TOTALES ───────────────────────────────────────────────────────────
    final ivaRate = tasaIgv ?? await ServicioConfiguracion.obtenerIGVActual();
    final desglose = UtilFiscal.calcularDesglose(total, tasa: ivaRate);
    final subtotalCalc = subtotalSinIgv ?? desglose.$1;
    final igvCalc = igvValue ?? desglose.$2;
    final igvPercentLabel = (ivaRate * 100).toStringAsFixed(0);

    bytes += generator.text(
        _normalize(_lineTotal('Subtotal', subtotalCalc, width: lineWidth)));

    if (ahorroMayorista > 0) {
      bytes += generator.text(_normalize(
          _lineTotal('Descuento', -ahorroMayorista, width: lineWidth)));
    }

    if (metodoPago != null &&
        metodoPago.toLowerCase() == 'efectivo' &&
        montoRecibido != null &&
        montoRecibido > 0) {
      bytes += generator.text(
          _normalize(_lineTotal('Recibido', montoRecibido, width: lineWidth)));
      final vueltoCalc =
          (vuelto ?? (montoRecibido - total)).clamp(0, double.infinity);
      bytes += generator.text(
        _normalize(_lineTotal('Vuelto', vueltoCalc, width: lineWidth)),
        styles: const PosStyles(bold: true),
      );
    }

    bytes += generator.text(_normalize(
        _lineTotal('IGV ($igvPercentLabel%)', igvCalc, width: lineWidth)));
    bytes += generator.feed(1);
    bytes += generator.text(
      _normalize(_lineTotal('TOTAL', total, width: lineWidth)),
      styles: const PosStyles(bold: true, height: PosTextSize.size2),
    );

    bytes += generator.feed(1);

    // ── QR CODE (si hay datos de comprobante) ─────────────────────────────
    if (incluirQr && correlativo != null && correlativo.contains('-')) {
      try {
        final qrContent = _generarQRContent(
          ruc: config.ruc,
          tipoDoc: tipo.toUpperCase().contains('FACTURA') ? '01' : '03',
          serie: correlativo.split('-').first,
          correlativo: correlativo.split('-').last,
          total: total,
          igv: igvCalc,
          fechaEmision: fecha,
          dniRuc: dniRuc,
          hashCpb: hashCpb,
        );

        bytes += generator.feed(1);
        bytes += _printCentered(generator, 'Escanea el QR', width: lineWidth);
        bytes += generator.qrcode(
          qrContent,
          align: PosAlign.center,
          size: is80mm ? QRSize.Size6 : QRSize.Size5,
          cor: QRCorrection.M,
        );
        bytes += generator.feed(1);
      } catch (e) {
        RegistroApp.warn('Error generando QR: $e', tag: 'PRINT');
      }
    }

    // ── PIE DE TICKET ─────────────────────────────────────────────────────
    bytes += generator.hr(ch: '-');
    bytes += _printCentered(generator, 'REPRESENTACION IMPRESA DE LA',
        width: lineWidth);
    bytes += _printCentered(generator, tipo, bold: true, width: lineWidth);

    // Updated marketing message
    const msgDespedida =
        "Gracias por su compra en BiPenc (Librería Exclusividades Jean Claudio) - Su boleta llegará al correo.";
    bytes +=
        _printCentered(generator, msgDespedida, bold: true, width: lineWidth);

    // Policy line
    bytes += _printCentered(
        generator, "No se aceptan devoluciones de material escolar.",
        width: lineWidth);

    // ── CORTE ─────────────────────────────────────────────────────────────
    bytes += generator.feed(3);
    bytes += generator.cut();

    // ── ENVÍO A IMPRESORA ────────────────────────────────────────────────
    if (!conectado || debugForceError) {
      await ColaImpresion.encolarImpresion(
        bytes: bytes,
        tipoComprobante: tipo,
        ventaId: ventaId ?? correlativo ?? '',
      );
      return false;
    }

    var result = await PrintBluetoothThermal.writeBytes(bytes)
        .timeout(const Duration(seconds: 8), onTimeout: () => false);
    RegistroApp.info('writeBytes ticket result=$result incluirQr=$incluirQr',
        tag: 'PRINT');
    if (!result) {
      await intentarReconectar();
      final reconnectOk = await PrintBluetoothThermal.connectionStatus;
      if (reconnectOk) {
        result = await PrintBluetoothThermal.writeBytes(bytes);
        RegistroApp.info('writeBytes ticket retry result=$result', tag: 'PRINT');
      }
    }
    if (!result) {
      await ColaImpresion.encolarImpresion(
        bytes: bytes,
        tipoComprobante: tipo,
        ventaId: ventaId ?? correlativo ?? '',
      );
    }
    return result;
  }

  /// Imprime ticket de cierre de caja
  Future<bool> imprimirTicketCierre(String ticketText) async {
    bool conectado = await PrintBluetoothThermal.connectionStatus;
    if (!conectado) {
      await intentarReconectar();
      conectado = await PrintBluetoothThermal.connectionStatus;
    }

    final prefs = await SharedPreferences.getInstance();
    final paperSize = (prefs.getString('thermal_paper_size') ?? '80').trim();
    final is80mm = paperSize == '80';
    final profile = await CapabilityProfile.load();
    final generator =
        Generator(is80mm ? PaperSize.mm80 : PaperSize.mm58, profile);
    List<int> bytes = [];

    bytes += generator.reset();
    bytes += generator.setGlobalCodeTable(
      _sanitizeCodePage(
          prefs.getString('thermal_code_page') ?? _forcedCodePage),
    );
    bytes += generator.text(ticketText,
        styles: const PosStyles(align: PosAlign.left));
    bytes += generator.feed(3);
    bytes += generator.cut();

    if (!conectado || debugForceError) {
      await ColaImpresion.encolarImpresion(
          bytes: bytes, tipoComprobante: 'CIERRE', ventaId: '');
      return false;
    }

    final result = await PrintBluetoothThermal.writeBytes(bytes)
        .timeout(const Duration(seconds: 8), onTimeout: () => false);
    if (!result) {
      await ColaImpresion.encolarImpresion(
          bytes: bytes, tipoComprobante: 'CIERRE', ventaId: '');
    }
    return result;
  }

  /// Imprime un ticket corto para calibrar ancho, centrado y caracteres.
  Future<bool> imprimirPruebaCalibracion() async {
    bool conectado = await PrintBluetoothThermal.connectionStatus;
    if (!conectado) {
      await intentarReconectar();
      conectado = await PrintBluetoothThermal.connectionStatus;
    }

    final config = await _getConfig();
    final prefs = await SharedPreferences.getInstance();
    final paperSize = (prefs.getString('thermal_paper_size') ?? '80').trim();
    final is80mm = paperSize == '80';
    final lineWidth = is80mm ? _lineChars80 : _lineChars58;
    final codePage = _sanitizeCodePage(
      prefs.getString('thermal_code_page') ?? _forcedCodePage,
    );

    final profile = await CapabilityProfile.load();
    final generator =
        Generator(is80mm ? PaperSize.mm80 : PaperSize.mm58, profile);
    List<int> bytes = [];

    bytes += generator.reset();
    bytes += generator.setGlobalCodeTable(codePage);
    bytes += _printCentered(
      generator,
      _normalize(config.nombre.toUpperCase()),
      bold: true,
      width: lineWidth,
    );
    bytes += _printCentered(
      generator,
      'PRUEBA DE IMPRESION',
      bold: true,
      width: lineWidth,
    );
    bytes += _printCentered(
      generator,
      '${is80mm ? "80" : "58"}mm  |  $codePage',
      width: lineWidth,
    );
    bytes += generator.hr(ch: '-');
    bytes += generator
        .text(_normalize(_lineJoin('|IZQUIERDA', 'DERECHA|', lineWidth)));
    bytes += _printCentered(generator, 'CENTRADO OK', width: lineWidth);
    bytes +=
        generator.text(_normalize('1234567890123456789012345678901234567890'));
    bytes += generator.text(_normalize(formatFechaTicket(DateTime.now())));
    bytes += generator.hr(ch: '-');
    bytes += _printCentered(generator, 'FIN DE PRUEBA', width: lineWidth);
    bytes += generator.feed(3);
    bytes += generator.cut();

    if (!conectado || debugForceError) {
      await ColaImpresion.encolarImpresion(
        bytes: bytes,
        tipoComprobante: 'TEST',
        ventaId: '',
      );
      return false;
    }

    var result = await PrintBluetoothThermal.writeBytes(bytes)
        .timeout(const Duration(seconds: 8), onTimeout: () => false);
    if (!result) {
      await intentarReconectar();
      final reconnectOk = await PrintBluetoothThermal.connectionStatus;
      if (reconnectOk) {
        result = await PrintBluetoothThermal.writeBytes(bytes);
      }
    }
    if (!result) {
      await ColaImpresion.encolarImpresion(
        bytes: bytes,
        tipoComprobante: 'TEST',
        ventaId: '',
      );
    }
    return result;
  }

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

  String _labelDocumento(String value) {
    return _labelDocumentoStatic(value);
  }

  String _labelMetodoPago(String metodo) {
    return _labelMetodoPagoStatic(metodo);
  }

  String _sanitizeCodePage(String cp) {
    final upper = cp.trim().toUpperCase();
    if (upper == 'CP1252' || upper == 'CP850' || upper == 'CP437') {
      return upper;
    }
    return 'CP1252';
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

  // ── LIFECYCLE ─────────────────────────────────────────────────────────────
  void dispose() {
    _watchdogTimer?.cancel();
    _reconnectTimer?.cancel();
    _connectionController.close();
    RegistroApp.info('ServicioImpresion disposed', tag: 'BT');
  }

  bool _isPrintSupported() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
