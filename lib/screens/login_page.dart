import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/boton_biometrico.dart';
import '../services/supabase_service.dart';
import '../services/session_service.dart';
import '../utils/app_logger.dart';
import '../models/producto.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  PackageInfo? _packageInfo;
  final LocalAuthentication _auth = LocalAuthentication();
  bool _isAuthenticating = false;
  bool _hasSession = false;
  bool _isLoading = true;
  final FocusNode _pinFocusNode = FocusNode();

  // Variables para formulario de login/registro
  bool _isRegistering = false;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _apellidoCtrl = TextEditingController();
  bool _isProcessingForm = false;
  bool _showPass = false;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _checkSession();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _packageInfo = info);
  }

  Future<void> _checkSession() async {
    final session = Supabase.instance.client.auth.currentSession;
    setState(() {
      _hasSession = session != null;
      _isLoading = false;
    });

    if (_hasSession) {
      AppLogger.info('Sesión activa: ${session!.user.email}', tag: 'LOGIN');
      _authenticateBiometric();
    } else {
      AppLogger.debug('Sin sesión activa', tag: 'LOGIN');
      Future.microtask(() => _pinFocusNode.requestFocus());
    }
  }

  // ── Lógica Biométrica (Solo si hay sesión) ──
  Future<void> _authenticateBiometric() async {
    try {
      // Verificar disponibilidad antes de pedir
      final bool canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) {
        await _ingresarApp(); // Sin sensor → entrar directo
        return;
      }
      setState(() => _isAuthenticating = true);
      final authenticated = await _auth.authenticate(
        localizedReason: 'Identifícate para entrar a BiPenc',
        options: const AuthenticationOptions(biometricOnly: false),
      );
      setState(() => _isAuthenticating = false);
      if (authenticated && mounted) await _ingresarApp();
    } on PlatformException catch (e) {
      setState(() => _isAuthenticating = false);
      // Sensor no disponible / no configurado → entrar sin huella
      if (['NotAvailable', 'NotEnrolled', 'no_fragment_activity', 'MissingPluginException']
          .any((c) => e.code.contains(c))) {
        await _ingresarApp();
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error biométrico: ${e.message}')),
        );
      }
    } catch (_) {
      setState(() => _isAuthenticating = false);
      await _ingresarApp(); // Cualquier error → entrar sin huella
    }
  }

  // ── Lógica Auth Formulario ──
  Future<void> _submitForm() async {
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, completa email y contraseña')),
      );
      return;
    }

    if (_isRegistering) {
      if (_nombreCtrl.text.isEmpty || _apellidoCtrl.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Completa tu nombre y apellido')),
        );
        return;
      }
      if (_passCtrl.text != _confirmPassCtrl.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Las contraseñas no coinciden'), backgroundColor: Colors.orange),
        );
        return;
      }
      if (_passCtrl.text.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La contraseña debe tener al menos 6 caracteres')),
        );
        return;
      }
    }

    setState(() => _isProcessingForm = true);

    String? error;
    try {
      if (_isRegistering) {
        error = await SupabaseService.crearCuenta(
          _emailCtrl.text.trim(),
          _passCtrl.text.trim(),
          _nombreCtrl.text.trim(),
          _apellidoCtrl.text.trim(),
        );
      } else {
        final res = await SupabaseService.iniciarSesion(
          _emailCtrl.text.trim(),
          _passCtrl.text.trim(),
        );
        if (res == null) {
          error = 'Error inesperado en el inicio de sesión.';
        } else {
          _checkSession(); // Actualizar estado tras login exitoso
        }
      }
    } on AuthException catch (e) {
      error = e.message;
      AppLogger.error('Error Auth: ${e.message}', tag: 'LOGIN');
    } catch (e) {
      error = 'Error inesperado: $e';
      AppLogger.error('Error general', tag: 'LOGIN', error: e);
    }

    if (mounted) {
      setState(() => _isProcessingForm = false);
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
        );
      } else {
        // Éxito
        if (!_isRegistering) await _ingresarApp();
        else _checkSession();
      }
    }
  }

  /// Ingresa a la app usando GoRouter (compatible con el router configurado en main.dart)
  Future<void> _ingresarApp() async {
    if (mounted) context.go('/pos');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFF0A0A0A));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.white10,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/logo/logo.png',
                        height: 120,
                        width: 120,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'BiPenc',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4,
                          color: Colors.tealAccent,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sistema de Ventas',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: 48),

                  if (_hasSession) ...[
                    // MODO BIOMÉTRICO (Usuario ya logueado)
                    BotonBiometrico(
                      onTap: _authenticateBiometric,
                      isLoading: _isAuthenticating,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Toca para ingresar',
                      style: TextStyle(color: Colors.tealAccent.withOpacity(0.8)),
                    ),
                    const SizedBox(height: 32),
                    TextButton(
                      onPressed: () async {
                        SessionService().limpiarSesion();
                        await Supabase.instance.client.auth.signOut();
                        _checkSession();
                      },
                      child: const Text('Cerrar Sesión', style: TextStyle(color: Colors.grey)),
                    )
                  ] else ...[
                    // MODO LOGIN / REGISTRO
                    Container(
                      constraints: const BoxConstraints(maxWidth: 400),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2C),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade800),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _isRegistering ? 'Crear Cuenta' : 'Iniciar Sesión',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          if (_isRegistering) ...[
                            _buildInput(_nombreCtrl, 'Nombre', Icons.person),
                            const SizedBox(height: 12),
                            _buildInput(_apellidoCtrl, 'Apellido', Icons.person_outline),
                            const SizedBox(height: 12),
                          ],
                          _buildInput(_emailCtrl, 'Email', Icons.email, type: TextInputType.emailAddress),
                          const SizedBox(height: 12),
                          _buildInput(
                            _passCtrl, 
                            'Contraseña / PIN', 
                            Icons.lock, 
                            obscure: !_showPass,
                            type: TextInputType.number,
                            focusNode: _pinFocusNode,
                            suffix: IconButton(
                              icon: Icon(_showPass ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                              onPressed: () => setState(() => _showPass = !_showPass),
                            ),
                          ),
                          if (_isRegistering) ...[
                            const SizedBox(height: 12),
                            _buildInput(
                              _confirmPassCtrl, 
                              'Confirmar Contraseña', 
                              Icons.lock_outline, 
                              obscure: !_showPass,
                            ),
                          ],
                          const SizedBox(height: 24),
                          
                          FilledButton(
                            onPressed: _isProcessingForm ? null : _submitForm,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.tealAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: _isProcessingForm 
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                                : Text(_isRegistering ? 'Registrarse' : 'Ingresar'),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () => setState(() => _isRegistering = !_isRegistering),
                            child: Text(
                              _isRegistering 
                                  ? '¿Ya tienes cuenta? Inicia Sesión' 
                                  : '¿Eres nuevo? Regístrate aquí',
                              style: const TextStyle(color: Colors.tealAccent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          // Version footer
          if (_packageInfo != null)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'v${_packageInfo!.version}+${_packageInfo!.buildNumber} | BiPenc Official',
                  style: TextStyle(
                      color: Colors.grey.shade700, fontSize: 11, letterSpacing: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInput(TextEditingController ctrl, String label, IconData icon, 
      {bool obscure = false, TextInputType? type, Widget? suffix, FocusNode? focusNode}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: type,
      focusNode: focusNode,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey),
        suffixIcon: suffix,
        labelStyle: const TextStyle(color: Colors.grey),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade700),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.tealAccent),
        ),
        filled: true,
        fillColor: Colors.black12,
      ),
    );
  }
}
