import 'package:flutter/material.dart';
import 'package:bipenc/modulos/caja/proveedor_caja.dart';
import 'package:bipenc/servicios/servicio_sesion.dart';
import 'package:bipenc/ui/indicador_estado_impresora.dart';

class EncabezadoCaja extends StatelessWidget {
  final ProveedorCaja pos;
  final bool isAdmin;
  final bool modoEscaneoContinuo;
  final VoidCallback onEscaneoSimple;
  final VoidCallback onModoRafaga;
  final VoidCallback onRayito;
  final VoidCallback onAgregarGenerico;
  const EncabezadoCaja({
    super.key,
    required this.pos,
    required this.isAdmin,
    required this.modoEscaneoContinuo,
    required this.onEscaneoSimple,
    required this.onModoRafaga,
    required this.onRayito,
    required this.onAgregarGenerico,
  });

  @override
  Widget build(BuildContext context) {
    final bool online = pos.isOnline;
    final Color barColor = online
        ? (isAdmin ? const Color(0xFF332A00) : const Color(0xFF0E2C26))
        : Colors.grey.shade900;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: BoxDecoration(
        color: barColor,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: Row(
                children: [
                  _PildoraCliente(
                    label: 'C${pos.activeCartIndex + 1}',
                    isAdmin: isAdmin,
                    onTap: () => _abrirSelectorCarritos(context, pos),
                  ),
                  const SizedBox(width: 6),
                  _BotonAgregarCliente(
                    onTap: () => _crearNuevoCliente(context, pos),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _InsigniaIcono(child: IndicadorEstadoImpresora.custom()),
          const SizedBox(width: 8),
          _AccionIcono(
            icon: Icons.qr_code_scanner,
            onTap: onEscaneoSimple,
            active: modoEscaneoContinuo,
            tooltip: 'Escanear producto',
            isAdmin: isAdmin,
          ),
          const SizedBox(width: 8),
          _AccionIcono(
            icon: Icons.add_circle_outline,
            onTap: onAgregarGenerico,
            tooltip: 'Agregar producto rápido',
            isAdmin: isAdmin,
          ),
          const SizedBox(width: 8),
          _AccionIcono(
            icon: Icons.bolt,
            onTap: onModoRafaga,
            tooltip: 'Modo ráfaga',
            isAdmin: isAdmin,
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            color: Colors.grey.shade900,
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            onSelected: (value) {
              if (value == 'consulta') onRayito();
            },
            itemBuilder: (_) => _buildMenuItems(),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(
        value: 'consulta',
        child: Row(
          children: [
            Icon(Icons.flash_on_outlined, size: 18, color: Colors.white70),
            SizedBox(width: 8),
            Text('Consulta rápida'),
          ],
        ),
      ),
      const PopupMenuDivider(),
    ];

    return items;
  }

  void _crearNuevoCliente(BuildContext context, ProveedorCaja pos) {
    final next = List.generate(pos.maxCarritos, (i) => i)
        .firstWhere(
          (i) => i != pos.activeCartIndex && pos.isCartEmpty(i),
          orElse: () => -1,
        );

    if (next == -1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ya hay 5 clientes abiertos. Usa el menú para cambiar.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    pos.cambiarCarrito(next);
  }

  Future<void> _abrirSelectorCarritos(
      BuildContext context, ProveedorCaja pos) async {
    final bool isAdmin = ServicioSesion().rol == RolesApp.admin;
    final Color activeColor = isAdmin ? Colors.amberAccent : Colors.tealAccent;

    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(12),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Text('Clientes rápidos',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2)),
              const SizedBox(height: 6),
              ...List.generate(pos.maxCarritos, (i) {
                final isActive = i == pos.activeCartIndex;
                final count = pos.cartItemCount(i);
                return ListTile(
                  dense: true,
                  leading: Icon(
                    isActive
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isActive ? activeColor : Colors.white54,
                  ),
                  title: Text('C${i + 1}',
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    count == 0 ? 'Sin productos' : '$count en carrito',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  trailing:
                      isActive ? const _InsigniaSuave(text: 'Activo') : null,
                  onTap: () => Navigator.pop(ctx, i),
                );
              }),
            ],
          ),
        ),
      ),
    );

    if (selected != null) pos.cambiarCarrito(selected);
  }
}

class _PildoraCliente extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isAdmin;
  const _PildoraCliente({
    required this.label,
    required this.onTap,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isAdmin
              ? Colors.amber.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isAdmin
                  ? Colors.amber.withValues(alpha: 0.5)
                  : Colors.white24),
        ),
        child: Text(label,
            style: TextStyle(
                color: isAdmin ? Colors.amberAccent : Colors.white,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _BotonAgregarCliente extends StatelessWidget {
  final VoidCallback onTap;
  const _BotonAgregarCliente({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      icon:
          const Icon(Icons.add_circle_outline, color: Colors.white70, size: 22),
      tooltip: 'Nuevo cliente (nuevo carrito)',
      onPressed: onTap,
    );
  }
}

class _InsigniaSuave extends StatelessWidget {
  final String text;
  const _InsigniaSuave({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white70, fontSize: 11)),
    );
  }
}

class _AccionIcono extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;
  final bool isAdmin;
  const _AccionIcono({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color accentColor = isAdmin ? Colors.amberAccent : Colors.tealAccent;

    final content = Icon(
      icon,
      color: active ? accentColor : Colors.white70,
      size: 20,
    );
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? accentColor : Colors.white12,
              width: active ? 1.4 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );
  }
}

class _InsigniaIcono extends StatelessWidget {
  final Widget child;
  const _InsigniaIcono({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
