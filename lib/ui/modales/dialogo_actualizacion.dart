import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import '../../servicios/servicio_actualizacion.dart';

class DialogoActualizacion extends StatefulWidget {
  final Map<String, dynamic> versionData;

  const DialogoActualizacion({super.key, required this.versionData});

  @override
  State<DialogoActualizacion> createState() => _DialogoActualizacionState();
}

class _DialogoActualizacionState extends State<DialogoActualizacion> {
  final ServicioActualizacion _updateService = ServicioActualizacion();
  double _progress = 0;
  String _status = "Preparando descarga...";
  bool _isDownloading = false;
  late final ValidacionActualizacion _validation;

  @override
  void initState() {
    super.initState();
    _validation = _updateService.validateUpdate(widget.versionData);
  }

  Future<void> _startDownload() async {
    if (!_updateService.otaEnabled) {
      setState(() {
        _status = "Actualizaciones OTA deshabilitadas";
      });
      return;
    }
    if (_updateService.strictVerification && !_validation.isValid) {
      setState(() {
        _status = _validation.errors.join(' | ');
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _status = "Preparando descarga...";
      _progress = 0;
    });

    try {
      if (_updateService.strictVerification &&
          _validation.uri != null &&
          _validation.sha256 != null) {
        setState(() {
          _status = "Descargando y verificando APK...";
        });

        final file = await _updateService.downloadAndVerifyApk(
          uri: _validation.uri!,
          expectedSha256: _validation.sha256!,
          onProgress: (p) {
            setState(() {
              _progress = (p * 100).clamp(0, 100);
            });
          },
        );

        setState(() {
          _status = "APK verificado. Iniciando instalador...";
          _progress = 100;
        });

        _updateService.installLocalApk(file).listen(
          (OtaEvent event) {
            setState(() {
              switch (event.status) {
                case OtaStatus.INSTALLING:
                  _status = "Iniciando instalador...";
                  break;
                case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                  _status = "Permiso denegado para instalar";
                  break;
                case OtaStatus.INTERNAL_ERROR:
                  _status = "Error interno del sistema";
                  break;
                default:
                  _status = "Instalación en progreso";
              }
            });
          },
          onError: (e) {
            setState(() {
              _status = "Error instalando APK: $e";
            });
          },
        );
      } else {
        _updateService.downloadAndInstall(widget.versionData['url_apk']).listen(
          (OtaEvent event) {
            setState(() {
              switch (event.status) {
                case OtaStatus.DOWNLOADING:
                  _status = "Descargando actualización...";
                  _progress = double.tryParse(event.value!) ?? 0;
                  break;
                case OtaStatus.INSTALLING:
                  _status = "Iniciando instalador...";
                  break;
                case OtaStatus.ALREADY_RUNNING_ERROR:
                  _status = "Ya hay una descarga en curso";
                  break;
                case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                  _status = "Permiso denegado para instalar";
                  break;
                case OtaStatus.INTERNAL_ERROR:
                  _status = "Error interno del sistema";
                  break;
                default:
                  _status = "Error desconocido";
              }
            });
          },
          onError: (e) {
            setState(() {
              _status = "Error en la descarga: $e";
            });
          },
        );
      }
    } catch (e) {
      setState(() {
        _status = "Error al iniciar: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isObligatory = widget.versionData['es_obligatoria'] ?? false;
    final hasErrors = !_validation.isValid;

    return PopScope(
      canPop: !isObligatory && !_isDownloading,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.system_update, color: Colors.blueAccent),
            SizedBox(width: 10),
            Expanded(child: Text("Nueva mejora para BiPenc")),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Versión: ${widget.versionData['version_code']}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(widget.versionData['cambios'] ?? "Mejoras de rendimiento y corrección de errores."),
            if (hasErrors) ...[
              const SizedBox(height: 10),
              Text(
                "Verificación OTA fallida: ${_validation.errors.join(' | ')}",
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ] else if (_validation.warnings.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                "Advertencias: ${_validation.warnings.join(' | ')}",
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ],
            if (_isDownloading) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: _progress / 100,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
              ),
              const SizedBox(height: 10),
              Center(child: Text("$_status (${_progress.toInt()}%)")),
            ]
          ],
        ),
        actions: _isDownloading
            ? []
            : [
                if (!isObligatory)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("MÁS TARDE"),
                  ),
                ElevatedButton(
                  onPressed: (hasErrors && _updateService.strictVerification)
                      ? null
                      : _startDownload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("ACTUALIZAR AHORA"),
                ),
              ],
      ),
    );
  }
}
