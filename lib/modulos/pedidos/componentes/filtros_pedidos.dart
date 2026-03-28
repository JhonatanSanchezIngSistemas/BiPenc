import 'package:flutter/material.dart';

enum FiltroPedidos { todos, porCobrar, canceladas }

class EncabezadoResumenPedidos extends StatelessWidget {
  final int total;
  final int canceladas;
  final double pendiente;
  final FiltroPedidos current;
  final ValueChanged<FiltroPedidos> onFilterChange;

  const EncabezadoResumenPedidos({
    super.key,
    required this.total,
    required this.canceladas,
    required this.pendiente,
    required this.current,
    required this.onFilterChange,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: ChipMetrica(
                  label: 'Listas',
                  value: '$total',
                  color: Colors.tealAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChipMetrica(
                  label: 'Canceladas',
                  value: '$canceladas',
                  color: Colors.greenAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChipMetrica(
                  label: 'Por Cobrar',
                  value: 'S/.${pendiente.toStringAsFixed(2)}',
                  color: Colors.orangeAccent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            ChipFiltro(
              text: 'Todas',
              active: current == FiltroPedidos.todos,
              onTap: () => onFilterChange(FiltroPedidos.todos),
            ),
            const SizedBox(width: 8),
            ChipFiltro(
              text: 'Por Cobrar',
              active: current == FiltroPedidos.porCobrar,
              onTap: () => onFilterChange(FiltroPedidos.porCobrar),
            ),
            const SizedBox(width: 8),
            ChipFiltro(
              text: 'Canceladas',
              active: current == FiltroPedidos.canceladas,
              onTap: () => onFilterChange(FiltroPedidos.canceladas),
            ),
          ],
        ),
      ],
    );
  }
}

class ChipMetrica extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const ChipMetrica({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class ChipFiltro extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback onTap;
  const ChipFiltro({
    super.key,
    required this.text,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? Colors.teal : Colors.grey.shade900,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: active ? Colors.tealAccent : Colors.white12,
            ),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.black : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
