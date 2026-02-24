import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/print_service.dart';
import '../../services/identidad_service.dart';
import '../../data/local/db_helper.dart';
import '../../data/models/cliente.dart';
import 'pos_provider.dart';

// Definición de _ResumenPagoPanel
class _ResumenPagoPanel extends StatefulWidget {
  final PosProvider posState;
  const _ResumenPagoPanel({required this.posState});

  @override
  State<_ResumenPagoPanel> createState() => _ResumenPagoPanelState();
}

class _ResumenPagoPanelState extends State<_ResumenPagoPanel> {
  final _recibidoCtrl = TextEditingController();
  final _docCtrl = TextEditingController();
  final _nombreManualCtrl = TextEditingController();
  bool _isSearchingId = false;

  @override
  void dispose() {
    _recibidoCtrl.dispose();
    _docCtrl.dispose();
    _nombreManualCtrl.dispose();
    super.dispose();
  }

  Future<void> _ejecutarCobro(BuildContext context, PosProvider posState) async {
    // Generamos boleta en BD
    await posState.procesarVenta();
    
    if (mounted) {
      // Módulo de Impresión Defensiva
      try {
        bool impreso = await PrintService().imprimirTicketCortesía(posState);
        if (!impreso) {
          _mostrarErrorImpresora(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venta Registrada e Impresa', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.teal));
        }
      } catch (e) {
          _mostrarErrorImpresora(context);
      }
    }
  }

  void _iniciarFlujoIdentidad(BuildContext context, PosProvider posState) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Identidad del Cliente'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_search, color: Colors.blue),
                title: const Text('Boleta (DNI)'),
                onTap: () { Navigator.pop(ctx); _mostrarIngresoDocumento(context, posState, false); },
              ),
              ListTile(
                leading: const Icon(Icons.domain, color: Colors.orange),
                title: const Text('Factura (RUC)'),
                onTap: () { Navigator.pop(ctx); _mostrarIngresoDocumento(context, posState, true); },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.flash_on, color: Colors.amber),
                title: const Text('Venta Rápida (Cliente Genérico)'),
                subtitle: const Text('Omite este paso (< 2s)'),
                onTap: () {
                  Navigator.pop(ctx);
                  posState.setCliente(Cliente(documento: '00000000', nombre: 'Público en General'));
                  _ejecutarCobro(context, posState);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            )
          ],
        );
      }
    );
  }

  void _mostrarIngresoDocumento(BuildContext context, PosProvider posState, bool esRuc) {
    _docCtrl.clear();
    _nombreManualCtrl.clear();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctxDialog) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> buscarRevisarDb() async {
              final doc = _docCtrl.text.trim();
              if (doc.isEmpty) return;

              setModalState(() => _isSearchingId = true);

              // 1. Caché Local Ultra-Rápida (Cero latencia si es cliente frecuente)
              Cliente? clienteDb = await DBHelper().getCliente(doc);
              if (clienteDb != null) {
                posState.setCliente(clienteDb);
                if (mounted) Navigator.pop(ctxDialog);
                _ejecutarCobro(context, posState);
                return;
              }

              // 2. Consulta Nube (Reniec/Sunat)
              final apiResult = await IdentidadService().consultarDocumento(doc, esRuc);
              setModalState(() => _isSearchingId = false);

              if (apiResult != null && apiResult != 'OFFLINE' && apiResult != 'ERROR') {
                final nuevoCliente = Cliente(documento: doc, nombre: apiResult);
                await DBHelper().insertCliente(nuevoCliente); // Guardamos en Caché Local
                posState.setCliente(nuevoCliente);
                
                if (mounted) Navigator.pop(ctxDialog);
                _ejecutarCobro(context, posState);
              } else {
                // Modo Offline o Falla de API: Ingreso Manual obligatorio
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sin conexión o documento no encontrado. Ingrese datos manualmente.')));
              }
            }

            return AlertDialog(
              title: Text(esRuc ? 'Ingresar RUC' : 'Ingresar DNI'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _docCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: esRuc ? 'RUC (11 dígitos)' : 'DNI (8 dígitos)',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isSearchingId) const CircularProgressIndicator(),
                  // Campo manual semi-oculto que se usa si la API falla
                  if (!_isSearchingId)
                    TextField(
                      controller: _nombreManualCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre o Razón Social (Opcional si API falla)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctxDialog), child: const Text('Cancelar')),
                FilledButton.icon(
                  onPressed: _isSearchingId ? null : () {
                     if (_nombreManualCtrl.text.isNotEmpty) {
                       // Forzar guardado manual si el usuario ya escribió algo
                       final manualCli = Cliente(documento: _docCtrl.text, nombre: _nombreManualCtrl.text);
                       DBHelper().insertCliente(manualCli);
                       posState.setCliente(manualCli);
                       Navigator.pop(ctxDialog);
                       _ejecutarCobro(context, posState);
                     } else {
                       buscarRevisarDb(); // Buscar automáticamente
                     }
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('Buscar y Cobrar'),
                )
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final posState = widget.posState;
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Resumen de Pago', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          
          // Selector de Método de Pago
          SegmentedButton<MetodoPago>(
            segments: const [
              ButtonSegment(value: MetodoPago.efectivo, icon: Icon(Icons.money), label: Text('Efectivo')),
              ButtonSegment(value: MetodoPago.yapePlin, icon: Icon(Icons.qr_code), label: Text('Yape')),
              ButtonSegment(value: MetodoPago.tarjeta, icon: Icon(Icons.credit_card), label: Text('Tarjeta')),
            ],
            selected: {posState.metodoPago},
            onSelectionChanged: (Set<MetodoPago> newSelection) {
              posState.setMetodoPago(newSelection.first);
              if (newSelection.first != MetodoPago.efectivo) {
                _recibidoCtrl.text = posState.totalCobrar.toStringAsFixed(2);
              } else {
                _recibidoCtrl.clear();
              }
            },
          ),
          const SizedBox(height: 16),
          
          if (posState.metodoPago == MetodoPago.efectivo)
            TextField(
              controller: _recibidoCtrl,
              decoration: const InputDecoration(labelText: 'Monto Recibido (\$)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (val) {
                final amount = double.tryParse(val) ?? 0.0;
                posState.setMontoRecibido(amount);
              },
            ),

          if (posState.metodoPago == MetodoPago.efectivo && posState.vuelto > 0)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('VUELTO A ENTREGAR:', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('\$${posState.vuelto.toStringAsFixed(2)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 24)),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 24),
          _RenglonResumen(label: 'Subtotal', value: posState.subtotal),
          _RenglonResumen(label: 'Descuento M(3+)', value: 0.0, textColor: Colors.green), // Calculamos la diff real después
          const Divider(height: 32),
          _RenglonResumen(label: 'TOTAL', value: posState.totalCobrar, isTotal: true),
          const Spacer(),
          SizedBox(
            height: 60,
            child: FilledButton.icon(
              onPressed: posState.canCheckout ? () => _iniciarFlujoIdentidad(context, posState) : null,
              icon: const Icon(Icons.payments, size: 28),
              label: const Text('COBRAR E IMPRIMIR', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarErrorImpresora(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.print_disabled, color: Colors.red), SizedBox(width: 8), Text('Impresora No Detectada')]),
        content: const Text('La venta fue cobrada y guardada en el sistema, pero no se pudo conectar con la ticketera Bluetooth.\n\n¿Desea re-intentar o continuar guardándolo como Ticket Pendiente?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Continuar sin Imprimir')),
          FilledButton.icon(
            onPressed: () {
               Navigator.pop(ctx);
               // Reintento opcional
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Re-intentar'),
          )
        ],
      )
    );
  }
}

// Reemplazando el class original _ResumenPagoPanel
class _ObsoleteResumen extends StatelessWidget {

class _PosScreenState extends State<PosScreen> {
  final TextEditingController _searchController = TextEditingController();

  void _escanearCodigo() {
    // TODO: Integrar cámara para buscar productos rápidos
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Escáner activado (Simulación)')),
    );
  }

  void _mostrarUltimosTickets(BuildContext context) async {
    final tickets = await context.read<PosProvider>().obtenerUltimosTickets();
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Últimos 5 Tickets', style: Theme.of(context).textTheme.titleLarge),
              const Divider(),
              Expanded(
                child: tickets.isEmpty 
                  ? const Center(child: Text('No hay ventas registradas aún.'))
                  : ListView.builder(
                      itemCount: tickets.length,
                      itemBuilder: (context, index) {
                        final v = tickets[index];
                        return ListTile(
                          leading: Icon(Icons.receipt_long, color: Theme.of(context).primaryColor),
                          title: Text('Ticket: ${v.id.substring(v.id.length - 6)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(v.resumenItems, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('\$${v.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text(v.metodoPago.name.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                          onTap: () {
                            // Lógica de re-impresión pasándola a PrintService...
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Comando de Re-impresión enviado (Simulado)')));
                            Navigator.pop(ctx);
                          },
                        );
                      }
                    ),
              )
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final posState = context.watch<PosProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Punto de Venta'),
            const SizedBox(width: 8),
            // Semáforo de Conexión en vivo
            Container(
              width: 12, height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: posState.isOnline ? Colors.greenAccent : Colors.red,
                boxShadow: [
                  BoxShadow(color: posState.isOnline ? Colors.green : Colors.red, blurRadius: 4),
                ]
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_toggle_off),
            tooltip: 'Últimos Tickets',
            onPressed: () => _mostrarUltimosTickets(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () {
              if (posState.items.isNotEmpty) {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Vaciar Carrito'),
                    content: const Text('¿Estás seguro de cancelar esta venta?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('No')),
                      FilledButton(
                        onPressed: () {
                          context.read<PosProvider>().vaciarCarrito();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Sí, vaciar'),
                      ),
                    ],
                  ),
                );
              }
            },
          )
        ],
      ),
      body: SafeArea(
        child: Row(
          children: [
            // PANEL IZQUIERDO: Búsqueda y Lista de Carrito (70% del ancho en Tablets, 100% en Móviles)
            Expanded(
            flex: 6,
            child: Column(
              children: [
                // Pestañas Multi-Carrito (Máximo 3 Clientes en Espera)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: theme.colorScheme.surface,
                  child: Row(
                    children: [
                      const Icon(Icons.people_alt_outlined, color: Colors.grey),
                      const SizedBox(width: 8),
                      ToggleButtons(
                        isSelected: [
                          posState.activeCartIndex == 0,
                          posState.activeCartIndex == 1,
                          posState.activeCartIndex == 2,
                        ],
                        onPressed: (index) => context.read<PosProvider>().cambiarCarrito(index),
                        borderRadius: BorderRadius.circular(8),
                        children: [
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('Caja 1', style: TextStyle(color: posState.isCartEmpty(0) ? null : Colors.teal, fontWeight: posState.isCartEmpty(0) ? FontWeight.normal : FontWeight.bold))),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('Caja 2', style: TextStyle(color: posState.isCartEmpty(1) ? null : Colors.teal, fontWeight: posState.isCartEmpty(1) ? FontWeight.normal : FontWeight.bold))),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('Caja 3', style: TextStyle(color: posState.isCartEmpty(2) ? null : Colors.teal, fontWeight: posState.isCartEmpty(2) ? FontWeight.normal : FontWeight.bold))),
                        ],
                      ),
                    ],
                  ),
                ),
                // Barra de Escaneo / Búsqueda
                Container(
                  padding: const EdgeInsets.all(16.0),
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Ingresar Código de Barras o Nombre...',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: theme.colorScheme.surface,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
                          onSubmitted: (val) async {
                            final codigo = val.trim();
                            if (codigo.isEmpty) return;
                            
                            final prov = context.read<PosProvider>();
                            final p = await prov.buscarYLlenarCache(codigo);
                            
                            if (p != null && mounted) {
                              prov.agregarProducto(p, p.presentaciones.first);
                              _searchController.clear();
                            } else if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Producto no encontrado.'), backgroundColor: Colors.redAccent),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      FloatingActionButton.small(
                        heroTag: 'gen_btn',
                        onPressed: () => context.read<PosProvider>().agregarProductoGenerico(),
                        backgroundColor: Colors.amber,
                        child: const Icon(Icons.bolt, color: Colors.black),
                        tooltip: 'Venta Rápida (Genérica)',
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        heroTag: 'scan_btn',
                        onPressed: _escanearCodigo,
                        child: const Icon(Icons.qr_code_scanner),
                      ),
                    ],
                  ),
                ),
                
                // Lista de Productos en el Carrito
                Expanded(
                  child: posState.items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text('El carrito está vacío', style: TextStyle(color: Colors.grey.shade600, fontSize: 18)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: posState.items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = posState.items[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                                child: Text(item.cantidad.toString(), style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(item.product.descripcion, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${item.presentacion.nombre} • ${item.product.marca}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                    onPressed: () => context.read<PosProvider>().actualizarCantidad(index, -1),
                                  ),
                                  Text(
                                    '\$${item.subtotal.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                                    onPressed: () => context.read<PosProvider>().actualizarCantidad(index, 1),
                                  ),
                                ],
                              ),
                              onLongPress: () {
                                if (item.product.requiereAutorizacion) {
                                  // TODO: Abrir modal del SecurityService PIN para cambiar precio manual
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // PANEL DERECHO: Resumen de Pago (Visible siempre en Tablet, o usar BottomSheet en Móvil)
          if (MediaQuery.of(context).size.width > 600)
            Expanded(
              flex: 4,
              child: _ResumenPagoPanel(posState: posState),
            ),
        ],
      ),
      ),
      
      // Bottom Bar visible solo en teléfonos (width < 600)
      bottomNavigationBar: MediaQuery.of(context).size.width <= 600
        ? _ResumenPagoBottomBar(posState: posState)
        : null,
    );
  }
}

}

/// Barra inferior compacta para vista móvil (Vendedores de Pasillo)
class _ResumenPagoBottomBar extends StatelessWidget {
  final PosProvider posState;
  const _ResumenPagoBottomBar({required this.posState});

  @override
  Widget build(BuildContext context) {
    if (posState.items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total a Cobrar', style: TextStyle(color: Colors.grey)),
                Text('\$${posState.totalCobrar.toStringAsFixed(2)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
            FilledButton.icon(
              onPressed: () { /* TODO: Imprimir */ },
              icon: const Icon(Icons.print),
              label: const Text('COBRAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RenglonResumen extends StatelessWidget {
  final String label;
  final double value;
  final bool isTotal;
  final Color? textColor;

  const _RenglonResumen({required this.label, required this.value, this.isTotal = false, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: isTotal ? 20 : 16, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text('\$${value.toStringAsFixed(2)}', style: TextStyle(fontSize: isTotal ? 24 : 16, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, color: textColor)),
        ],
      ),
    );
  }
}
