import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';

import 'servicio_procesamiento_imagen.dart';

class ResultadoFotoPedido {
  final File imagenFinal;
  final List<File> temporales;
  final String? etapaFallida; // para diagnóstico

  ResultadoFotoPedido({
    required this.imagenFinal,
    List<File>? temporales,
    this.etapaFallida,
  }) : temporales = temporales ?? const [];
}

/// Callback para informar el progreso del procesamiento al UI.
typedef ProgresoCallback = void Function(String etapa);

/// Orquesta la captura y limpieza visual de la foto de la lista.
/// Aplica un pipeline tipo CamScanner cuando la foto viene de cámara estándar.
class ServicioFotoPedido {
  ServicioFotoPedido({ServicioProcesamientoImagen? processing})
      : _proc = processing ?? ServicioProcesamientoImagen();

  final ServicioProcesamientoImagen _proc;

  /// Usa el escáner nativo de ML Kit. Devuelve null si se cancela o falla.
  Future<File?> capturarConEscaner() async {
    DocumentScanner? scanner;
    try {
      scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormats: {DocumentFormat.jpeg},
          pageLimit: 1,
          mode: ScannerMode.full,
          isGalleryImport: false,
        ),
      );
      final result = await scanner.scanDocument();
      final images = result.images;
      if (images != null && images.isNotEmpty) {
        final path = images.first;
        if (path.isNotEmpty) {
          final file = File(path);
          if (await file.exists()) return file;
        }
      }
    } on PlatformException catch (e) {
      debugPrint('[FotoService] ML Kit PlatformException: $e');
      // Ignoramos para no romper UX; caller decide fallback.
    } catch (e) {
      debugPrint('[FotoService] ML Kit error: $e');
    } finally {
      try {
        await scanner?.close();
      } catch (_) {}
    }
    return null;
  }

  /// Procesa la foto para dejar fondo blanco y bordes limpios.
  ///
  /// - [desdeScanner]: si vino del escáner nativo → solo sharpening suave
  ///   (ya viene con perspectiva corregida y fondo limpio).
  /// - [desdeScanner] = false → aplica el pipeline completo de 5 pasos:
  ///   glare removal → grayscale → denoising → binarización adaptativa → sharpening.
  ///
  /// [onProgreso] permite actualizar el UI con el estado actual.
  Future<ResultadoFotoPedido> procesarImagen({
    required File baseFile,
    required bool desdeScanner,
    ProgresoCallback? onProgreso,
  }) async {
    final temporales = <File>[];
    String? etapaFallida;

    File imagenFile;

    if (desdeScanner) {
      // ── Camino A: Escáner nativo ─────────────────────────────────────────
      // El escáner ya corrigió perspectiva, recortó y mejoró iluminación.
      // Solo comprimimos para reducir tamaño de almacenamiento + sharpening leve.
      onProgreso?.call('Optimizando imagen...');
      XFile? compressed = await _proc.comprimirImagen(XFile(baseFile.path));
      final base = compressed != null ? File(compressed.path) : baseFile;
      if (compressed != null) temporales.add(base);

      onProgreso?.call('Mejorando nitidez...');
      final mejorada = await _proc.mejorarContraste(
        base,
        contraste: 1.2,
        brillo: 5,
      );
      if (mejorada != null) temporales.add(mejorada);
      imagenFile = mejorada ?? base;
    } else {
      // ── Camino B: Cámara estándar → Pipeline completo ────────────────────
      debugPrint('[FotoService] Iniciando pipeline completo (modo cámara)...');

      // Paso 0: Comprimir primero para reducir tiempo de procesamiento
      onProgreso?.call('Preparando imagen...');
      XFile? compressed = await _proc.comprimirImagen(XFile(baseFile.path));
      File baseComprimida =
          compressed != null ? File(compressed.path) : baseFile;
      if (compressed != null) temporales.add(baseComprimida);

      // Paso 1–5: Pipeline completo (glare + grayscale + denoise + binarización + sharpen)
      onProgreso?.call('Eliminando destellos y limpiando...');
      final procesada =
          await _proc.procesarDocumentoCompleto(baseComprimida);

      if (procesada != null) {
        temporales.add(procesada);
        imagenFile = procesada;
        debugPrint('[FotoService] ✓ Pipeline completo exitoso');
      } else {
        // Fallback: si el pipeline falla, usar el camino antiguo
        etapaFallida = 'pipeline_documento';
        debugPrint(
            '[FotoService] ⚠ Pipeline falló, usando fallback contraste...');
        onProgreso?.call('Ajustando imagen...');
        final mejorada = await _proc.mejorarContraste(
          baseComprimida,
          contraste: 1.4,
          brillo: 10,
        );
        if (mejorada != null) temporales.add(mejorada);
        imagenFile = mejorada ?? baseComprimida;
      }
    }

    onProgreso?.call('Listo');
    return ResultadoFotoPedido(
      imagenFinal: imagenFile,
      temporales: temporales,
      etapaFallida: etapaFallida,
    );
  }
}
