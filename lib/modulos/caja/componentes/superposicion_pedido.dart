import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class SuperposicionPedido extends StatelessWidget {
  final String fotoUrl;
  const SuperposicionPedido({super.key, required this.fotoUrl});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 12, bottom: 4),
        child: GestureDetector(
          onTap: () => _abrirImagen(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
              ),
              width: 90,
              height: 90,
              child: Image.network(
                fotoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade800,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image, color: Colors.white54),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _abrirImagen(BuildContext context) {
    bool invert = false;
    bool sharpen = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(_matrixFor(invert, sharpen)),
                  child: Image.network(
                    fotoUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      height: 200,
                      color: Colors.grey.shade900,
                      alignment: Alignment.center,
                      child: const Text('No se pudo cargar la foto',
                          style: TextStyle(color: Colors.white70)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() => invert = !invert);
                      },
                      icon: const Icon(Icons.invert_colors,
                          color: Colors.tealAccent),
                      label: Text(invert ? 'Color normal' : 'Invertir',
                          style: const TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() => sharpen = !sharpen);
                      },
                      icon: const Icon(Icons.auto_fix_high,
                          color: Colors.tealAccent),
                      label: Text(sharpen ? 'Normal' : 'Mejorar',
                          style: const TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Share.shareUri(Uri.parse(fotoUrl));
                      },
                      icon: const Icon(Icons.share, color: Colors.tealAccent),
                      label: const Text('Compartir',
                          style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('Cerrar'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      }),
    );
  }
}

List<double> _matrixFor(bool invert, bool sharpen) {
  // sharpen via simple contrast boost
  const normal = <double>[
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];
  const inverted = <double>[
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ];
  final base = invert ? inverted : normal;
  if (!sharpen) return base;
  // simple contrast +15%
  const c = 1.15;
  return List<double>.generate(
      20, (i) => base[i] * (i % 6 == 0 ? c : 1));
}
