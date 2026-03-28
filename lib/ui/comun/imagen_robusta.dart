import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Un widget robusto para renderizar imágenes de productos.
/// Soporta:
/// 1. Rutas de archivos locales (File).
/// 2. Cadenas en Base64.
/// 3. URLs (si se implementa en el futuro).
/// 4. Fallback a un ícono si todo lo anterior falla o es nulo.
class ImagenRobusta extends StatelessWidget {
  final String? imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData fallbackIcon;

  const ImagenRobusta({
    super.key,
    this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallbackIcon = Icons.inventory_2_outlined,
  });

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    if (imagePath == null || imagePath!.isEmpty) {
      imageWidget = _buildFallback();
    } else {
      // Intentar determinar si es Base64 o Ruta de Archivo
      if (_isBase64(imagePath!)) {
        try {
          final Uint8List bytes = base64Decode(imagePath!);
          imageWidget = Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stackTrace) => _buildFallback(),
          );
        } catch (e) {
          imageWidget = _buildFallback();
        }
      } else {
        // Asumir que es una ruta de archivo
        final file = File(imagePath!);
        if (file.existsSync()) {
          imageWidget = Image.file(
            file,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stackTrace) => _buildFallback(),
          );
        } else if (imagePath!.startsWith('http')) {
             imageWidget = Image.network(
                imagePath!,
                width: width,
                height: height,
                fit: fit,
                errorBuilder: (context, error, stackTrace) => _buildFallback(),
            );
        } else {
          imageWidget = _buildFallback();
        }
      }
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  bool _isBase64(String path) {
    // Una heurística simple para detectar Base64
    // Generalmente no contienen '/' de rutas de archivo al inicio
    // y tienen una longitud considerable sin espacios.
    if (path.contains('/') || path.contains('\\')) {
        if (path.startsWith('http')) return false; // URL
        return false; // Ruta de archivo
    }
    return path.length > 50; // Probablemente base64
  }

  Widget _buildFallback() {
    return Container(
      width: width,
      height: height,
      color: Colors.tealAccent.withValues(alpha: 0.1),
      child: Icon(
        fallbackIcon,
        color: Colors.tealAccent,
        size: (width != null) ? width! * 0.5 : 24,
      ),
    );
  }
}
