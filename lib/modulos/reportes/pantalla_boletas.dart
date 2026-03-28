import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';

import '../../datos/modelos/venta.dart';
import '../../modulos/caja/proveedor_caja.dart';
import '../../servicios/servicio_configuracion.dart';
import '../../servicios/servicio_db_local.dart';
import '../../servicios/servicio_pdf.dart';
import '../../servicios/servicio_impresion.dart';
import '../../servicios/servicio_backend.dart';
import '../../utilidades/fiscal.dart';

class PantallaBoletas extends StatefulWidget {
  const PantallaBoletas({super.key});

  @override
  State<PantallaBoletas> createState() => _PantallaBoletasState();
}

class _PantallaBoletasState extends State<PantallaBoletas> {
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _ventas = [];
  bool _loading = true;
  _BoletaFilter _filter = _BoletaFilter.todas;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({String? query}) async {
    setState(() => _loading = true);
    final rows = await ServicioDbLocal.buscarVentasPorCorrelativo(
      query ?? _search.text,
      limit: 120,
    );
    if (!mounted) return;
    setState(() {
      _ventas = rows;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _ventasFiltradas() {
    return _ventas.where((v) {
      final anulada = (v['anulado'] ?? 0) == 1;
      final synced = (v['sincronizado'] ?? 0) == 1;
      switch (_filter) {
        case _BoletaFilter.vigentes:
          return !anulada;
        case _BoletaFilter.anuladas:
          return anulada;
        case _BoletaFilter.pendientesSync:
          return !synced;
        case _BoletaFilter.todas:
          return true;
      }
    }).toList();
  }

  Future<Venta> _mapVenta(Map<String, dynamic> row) async {
    final ventaId = row['id'] as int?;
    List<ItemCarrito> items = [];

    // Prioridad 1: Obtener de la tabla normalizada venta_items (Máxima Integridad)
    if (ventaId != null) {
      try {
        final itemRows = await ServicioDbLocal.obtenerItemsDeVenta(ventaId);
        if (itemRows.isNotEmpty) {
          items = itemRows.map((r) => ItemCarrito.fromLocalMap(r)).toList();
        }
      } catch (e) {
        debugPrint('Error cargando items desde tabla venta_items: $e');
      }
    }

    // Prioridad 2: Fallback al JSON (Compatibilidad o Recuperación)
    if (items.isEmpty) {
      final rawItems = (row['items_json'] ?? '[]').toString();
      final decoded = jsonDecode(rawItems);
      if (decoded is List) {
        for (final raw in decoded) {
          if (raw is Map<String, dynamic>) {
            try {
              items.add(ItemCarrito.fromJson(raw));
            } catch (_) {}
          } else if (raw is Map) {
            try {
              items.add(ItemCarrito.fromJson(Map<String, dynamic>.from(raw)));
            } catch (_) {}
          }
        }
      }
    }

    final total = ((row['total'] ?? 0) as num).toDouble();
    final ivaRate = await ServicioConfiguracion.obtenerIGVActual();
    final desglose = UtilFiscal.calcularDesglose(total, tasa: ivaRate);
    final subtotal = row['subtotal'] != null
        ? double.tryParse(row['subtotal'].toString()) ?? desglose.$1
        : desglose.$1;
    final igv = row['igv'] != null
        ? double.tryParse(row['igv'].toString()) ?? desglose.$2
        : desglose.$2;

    final correlativo = row['correlativo']?.toString();
    final tipo = (correlativo?.contains('F') ?? false)
        ? TipoComprobante.factura
        : TipoComprobante.boleta;

    return Venta(
      id: correlativo?.isNotEmpty == true ? correlativo! : row['id'].toString(),
      correlativo: correlativo,
      fecha: DateTime.tryParse((row['creado_at'] ?? '').toString()) ??
          DateTime.now(),
      tipoComprobante: tipo,
      documentoCliente: (row['documento_cliente'] ?? '').toString().isNotEmpty
          ? row['documento_cliente'].toString()
          : '00000000',
      nombreCliente: row['nombre_cliente']?.toString(),
      operacionGravada: subtotal,
      igv: igv,
      total: total,
      metodoPago: MetodoPago.values.firstWhere(
        (e) =>
            e.name.toUpperCase() ==
            (row['metodo_pago']?.toString().toUpperCase() ?? 'EFECTIVO'),
        orElse: () => MetodoPago.efectivo,
      ),
      montoRecibido: total,
      vuelto: 0,
      items: items,
      dbId: row['id'] as int?,
      despachado: (row['despachado'] ?? 0) == 1,
      synced: (row['sincronizado'] ?? 0) == 1,
    );
  }

  Future<void> _reimprimir(Map<String, dynamic> row) async {
    if ((row['anulado'] ?? 0) == 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'La boleta está anulada. No se puede reimprimir como válida.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final venta = await _mapVenta(row);
    final ok = await ServicioImpresion().imprimirComprobante(venta);
    if (!mounted) return;
    unawaited(ServicioDbLocal.logAudit(
        accion: 'REIMPRESION',
        usuario: await ServicioImpresion.obtenerAliasVendedor(),
        detalle: 'Venta ${venta.id} ok=$ok'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Reimpresión enviada'
            : 'No se pudo imprimir ahora, quedó en cola'),
        backgroundColor: ok ? Colors.green : Colors.orange,
      ),
    );
  }

  Future<void> _exportarPdf(
    Map<String, dynamic> row, {
    required PdfPageFormat pageFormat,
    required String etiqueta,
  }) async {
    final venta = await _mapVenta(row);
    final vendedor = await ServicioImpresion.obtenerAliasVendedor();
    final File pdf = await ServicioPdf.generateVentaPdf(
      items: venta.items,
      total: venta.total,
      vendedor: vendedor,
      correlativo:
          venta.correlativo?.isNotEmpty == true ? venta.correlativo! : venta.id,
      cliente: venta.nombreCliente,
      dniRuc: venta.documentoCliente,
      tipo: venta.tipoComprobante == TipoComprobante.factura
          ? 'FACTURA ELECTRÓNICA'
          : 'BOLETA ELECTRÓNICA',
      metodoPago: venta.metodoPago.name,
      montoRecibido: venta.montoRecibido,
      vuelto: venta.vuelto,
      subtotalSinIgv: venta.operacionGravada,
      igvValue: venta.igv,
      pageFormat: pageFormat,
    );
    await ServicioPdf.shareVentaPdf(pdf);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PDF generado en formato $etiqueta')),
    );
  }

  Future<void> _previewTicket(Map<String, dynamic> row) async {
    final venta = await _mapVenta(row);
    final text = ServicioImpresion.renderTicketPreview(
      items: venta.items,
      total: venta.total,
      serie: venta.correlativo?.split('-').first ?? 'B001',
      correlativo: venta.correlativo,
      cliente: venta.nombreCliente,
      dniRuc: venta.documentoCliente,
      tipo: venta.tipoComprobante == TipoComprobante.factura
          ? 'FACTURA ELECTRÓNICA'
          : 'BOLETA ELECTRÓNICA',
      vendedor: await ServicioImpresion.obtenerAliasVendedor(),
      metodoPago: venta.metodoPago.name,
      montoRecibido: venta.montoRecibido,
      vuelto: venta.vuelto,
      subtotalSinIgv: venta.operacionGravada,
      igvValue: venta.igv,
      fechaVenta: venta.fecha,
    );
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F0F1A),
        title:
            const Text('Preview Ticket', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Text(
            text,
            style:
                const TextStyle(fontFamily: 'monospace', color: Colors.white70),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar',
                style: TextStyle(color: Colors.tealAccent)),
          )
        ],
      ),
    );
  }

  Future<void> _abrirOpcionesPdf(Map<String, dynamic> row) async {
    if ((row['anulado'] ?? 0) == 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La boleta está anulada.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final opcion = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF A4 (impresora normal)'),
              onTap: () => Navigator.pop(ctx, 'a4'),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('PDF ticket 58mm'),
              onTap: () => Navigator.pop(ctx, '58'),
            ),
          ],
        ),
      ),
    );

    if (opcion == 'a4') {
      await _exportarPdf(
        row,
        pageFormat: PdfPageFormat.a4,
        etiqueta: 'A4',
      );
    } else if (opcion == '58') {
      await _exportarPdf(
        row,
        pageFormat: const PdfPageFormat(
          58 * PdfPageFormat.mm,
          220 * PdfPageFormat.mm,
          marginAll: 5 * PdfPageFormat.mm,
        ),
        etiqueta: '58mm',
      );
    }
  }

  Future<void> _anularBoleta(Map<String, dynamic> row) async {
    final ventaId = row['id'] as int?;
    if (ventaId == null) return;
    if ((row['anulado'] ?? 0) == 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta boleta ya está anulada')),
      );
      return;
    }

    final motivoCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular boleta'),
        content: TextField(
          controller: motivoCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Motivo de anulación',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final motivo = motivoCtrl.text.trim();
    if (motivo.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes ingresar un motivo de anulación')),
      );
      return;
    }

    final alias = await ServicioBackend.obtenerAliasVendedorActual();
    final localOk = await ServicioDbLocal.anularVentaLocal(
      ventaId: ventaId,
      motivo: motivo,
      aliasUsuario: alias,
    );
    if (!localOk) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo anular localmente'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final correlativo = row['correlativo']?.toString();
    bool cloudOk = false;
    if (correlativo != null && correlativo.isNotEmpty) {
      cloudOk = await ServicioBackend.anularVentaEnNube(
        correlativo: correlativo,
        motivo: motivo,
        aliasUsuario: alias,
      );
    }

    await ServicioDbLocal.logAudit(
      accion: 'ANULAR_BOLETA',
      usuario: alias,
      detalle: 'ID=$ventaId correlativo=$correlativo motivo=$motivo',
    );

    if (!mounted) return;
    await _cargar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cloudOk
              ? 'Boleta anulada y sincronizada (SUNAT pendiente)'
              : 'Boleta anulada localmente (pendiente de sincronizar/SUNAT)',
        ),
        backgroundColor: cloudOk ? Colors.green : Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _ventasFiltradas();
    final anuladasCount = _ventas.where((v) => (v['anulado'] ?? 0) == 1).length;
    final pendientesSync =
        _ventas.where((v) => (v['sincronizado'] ?? 0) != 1).length;
    final totalVisible = visibles.fold<double>(
      0,
      (s, v) => s + ((v['total'] ?? 0) as num).toDouble(),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Boletas')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E1422), Color(0xFF101827), Color(0xFF0F0F1A)],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) => _cargar(),
                    decoration: InputDecoration(
                      labelText: 'Buscar por N° boleta/correlativo',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          _cargar(query: '');
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _Metrica(
                          label: 'Visibles',
                          value: '${visibles.length}',
                          color: Colors.tealAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Metrica(
                          label: 'Anuladas',
                          value: '$anuladasCount',
                          color: Colors.orangeAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Metrica(
                          label: 'Pend. Sync',
                          value: '$pendientesSync',
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _FilaFiltro(
                    filter: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visibles.isEmpty
                      ? const Center(child: Text('No hay boletas para mostrar'))
                      : RefreshIndicator(
                          onRefresh: _cargar,
                          child: ListView.builder(
                            itemCount: visibles.length,
                            itemBuilder: (_, i) {
                              final v = visibles[i];
                              final total =
                                  ((v['total'] ?? 0) as num).toDouble();
                              final anulada = (v['anulado'] ?? 0) == 1;
                              final estadoSync = (v['sincronizado'] ?? 0) == 1;
                              final creadoAt = DateTime.tryParse(
                                  (v['creado_at'] ?? '').toString());
                              final fecha = creadoAt == null
                                  ? '-'
                                  : '${creadoAt.day.toString().padLeft(2, '0')}/${creadoAt.month.toString().padLeft(2, '0')}/${creadoAt.year}';
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                color: const Color(0xFF121B2B),
                                child: ListTile(
                                  title: Text(v['correlativo']?.toString() ??
                                      'Ticket #${v['id']}'),
                                  subtitle: Text(
                                    'Total: S/. ${total.toStringAsFixed(2)} • $fecha\n'
                                    'Estado: ${anulada ? 'ANULADO' : 'VIGENTE'} • Sync: ${estadoSync ? 'OK' : 'PENDIENTE'}',
                                  ),
                                  trailing: Wrap(
                                    spacing: 8,
                                    children: [
                                      IconButton(
                                        tooltip: 'Preview',
                                        icon: const Icon(
                                            Icons.visibility_outlined),
                                        onPressed: () => _previewTicket(v),
                                      ),
                                      IconButton(
                                        tooltip: 'Reimprimir',
                                        icon: const Icon(Icons.print_outlined),
                                        onPressed: anulada
                                            ? null
                                            : () => _reimprimir(v),
                                      ),
                                      IconButton(
                                        tooltip: 'PDF',
                                        icon: const Icon(
                                            Icons.picture_as_pdf_outlined),
                                        onPressed: anulada
                                            ? null
                                            : () => _abrirOpcionesPdf(v),
                                      ),
                                      IconButton(
                                        tooltip: 'Anular',
                                        icon: const Icon(Icons.block_outlined),
                                        onPressed: anulada
                                            ? null
                                            : () => _anularBoleta(v),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
            if (!_loading)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Total visible: S/.${totalVisible.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _BoletaFilter { todas, vigentes, anuladas, pendientesSync }

class _Metrica extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Metrica(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 1),
          Text(value,
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _FilaFiltro extends StatelessWidget {
  final _BoletaFilter filter;
  final ValueChanged<_BoletaFilter> onChanged;
  const _FilaFiltro({required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip(_BoletaFilter.todas, 'Todas'),
        const SizedBox(width: 8),
        _chip(_BoletaFilter.vigentes, 'Vigentes'),
        const SizedBox(width: 8),
        _chip(_BoletaFilter.anuladas, 'Anuladas'),
        const SizedBox(width: 8),
        _chip(_BoletaFilter.pendientesSync, 'Pend. Sync'),
      ],
    );
  }

  Widget _chip(_BoletaFilter f, String label) {
    final active = filter == f;
    return Expanded(
      child: InkWell(
        onTap: () => onChanged(f),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: active ? Colors.teal : Colors.white10,
            border:
                Border.all(color: active ? Colors.tealAccent : Colors.white24),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.black : Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}
