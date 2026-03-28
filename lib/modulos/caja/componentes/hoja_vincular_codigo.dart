import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bipenc/modulos/caja/proveedor_caja.dart';
import 'package:bipenc/servicios/servicio_db_local.dart';

/// Hoja de vinculación "on-the-fly".
/// Se abre cuando:
///   a) Un código desconocido se escanea → permite vincularlo a un producto existente.
///   b) Un ítem del carrito necesita corrección de vínculo.
///
/// [codigoBarras] — código a vincular.
/// [productoAntiguo] — si se está corrigiendo, el producto actual del ítem.
///
/// Uso:
/// ```dart
/// await showHojaVincularCodigo(context, pos: pos, codigoBarras: '000000');
/// ```
Future<void> showHojaVincularCodigo(
  BuildContext context, {
  required ProveedorCaja pos,
  required String codigoBarras,
  Producto? productoAntiguo,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => HojaVincularCodigo(
      pos: pos,
      codigoBarras: codigoBarras,
      productoAntiguo: productoAntiguo,
    ),
  );
}

class HojaVincularCodigo extends StatefulWidget {
  final ProveedorCaja pos;
  final String codigoBarras;
  final Producto? productoAntiguo; // null = vincular nuevo, no-null = corregir

  const HojaVincularCodigo({
    super.key,
    required this.pos,
    required this.codigoBarras,
    this.productoAntiguo,
  });

  @override
  State<HojaVincularCodigo> createState() => _HojaVincularCodigoState();
}

class _HojaVincularCodigoState extends State<HojaVincularCodigo> {
  final _searchCtrl = TextEditingController();
  List<Producto> _resultados = [];
  Producto? _seleccionado;
  bool _buscando = false;
  bool _vinculando = false;
  Timer? _debounce;

  bool get _esModoCorreccion => widget.productoAntiguo != null;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _buscar(q));
  }

  Future<void> _buscar(String q) async {
    if (q.trim().length < 2) {
      if (mounted) setState(() => _resultados = []);
      return;
    }
    if (mounted) setState(() => _buscando = true);
    final res = await widget.pos.buscarProductos(q);
    if (mounted) {
      setState(() {
        _resultados = res;
        _buscando = false;
      });
    }
  }

  Future<void> _confirmarVinculo() async {
    final target = _seleccionado;
    if (target == null) return;

    // Check duplicado: ¿ya hay un vínculo para este código?
    final vinculosExistentes =
        await _checkVinculosExistentes(widget.codigoBarras);
    if (vinculosExistentes.isNotEmpty && !_esModoCorreccion) {
      if (!mounted) return;
      final confirmar = await _mostrarAlertaDuplicado(context, vinculosExistentes);
      if (confirmar != true) return;
    }

    if (!mounted) return;
    setState(() => _vinculando = true);

    try {
      if (_esModoCorreccion) {
        await widget.pos.corregirVinculo(
          widget.codigoBarras,
          widget.productoAntiguo!,
          target,
        );
      } else {
        await widget.pos.vincularCodigo(widget.codigoBarras, target);
      }

      HapticFeedback.heavyImpact();

      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.link, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _esModoCorreccion
                    ? '✅ Vínculo corregido: "${target.nombre}"'
                    : '✅ "${widget.codigoBarras}" vinculado a "${target.nombre}"',
              ),
            ),
          ]),
          backgroundColor: Colors.teal.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al vincular: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _vinculando = false);
    }
  }

  Future<List<Map<String, dynamic>>> _checkVinculosExistentes(
      String codigo) async {
    try {
      return await ServicioDbLocal.getVinculosPorCodigo(codigo);
    } catch (_) {
      return [];
    }
  }

  Future<bool?> _mostrarAlertaDuplicado(
      BuildContext ctx, List<Map<String, dynamic>> existentes) {
    return showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C2E),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber),
            SizedBox(width: 8),
            Text('Código ya vinculado',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Text(
          'Este código ya está vinculado a ${existentes.length} producto(s).\n\n'
          '¿Estás seguro de que también pertenece al producto seleccionado?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.white38)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Vincular igual',
                style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isModoCorreccion = _esModoCorreccion;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF111827),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isModoCorreccion ? Icons.edit_attributes : Icons.add_link,
                    color: Colors.tealAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isModoCorreccion
                            ? 'Corregir Vínculo'
                            : 'Vincular Código',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Código: "${widget.codigoBarras}"',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (isModoCorreccion) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link_off,
                        color: Colors.redAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Se desvinculará de: "${widget.productoAntiguo!.nombre}"',
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Buscador
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Buscar producto por nombre, marca o SKU...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.teal, size: 20),
                suffixIcon: _buscando
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.teal),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Resultados de búsqueda
            if (_resultados.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.35,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _resultados.length,
                  itemBuilder: (_, i) {
                    final p = _resultados[i];
                    final isSelected = _seleccionado?.id == p.id;
                    return _ResultadoItem(
                      producto: p,
                      isSelected: isSelected,
                      onTap: () => setState(() => _seleccionado = p),
                    );
                  },
                ),
              )
            else if (!_buscando && _searchCtrl.text.length >= 2)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Sin resultados',
                  style: TextStyle(color: Colors.white38),
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 16),

            // Botón de confirmación
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _seleccionado != null
                    ? Colors.teal
                    : Colors.white12,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: (_seleccionado != null && !_vinculando)
                  ? _confirmarVinculo
                  : null,
              icon: _vinculando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(isModoCorreccion ? Icons.swap_horiz : Icons.link),
              label: Text(
                _seleccionado != null
                    ? (isModoCorreccion
                        ? 'Corregir a "${_seleccionado!.nombre}"'
                        : 'Vincular a "${_seleccionado!.nombre}"')
                    : 'Selecciona un producto primero',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultadoItem extends StatelessWidget {
  final Producto producto;
  final bool isSelected;
  final VoidCallback onTap;

  const _ResultadoItem({
    required this.producto,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.teal.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? Colors.tealAccent : Colors.white10,
            ),
          ),
          child: Row(
            children: [
              if (isSelected)
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Icon(Icons.check_circle_rounded,
                      color: Colors.tealAccent, size: 18),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      producto.nombre,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                    if (producto.marca.isNotEmpty)
                      Text(
                        producto.marca,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11),
                      ),
                  ],
                ),
              ),
              Text(
                producto.precioBase > 0
                    ? 'S/.${producto.precioBase.toStringAsFixed(2)}'
                    : '',
                style: const TextStyle(
                    color: Colors.tealAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

