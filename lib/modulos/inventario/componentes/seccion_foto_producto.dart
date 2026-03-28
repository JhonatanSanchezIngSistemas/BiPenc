import 'dart:io';
import 'package:flutter/material.dart';

class SeccionFotoProducto extends StatelessWidget {
  final File? imagenLocal;
  final String? imagenUrl;
  final bool isProcesando;
  final VoidCallback? onTomarFoto;
  final VoidCallback? onReintentarRecorte;
  final VoidCallback? onToggleFlash;

  const SeccionFotoProducto({
    super.key,
    required this.imagenLocal,
    required this.imagenUrl,
    required this.isProcesando,
    required this.onTomarFoto,
    required this.onReintentarRecorte,
    required this.onToggleFlash,
  });

  @override
  Widget build(BuildContext context) {
    final ImageProvider? imageProvider = imagenLocal != null
        ? FileImage(imagenLocal!)
        : (imagenUrl != null && imagenUrl!.startsWith('http'))
            ? NetworkImage(imagenUrl!)
            : null;

    return Column(
      children: [
        Center(
          child: GestureDetector(
            onTap: isProcesando ? null : onTomarFoto,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.teal, width: 2),
                image: imageProvider != null
                    ? DecorationImage(image: imageProvider, fit: BoxFit.contain)
                    : null,
              ),
              child: isProcesando
                  ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.teal),
                        SizedBox(height: 8),
                        Text('Procesando...',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    )
                  : imageProvider == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.camera_alt,
                                size: 50, color: Colors.teal),
                            const SizedBox(height: 8),
                            Text('Foto del producto',
                                style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 12)),
                          ],
                        )
                      : const Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.check_circle,
                                color: Colors.teal, size: 28),
                          ),
                        ),
            ),
          ),
        ),
        if (imagenLocal != null && !isProcesando)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: onReintentarRecorte,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('REINTENTAR RECORTE',
                      style: TextStyle(fontSize: 10)),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onToggleFlash,
                  icon: const Icon(Icons.flash_on,
                      color: Colors.yellowAccent, size: 20),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
