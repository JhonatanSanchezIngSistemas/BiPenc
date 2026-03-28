import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:bipenc/datos/modelos/pedido.dart';
import 'package:bipenc/servicios/servicio_pedidos.dart';
import 'package:bipenc/utilidades/registro_app.dart';
import 'package:bipenc/servicios/servicio_impresion.dart';
import 'package:bipenc/servicios/servicio_procesamiento_imagen.dart';
import 'package:bipenc/servicios/servicio_foto_pedido.dart';
import 'package:bipenc/servicios/servicio_ocr.dart';
import 'package:bipenc/servicios/servicio_db_local.dart';
import 'package:bipenc/datos/modelos/producto.dart';
import 'package:bipenc/servicios/servicio_sesion.dart';

class ModalDetallesPedido extends StatefulWidget {
  final Pedido orden;
  final VoidCallback onActualizar;

  const ModalDetallesPedido({
    super.key,
    required this.orden,
    required this.onActualizar,
  });

  @override
  State<ModalDetallesPedido> createState() => _ModalDetallesPedidoState();
}

class _ModalDetallesPedidoState extends State<ModalDetallesPedido> {
  final _service = ServicioPedidos();
  final _photoService = ServicioFotoPedido();
  final _ocrService = ServicioOcr();
  late Pedido _orden = widget.orden;
  bool _isUploadingFoto = false;
  String _progresoProcesamiento = 'Subiendo...';
  bool _isPrinting = false;

  Future<void> _registrarAbono() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Registrar Abono',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Monto abonado (S/.)',
            labelStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final monto = double.tryParse(ctrl.text.replaceAll(',', '.'));
    if (monto == null || monto <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Monto inválido'), backgroundColor: Colors.red),
      );
      return;
    }

    final nuevoPagado = _orden.montoAdelantado + monto;
    final okUpdate = await _service.updatePedidoFinancial(
      order: _orden,
      nuevoMontoPagado: nuevoPagado,
    );
    if (!mounted) return;
    if (!okUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se pudo guardar abono'),
            backgroundColor: Colors.red),
      );
      return;
    }
    setState(() {
      _orden = _orden.copyWith(montoAdelantado: nuevoPagado);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _orden.estaCancelado
              ? 'Lista cancelada totalmente'
              : 'Abono registrado',
        ),
        backgroundColor: Colors.teal,
      ),
    );
    widget.onActualizar();
  }

  Future<void> _editarFinanzasYContacto() async {
    final totalCtrl =
        TextEditingController(text: _orden.totalLista.toStringAsFixed(2));
    final telCtrl = TextEditingController(text: _orden.telefonoContacto ?? '');
    final respCtrl = TextEditingController(text: _orden.responsable ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title:
            const Text('Editar Datos', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: totalCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Total lista'),
            ),
            TextField(
              controller: telCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Teléfono'),
            ),
            TextField(
              controller: respCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Responsable'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final total = double.tryParse(totalCtrl.text.replaceAll(',', '.'));
    if (total == null || total <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Total inválido'), backgroundColor: Colors.red),
      );
      return;
    }
    final updated = await _service.updatePedidoFinancial(
      order: _orden,
      nuevoTotalLista: total,
      nuevoTelefono: telCtrl.text.trim(),
      nuevoResponsable: respCtrl.text.trim(),
    );
    if (!mounted) return;
    if (!updated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se pudo actualizar'),
            backgroundColor: Colors.red),
      );
      return;
    }
    setState(() {
      _orden = _orden.copyWith(
        meta: _orden.meta.copyWith(
          totalLista: total,
          telefono: telCtrl.text.trim(),
          responsable: respCtrl.text.trim(),
        ),
      );
    });
    widget.onActualizar();
  }

  Future<void> _eliminarPedido() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Eliminar pedido',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Esta acción marcará el pedido como CANCELADO. ¿Continuar?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    final deleted = await _service.eliminarPedido(_orden.id);
    if (!mounted) return;
    if (deleted) {
      setState(() {
        _orden = _orden.copyWith(estado: 'CANCELADO');
      });
      widget.onActualizar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido eliminado (CANCELADO)'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tienes permisos para eliminar'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
    }
  }

  Future<void> _llamarCliente() async {
    final tel = _orden.telefonoContacto?.trim();
    if (tel == null || tel.isEmpty) return;
    final uri = Uri.parse('tel:$tel');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _enviarWhatsApp() async {
    final tel = _orden.telefonoContacto?.trim();
    if (tel == null || tel.isEmpty) return;
    final msg = Uri.encodeComponent('Buenas tardes ${_orden.clienteNombre}, '
        'tu pedido está listo para recoger. Te esperamos hoy entre '
        '${DateFormat.Hm().format(_orden.fechaRecojo)} '
        'en la tienda. Gracias por tu compra.');
    final phone = tel.startsWith('+') ? tel : '+51$tel';
    final uri = Uri.parse('https://wa.me/$phone?text=$msg');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _marcarEntregado() async {
    final ok = await _service.updatePedidoFinancial(
      order: _orden,
      nuevoMontoPagado: _orden.totalLista,
    );
    if (!mounted) return;
    if (ok) {
      setState(() {
        _orden = _orden.copyWith(
          estado: 'ENTREGADO',
          montoAdelantado: _orden.totalLista,
        );
      });
    }
  }

  Future<void> _marcarPorCobrar() async {
    final okMonto = await _service.updatePedidoFinancial(
      order: _orden,
      nuevoMontoPagado: 0,
    );
    final okEstado = okMonto
        ? await _service.updatePedidoStatus(_orden.id, 'PENDIENTE')
        : false;
    if (!mounted) return;
    if (okMonto && okEstado) {
      setState(() {
        _orden = _orden.copyWith(
          estado: 'PENDIENTE',
          montoAdelantado: 0,
        );
      });
    }
  }

  Future<void> _capturarYSubirFoto() async {
    // ── [PATCH] Solicitar permiso de cámara antes de abrir el picker ──────────
    final permiso = await Permission.camera.request();
    final temporales = <File>[];
    String? imagenPath;

    if (!permiso.isGranted) {
      RegistroApp.warning(
        'Permiso de cámara denegado. Estado: $permiso',
        tag: 'CAMERA',
      );
      if (mounted) {
        final isPermanentlyDenied = permiso.isPermanentlyDenied;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPermanentlyDenied
                  ? '🚫 Permiso de cámara bloqueado. Ve a Ajustes > Aplicaciones > BiPenc > Permisos para habilitarlo.'
                  : '📷 Necesitamos acceso a la cámara para tomar la foto del pedido.',
            ),
            backgroundColor: Colors.orange.shade800,
            duration: Duration(seconds: isPermanentlyDenied ? 5 : 3),
            action: isPermanentlyDenied
                ? const SnackBarAction(
                    label: 'Abrir Ajustes',
                    textColor: Colors.white,
                    onPressed: openAppSettings,
                  )
                : null,
          ),
        );
      }
      return;
    }
    // ─────────────────────────────────────────────────────────────────────────

    try {
      RegistroApp.debug('Permiso concedido. Abriendo escáner de documentos...',
          tag: 'CAMERA');

      File? baseFile = await _photoService.capturarConEscaner();
      bool desdeScanner = baseFile != null;

      if (baseFile == null) {
        RegistroApp.debug('Escáner cancelado o falló, usando cámara estándar...',
            tag: 'CAMERA');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Escáner cancelado, usando cámara normal'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        final foto = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 92,
        );
        if (foto == null) {
          RegistroApp.debug('Usuario canceló captura de foto', tag: 'CAMERA');
          return;
        }
        baseFile = File(foto.path);
      }

      if (mounted) {
        setState(() {
          _isUploadingFoto = true;
          _progresoProcesamiento = 'Limpiando imagen...';
        });
      }

      final processed = await _photoService.procesarImagen(
        baseFile: baseFile,
        desdeScanner: desdeScanner,
        onProgreso: (etapa) {
          if (mounted) {
            setState(() => _progresoProcesamiento = etapa);
          }
        },
      );

      temporales.addAll(processed.temporales);
      imagenPath = processed.imagenFinal.path;
      final imagenFile = processed.imagenFinal;

      final fileSizeKb = imagenFile.lengthSync() / 1024;
      RegistroApp.debug(
          'Foto lista para upload: ${imagenFile.path} (${fileSizeKb.toStringAsFixed(2)} KB)',
          tag: 'CAMERA');

      // OCR on-device: sugerir productos antes de subir
      unawaited(_sugerirProductosDesdeOcr(imagenFile));

      if (mounted) setState(() => _progresoProcesamiento = 'Subiendo...');
      RegistroApp.debug('Iniciando upload de foto a Storage...', tag: 'CAMERA');
      final (success, fotoUrl) = await _service.uploadFotoAndUpdate(
        _orden.id,
        imagenFile,
      );

      if (mounted) {
        if (success) {
          RegistroApp.info('✅ Foto subida correctamente: $fotoUrl',
              tag: 'CAMERA');

          setState(() {
            _orden = _orden.copyWith(
              fotosUrls: [..._orden.fotosUrls, fotoUrl!],
            );
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Foto subida exitosamente'),
              backgroundColor: Colors.teal,
            ),
          );
          widget.onActualizar();
        } else {
          RegistroApp.error('❌ Upload falló - Service retornó false',
              tag: 'CAMERA');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al subir foto. Intenta de nuevo.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      RegistroApp.error(
        'Excepción en _capturarYSubirFoto: $e',
        tag: 'CAMERA',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error inesperado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingFoto = false);
      // Limpieza de temporales
      try {
        for (final f in temporales) {
          if (f.path == imagenPath) continue;
          if (await f.exists()) await f.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _sugerirProductosDesdeOcr(File imagenFile) async {
    try {
      List<String> lineas = await _ocrService.extraerLineas(imagenFile);

      // Si no detecta nada (fondo blanco/objeto claro), intenta con alto contraste.
      if (lineas.isEmpty) {
        final proc = ServicioProcesamientoImagen();
        final reforzada =
            await proc.mejorarContraste(imagenFile, contraste: 1.6, brillo: 14);
        if (reforzada != null) {
          lineas = await _ocrService.extraerLineas(reforzada);
          try {
            if (await reforzada.exists()) await reforzada.delete();
          } catch (_) {}
        }
      }

      if (lineas.isEmpty || !mounted) return;

      final Map<String, Producto> hallados = {};
      for (final linea in lineas.take(15)) {
        final res = await ServicioDbLocal.buscarLocal(linea);
        for (final p in res.take(2)) {
          hallados[p.id] = p;
        }
        if (hallados.length >= 10) break;
      }

      if (!mounted || hallados.isEmpty) return;

      final lista = hallados.values.toList();
      // Mostrar sugerencias rápidas en un bottom sheet compacto
      // (no se agrega nada automáticamente para evitar errores).
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.black87,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sugerencias OCR (local)',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...lista.take(6).map(
                      (p) => ListTile(
                        dense: true,
                        title: Text(p.nombre,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          [p.marca, p.skuCode]
                              .where((e) => e.isNotEmpty)
                              .join(' • '),
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ),
                    ),
                if (lista.length > 6)
                  Text(
                    '+${lista.length - 6} más…',
                    style: const TextStyle(color: Colors.white54),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      RegistroApp.error('OCR local falló: $e', tag: 'OCR');
    }
  }

  Future<void> _imprimirLista() async {
    if (_orden.fotosUrls.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay foto de lista para imprimir'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    if (_isPrinting) return;
    setState(() => _isPrinting = true);
    try {
      final ok =
          await ServicioImpresion().imprimirImagenLista(_orden.fotosUrls.first);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Lista enviada a la impresora'
              : 'No se pudo imprimir la lista'),
          backgroundColor: ok ? Colors.teal : Colors.orange,
        ),
      );
    } catch (e) {
      RegistroApp.error('Error imprimiendo lista: $e', tag: 'PRINT');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error imprimiendo: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isAdmin = ServicioSesion().rol == RolesApp.admin;

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: keyboardHeight + 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Encabezado
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _orden.clienteNombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${_orden.id}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getEstadoColor(_orden.estado),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _orden.estado,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Información
          _FilaInfo(
            icon: Icons.attach_money,
            label: 'Pagado / Total',
            value:
                'S/.${_orden.montoAdelantado.toStringAsFixed(2)} / S/.${_orden.totalLista.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 12),
          _FilaInfo(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Saldo Pendiente',
            value: 'S/.${_orden.saldoPendiente.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 12),
          _FilaInfo(
            icon: Icons.phone,
            label: 'Teléfono',
            value: _orden.telefonoContacto?.isNotEmpty == true
                ? _orden.telefonoContacto!
                : 'No registrado',
          ),
          const SizedBox(height: 12),
          _FilaInfo(
            icon: Icons.badge_outlined,
            label: 'Responsables',
            value: _orden.responsable?.isNotEmpty == true
                ? _orden.responsable!
                : 'Sin asignar',
          ),
          const SizedBox(height: 12),
          _FilaInfo(
            icon: Icons.inventory_2_outlined,
            label: 'Bultos',
            value: _orden.bultos > 0 ? '${_orden.bultos}' : 'No indicado',
          ),
          const SizedBox(height: 12),
          _FilaInfo(
            icon: Icons.child_friendly,
            label: 'Destinatario',
            value: _orden.meta.destinatario ?? 'No indicado',
          ),
          const SizedBox(height: 12),
          _FilaInfo(
            icon: Icons.calendar_today,
            label: 'Fecha de Recojo',
            value: DateFormat('dd/MM/yyyy HH:mm').format(_orden.fechaRecojo),
          ),
          const SizedBox(height: 24),

          // --- ACCIONES DE CONTACTO ---
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _orden.telefonoContacto?.isNotEmpty == true
                      ? _llamarCliente
                      : null,
                  icon: const Icon(Icons.call, size: 20),
                  label: const Text('Llamar'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _orden.telefonoContacto?.isNotEmpty == true
                      ? _enviarWhatsApp
                      : null,
                  icon: const Icon(Icons.chat_bubble_outline, size: 20),
                  label: const Text('WhatsApp'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // --- ACCIONES DE GESTIÓN Y DOCUMENTO ---
          Row(
            children: [
              Expanded(
                child: _AccionSecundaria(
                  icon: Icons.print_outlined,
                  label: 'Imprimir',
                  onTap: _orden.fotosUrls.isNotEmpty ? _imprimirLista : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AccionSecundaria(
                  icon: Icons.share_outlined,
                  label: 'Compartir',
                  onTap: _orden.fotosUrls.isNotEmpty 
                      ? () => Share.shareUri(Uri.parse(_orden.fotosUrls.first)) 
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AccionSecundaria(
                  icon: Icons.camera_alt_outlined,
                  label: 'Nueva Foto',
                  onTap: _capturarYSubirFoto,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // --- FLUJO DE TRABAJO (Wflow) ---
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _BotonWflow(
                    icon: Icons.pending_actions,
                    label: 'Por Cobrar',
                    onTap: _marcarPorCobrar,
                    active: _orden.estado == 'PENDIENTE',
                  ),
                ),
                Expanded(
                  child: _BotonWflow(
                    icon: Icons.check_circle_outline,
                    label: 'Entregado',
                    onTap: _marcarEntregado,
                    active: _orden.estado == 'ENTREGADO',
                    isPrimary: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // --- ACCIÓN CRÍTICA: PUNTO DE VENTA (POS) ---
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: () async {
                final router = GoRouter.of(context);
                await router.push('/pos', extra: {
                  'orderId': _orden.id,
                  'fotoUrl': _orden.fotosUrls.isNotEmpty
                      ? _orden.fotosUrls.first
                      : null,
                });
                widget.onActualizar();
              },
              icon: const Icon(Icons.point_of_sale, size: 24),
              label: const Text('PROCESAR EN CAJA (POS)', 
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.tealAccent.shade700,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // --- ACCIONES DE ABONO Y ADMIN ---
          Row(
            children: [
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _registrarAbono,
                  icon: const Icon(Icons.add_card),
                  label: const Text('Registrar Abono'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal.shade900.withValues(alpha: 0.5),
                    foregroundColor: Colors.tealAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: const BorderSide(color: Colors.teal, width: 0.5),
                  ),
                ),
              ),
              if (isAdmin) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    onPressed: _editarFinanzasYContacto,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Icon(Icons.edit_note),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    onPressed: _eliminarPedido,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent, width: 0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Icon(Icons.delete_forever_outlined),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 24),

          // Sección Fotos
          const Text(
            'Fotos de Lista de Papel',
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          if (_orden.fotosUrls.isEmpty)
            const Center(
              child: Column(
                children: [
                  Icon(Icons.image_not_supported,
                      size: 48, color: Colors.white30),
                  SizedBox(height: 12),
                  Text(
                    'Sin fotos aún',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _orden.fotosUrls.length,
              itemBuilder: (ctx, idx) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _orden.fotosUrls[idx],
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, progress) => progress == null
                      ? child
                      : const Center(
                          child: CircularProgressIndicator(color: Colors.teal),
                        ),
                  errorBuilder: (ctx, err, st) => Container(
                    color: Colors.grey.shade900,
                    child: const Icon(Icons.error, color: Colors.red),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Botón Capturar
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _isUploadingFoto ? null : _capturarYSubirFoto,
              icon: _isUploadingFoto
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.camera_alt),
              label: Text(_isUploadingFoto ? _progresoProcesamiento : 'Capturar Foto'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getEstadoColor(String estado) {
    switch (estado) {
      case 'PENDIENTE':
        return Colors.orange;
      case 'EN_PROCESO':
        return Colors.blue;
      case 'COMPLETADO':
        return Colors.green;
      case 'CANCELADO':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

// ── Helper Widget ──────────────────────────────────────────────────────────

// --- WIDGETS AUXILIARES DE UI DIAMOND ---

class _AccionSecundaria extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _AccionSecundaria({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: onTap == null ? 0.3 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
            color: Colors.white.withValues(alpha: 0.02),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: Colors.white70),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(color: Colors.white60, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonWflow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool isPrimary;

  const _BotonWflow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isPrimary ? Colors.tealAccent : Colors.orangeAccent;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(
            color: active ? color.withValues(alpha: 0.5) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? Icons.check_circle : icon,
              size: 18,
              color: active ? color : Colors.white24,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white24,
                fontSize: 13,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _FilaInfo({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.tealAccent),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ],
    );
  }
}
