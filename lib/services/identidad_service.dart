import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

// Token simulado o real de API de consultas (Ej. APISPeru o Migo)
const String _apiToken = 'YOUR_API_TOKEN_HERE'; 

class IdentidadService {

  /// Verifica si el dispositivo cuenta con acceso real a Internet, no solo conexión WiFi.
  Future<bool> _hasInternetAccess() async {
    final connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) return false;
    
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  /// Consulta el nombre de la persona (DNI) o Razón Social (RUC) usando API pública.
  /// Si no hay internet, retorna 'Off-line' para permitir el ingreso manual.
  Future<String?> consultarDocumento(String documento, bool esRuc) async {
    final hasInternet = await _hasInternetAccess();
    if (!hasInternet) return 'OFFLINE';

    try {
      final url = esRuc 
        ? Uri.parse('https://api.apis.net.pe/v2/sunat/ruc?numero=\$documento')
        : Uri.parse('https://api.apis.net.pe/v2/reniec/dni?numero=\$documento');

      final response = await http.get(url, headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer \$_apiToken'
      }).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (esRuc) {
          return data['razonSocial'];
        } else {
          return '\${data['nombres']} \${data['apellidoPaterno']} \${data['apellidoMaterno']}';
        }
      }
      return null; // Documento no encontrado o error de API
    } catch (e) {
      return 'ERROR';
    }
  }
}
