import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bipenc/datos/modelos/venta.dart';
import 'package:bipenc/modulos/caja/proveedor_caja.dart';
import 'package:bipenc/servicios/servicio_pedidos.dart';
import 'package:bipenc/utilidades/registro_app.dart';
import 'selector_pago.dart';

class PanelCobro extends StatefulWidget {
  final ProveedorCaja pos;
  const PanelCobro({super.key, required this.pos});
  @override
  State<PanelCobro> createState() => _PanelCobroState();
}

class _PanelCobroState extends State<PanelCobro> {
  final _montoCtrl = TextEditingController();
  final _docCtrl = TextEditingController();
  String? _nombreCliente;
  bool _isProcessing = false;
  String? _dniApiStatus;
  bool get _buscandoCliente => widget.pos.isLoadingDocument;
  bool _vueltoConfirmado = false;
  bool _montoEditado = false;
  bool get _requiereConfirmacionVuelto =>
      widget.pos.metodoPago == MetodoPago.efectivo;

  String _sanitizeDocumento(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9]'), '');
  }

  @override
  void initState() {
    super.initState();
    _montoCtrl.text = ''; // obliga a ingresar monto manual
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncVueltoFlag());
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _docCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscarCliente(String doc, bool esRuc) async {
    _dniApiStatus = null;
    _nombreCliente = null;
    setState(() {});

    await widget.pos.buscarDocumentoCliente(doc);
    final cliente = widget.pos.clienteActivo;
    if (!mounted) return;
    if (cliente != null) {
      _nombreCliente = cliente.nombre;
      _dniApiStatus = 'OK';
    } else {
      _dniApiStatus = 'Error';
    }
    setState(() {});
  }

  Future<void> _cobrar() async {
    if (_isProcessing) return;

    final monto = double.tryParse(_montoCtrl.text.replaceAll(',', '.'));
    if (monto != null) widget.pos.setMontoRecibido(monto);

    if (!widget.pos.canCheckout) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.pos.totalCobrar > (monto ?? 0)
              ? 'Monto insuficiente — faltan S/.${(widget.pos.totalCobrar - (monto ?? 0)).toStringAsFixed(2)}'
              : 'El carrito está vacío'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final docLimpio = _sanitizeDocumento(_docCtrl.text);
      if (docLimpio.isNotEmpty &&
          docLimpio.length != 8 &&
          docLimpio.length != 11) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Documento inválido: usa 8 dígitos (DNI) o 11 (RUC)'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _isProcessing = false);
        return;
      }
      final venta = await widget.pos.procesarVenta(
        tipo: docLimpio.length == 11
            ? TipoComprobante.factura
            : TipoComprobante.boleta,
        docCliente: docLimpio.isNotEmpty ? docLimpio : null,
        nombreCliente: _nombreCliente,
      );

      if (venta == null) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      // Si la venta está vinculada a un pedido, marcarlo como completado
      final pedidoId = widget.pos.orderListId;
      if (pedidoId != null) {
        unawaited(ServicioPedidos()
            .completarConVenta(orderId: pedidoId, correlativoComprobante: venta.id));
      }

      if (mounted) {
        // Retornar la venta al modal para que el flujo siga en el context principal
        Navigator.pop(context, venta);
      }
    } catch (e) {
      RegistroApp.error('Error al procesar cobro: $e', tag: 'POS');
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al procesar: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.pos;
    // Para efectivo: pedimos (1) monto escrito y (2) confirmar entrega de vuelto.
    // La validación de monto suficiente sigue ocurriendo en pos.canCheckout dentro de _cobrar.
    final puedeCobrar = pos.metodoPago != MetodoPago.efectivo
        ? true
        : (_montoEditado && _vueltoConfirmado);

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),

            _section(
              title: 'Total a cobrar',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('S/.${pos.totalCobrar.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Incluye IGV ${pos.ivaRate * 100 ~/ 1}%',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            SelectorPago(
              pos: pos,
              montoCtrl: _montoCtrl,
              montoEditado: _montoEditado,
              vueltoConfirmado: _vueltoConfirmado,
              requiereConfirmacionVuelto: _requiereConfirmacionVuelto,
              onMontoChanged: () {
                _montoEditado = _montoCtrl.text.trim().isNotEmpty;
                _syncVueltoFlag();
                setState(() {});
              },
              onQuickAmount: (value) {
                _montoCtrl.text = value.toStringAsFixed(2);
                _montoCtrl.selection =
                    TextSelection.collapsed(offset: _montoCtrl.text.length);
                _montoEditado = true;
                _syncVueltoFlag();
                setState(() {});
              },
              onMetodoChange: (m) {
                pos.setMetodoPago(m);
                setState(() {
                  _vueltoConfirmado = m != MetodoPago.efectivo;
                  _montoEditado = m != MetodoPago.efectivo;
                });
              },
              onConfirmVuelto: () => setState(() => _vueltoConfirmado = true),
            ),

            // DNI/RUC (opcional)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _docCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 11,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'DNI / RUC (opcional)',
                      hintStyle:
                          const TextStyle(color: Colors.white24, fontSize: 12),
                      prefixIcon: const Icon(Icons.person_search,
                          color: Colors.white38, size: 18),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      counterText: '',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                    ),
                    onChanged: (v) {
                      final clean = _sanitizeDocumento(v);
                      if (clean.length == 8 || clean.length == 11) {
                        _docCtrl.text = clean;
                        _docCtrl.selection = TextSelection.collapsed(
                            offset: _docCtrl.text.length);
                        _buscarCliente(clean, clean.length == 11);
                      } else if (_nombreCliente != null ||
                          _dniApiStatus != null) {
                        setState(() {
                          _nombreCliente = null;
                          _dniApiStatus = null;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                _buscandoCliente
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                            color: Colors.teal, strokeWidth: 2))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_dniApiStatus != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                _dniApiStatus == 'OK'
                                    ? Icons.verified_user
                                    : _dniApiStatus == 'Error API'
                                        ? Icons.error_outline
                                        : Icons.cloud_off,
                                color: _dniApiStatus == 'OK'
                                    ? Colors.tealAccent
                                    : _dniApiStatus == 'Error API'
                                        ? Colors.redAccent
                                        : Colors.orange,
                                size: 18,
                              ),
                            ),
                          IconButton(
                            icon: const Icon(Icons.search, color: Colors.teal),
                            onPressed: () {
                              final doc = _sanitizeDocumento(_docCtrl.text);
                              if (doc.length == 8 || doc.length == 11) {
                                _buscarCliente(doc, doc.length == 11);
                              } else if (doc.isNotEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Ingresa un DNI (8) o RUC (11) válido'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
              ],
            ),
            if (_nombreCliente != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Resultado',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            letterSpacing: 0.2)),
                    const SizedBox(height: 4),
                    Text('Nombre: $_nombreCliente',
                        style: const TextStyle(
                            color: Colors.tealAccent,
                            fontWeight: FontWeight.w700)),
                    if (_docCtrl.text.isNotEmpty)
                      Text('Doc: ${_sanitizeDocumento(_docCtrl.text)}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: puedeCobrar ? _cobrar : null,
              icon: const Icon(Icons.check_circle),
              label: const Text('CONFIRMAR COBRO',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (!puedeCobrar && pos.metodoPago == MetodoPago.efectivo)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _montoEditado
                      ? 'Confirma que ya entregaste el vuelto para habilitar el cobro.'
                      : 'Ingresa el monto recibido para continuar.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  void _syncVueltoFlag() {
    final monto = double.tryParse(_montoCtrl.text.replaceAll(',', '.')) ?? 0;
    widget.pos.setMontoRecibido(monto);
    if (!_requiereConfirmacionVuelto) {
      _vueltoConfirmado = true;
    } else {
      _vueltoConfirmado = false;
    }
  }

  // helper compartido para secciones del panel.
  Widget _section({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
