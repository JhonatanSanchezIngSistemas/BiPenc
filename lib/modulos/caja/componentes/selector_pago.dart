import 'package:flutter/material.dart';
import 'package:bipenc/modulos/caja/proveedor_caja.dart';

/// REFACTOR: Selector de método de pago y captura de montos.
class SelectorPago extends StatelessWidget {
  final ProveedorCaja pos;
  final TextEditingController montoCtrl;
  final bool montoEditado;
  final bool vueltoConfirmado;
  final bool requiereConfirmacionVuelto;
  final VoidCallback onMontoChanged;
  final void Function(double value) onQuickAmount;
  final void Function(MetodoPago metodo) onMetodoChange;
  final VoidCallback onConfirmVuelto;

  const SelectorPago({
    super.key,
    required this.pos,
    required this.montoCtrl,
    required this.montoEditado,
    required this.vueltoConfirmado,
    required this.requiereConfirmacionVuelto,
    required this.onMontoChanged,
    required this.onQuickAmount,
    required this.onMetodoChange,
    required this.onConfirmVuelto,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(
          title: 'Método de pago',
          child: Row(
            children: MetodoPago.values.map((m) {
              final labels = {
                MetodoPago.efectivo: '💵 Efectivo',
                MetodoPago.yapePlin: '📱 Yape/Plin',
                MetodoPago.tarjeta: '💳 Tarjeta'
              };
              final isActive = pos.metodoPago == m;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onMetodoChange(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.teal
                          : Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              isActive ? Colors.tealAccent : Colors.white12),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                  color: Colors.tealAccent
                                      .withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3))
                            ]
                          : [],
                    ),
                    child: Text(labels[m]!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color:
                                isActive ? Colors.black : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        if (pos.metodoPago == MetodoPago.yapePlin)
          Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                width: 180,
                height: 220,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_2, size: 120, color: Colors.black87),
                    SizedBox(height: 12),
                    Text('QR Estático Negocio',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(180, 44)),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Confirmar pago visual'),
              ),
              const SizedBox(height: 12),
            ],
          ),

        if (pos.metodoPago == MetodoPago.efectivo)
          _cashSection(),

        if (pos.metodoPago == MetodoPago.efectivo)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _resumenEfectivo(context),
          ),
      ],
    );
  }

  Widget _cashSection() {
    return _section(
      title: 'Cobro en efectivo',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paso 1: escribe o toca un atajo de monto',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _montoChip(label: 'Exacto', value: pos.totalCobrar),
              _montoChip(label: '+ 5', value: pos.totalCobrar + 5),
              _montoChip(label: '+ 10', value: pos.totalCobrar + 10),
              _montoChip(label: '+ 20', value: pos.totalCobrar + 20),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: montoCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white, fontSize: 20),
            onChanged: (_) => onMontoChanged(),
            decoration: const InputDecoration(
              labelText: 'Monto recibido',
              labelStyle: TextStyle(color: Colors.white54),
              prefixText: 'S/. ',
              prefixStyle: TextStyle(
                  color: Colors.teal,
                  fontWeight: FontWeight.bold,
                  fontSize: 20),
              enabledBorder:
                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder:
                  UnderlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resumenEfectivo(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rowResumen('Total', pos.totalCobrar),
          _rowResumen('Recibido', pos.montoRecibido),
          const SizedBox(height: 6),
          const Text('Vuelto calculado',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('S/.${pos.vuelto.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 44,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  vueltoConfirmado ? Colors.greenAccent : Colors.white12,
              foregroundColor: vueltoConfirmado ? Colors.black : Colors.white,
            ),
            onPressed: onConfirmVuelto,
            icon: const Icon(Icons.handshake_outlined),
            label: Text(
                vueltoConfirmado
                    ? 'Vuelto entregado'
                    : 'Confirmar entrega de vuelto',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (requiereConfirmacionVuelto && !montoEditado)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Ingresa el monto recibido para habilitar el cobro',
                  style: TextStyle(color: Colors.orange, fontSize: 12)),
            ),
        ],
      ),
    );
  }

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

  Widget _montoChip({required String label, required double value}) {
    return ActionChip(
      label: Text(label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      side: const BorderSide(color: Colors.white24),
      onPressed: () => onQuickAmount(value),
    );
  }

  Widget _rowResumen(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          Text('S/.${value.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
