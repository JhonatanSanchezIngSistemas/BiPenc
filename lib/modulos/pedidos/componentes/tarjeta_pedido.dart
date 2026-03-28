import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bipenc/datos/modelos/pedido.dart';

class TarjetaPedido extends StatelessWidget {
  final Pedido orden;
  final VoidCallback onTap;

  const TarjetaPedido({
    super.key,
    required this.orden,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fechaFormato = DateFormat('dd/MM/yyyy HH:mm').format(orden.llegadaAt);
    final recojoFormato =
        DateFormat('dd/MM/yyyy HH:mm').format(orden.fechaRecojo);
    final estadoColor = orden.estaCancelado ? Colors.green : Colors.orange;
    final estadoLabel = orden.estaCancelado
        ? 'CANCELADO'
        : 'DEBE S/.${orden.saldoPendiente.toStringAsFixed(2)}';

    return Card(
      color: Colors.grey.shade900,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          orden.clienteNombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text('ID: ${orden.id}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (orden.telefonoContacto != null &&
                            orden.telefonoContacto!.isNotEmpty)
                          Text('Tel: ${orden.telefonoContacto}',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                        if (orden.responsable != null &&
                            orden.responsable!.isNotEmpty)
                          Text('Resp: ${orden.responsable}',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: estadoColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      estadoLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.attach_money,
                      size: 18, color: Colors.tealAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pagado: S/.${orden.montoAdelantado.toStringAsFixed(2)} / '
                      'Total: S/.${orden.totalLista.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                  const Icon(Icons.calendar_today,
                      size: 18, color: Colors.tealAccent),
                  const SizedBox(width: 8),
                  Text(
                    'Llegó: $fechaFormato',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Recojo: $recojoFormato',
                  style:
                      const TextStyle(color: Colors.tealAccent, fontSize: 12)),
              if (orden.fotosUrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.image, size: 16, color: Colors.tealAccent),
                    const SizedBox(width: 8),
                    Text(
                      '${orden.fotosUrls.length} foto${orden.fotosUrls.length > 1 ? 's' : ''}',
                      style: const TextStyle(
                          color: Colors.tealAccent, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
