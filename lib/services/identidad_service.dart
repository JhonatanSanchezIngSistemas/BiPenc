import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

const String _apiToken = 'YOUR_API_TOKEN_HERE';

class IdentidadService {

  /// Verifica conectividad real (no solo Wi-Fi asociado).
  Future<bool> _hasInternetAccess() async {
    final result = await Connectivity().checkConnectivity();
    if (result.contains(ConnectivityResult.none)) return false;
    try {
      final lookup = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Consulta DNI o RUC con timeout de 6 segundos.
  /// Retorna:
  ///   - El nombre/razón social si tiene éxito
  ///   - 'OFFLINE'  si no hay internet → muestra campo manual
  ///   - 'ERROR'    si la API falla o el documento no existe
  Future<String?> consultarDocumento(String documento, bool esRuc) async {
    final hasInternet = await _hasInternetAccess();
    if (!hasInternet) return 'OFFLINE';

    try {
      final url = esRuc
          ? Uri.parse('https://api.apis.net.pe/v2/sunat/ruc?numero=$documento')
          : Uri.parse('https://api.apis.net.pe/v2/reniec/dni?numero=$documento');

      final response = await http
          .get(url, headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $_apiToken',
          })
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (esRuc) {
          return data['razonSocial'] as String?;
        } else {
          final n = data['nombres'] ?? '';
          final ap = data['apellidoPaterno'] ?? '';
          final am = data['apellidoMaterno'] ?? '';
          return '$n $ap $am'.trim();
        }
      }
      return 'ERROR';
    } catch (_) {
      return 'OFFLINE'; // Timeout o cualquier excepción de red → trato como offline
    }
  }
}
