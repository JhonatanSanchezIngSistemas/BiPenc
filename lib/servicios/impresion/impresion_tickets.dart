part of '../servicio_impresion.dart';

mixin _ImpresionTickets on ServicioImpresion {
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

    const msgDespedida =
        'Gracias por su compra en BiPenc (Librería Exclusividades Jean Claudio) - Su boleta llegará al correo.';
    bytes +=
        _printCentered(generator, msgDespedida, bold: true, width: lineWidth);

    bytes += _printCentered(
        generator, 'No se aceptan devoluciones de material escolar.',
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
}
