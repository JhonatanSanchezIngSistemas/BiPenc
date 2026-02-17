import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../widgets/boton_biometrico.dart';

/// Pantalla de login con autenticación biométrica y PIN de respaldo.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _isAuthenticating = false;

  // ── Autenticación biométrica ──
  Future<void> _authenticateBiometric() async {
    try {
      setState(() => _isAuthenticating = true);
      final authenticated = await _auth.authenticate(
        localizedReason: 'Identifícate para entrar a BiPenc',
      );
      setState(() => _isAuthenticating = false);

      if (authenticated && mounted) {
        Navigator.pushReplacementNamed(context, '/venta');
      }
    } on PlatformException catch (e) {
      setState(() => _isAuthenticating = false);
      if (!mounted) return;
      debugPrint('Auth error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.message ?? "Autenticación fallida"}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ── Autenticación por PIN ──
  void _authenticatePin() {
    final pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: const Text('Ingresar con PIN',
            style: TextStyle(color: Colors.tealAccent)),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            letterSpacing: 12,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '• • • •',
            hintStyle: TextStyle(color: Colors.grey.shade700, fontSize: 28),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.tealAccent),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade700),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.tealAccent, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            onPressed: () {
              // PIN de demostración: 1234
              if (pinController.text == '1234') {
                Navigator.pop(ctx);
                Navigator.pushReplacementNamed(context, '/venta');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('PIN incorrecto'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.tealAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Ingresar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo / Título
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
              const SizedBox(height: 64),

              // Botón biométrico con halo
              BotonBiometrico(
                onTap: _authenticateBiometric,
                isLoading: _isAuthenticating,
              ),
              const SizedBox(height: 16),
              Text(
                'Acceso Biométrico',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.tealAccent.withValues(alpha: 0.8),
                    ),
              ),

              const SizedBox(height: 48),

              // Separador
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade800)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('o',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade800)),
                ],
              ),

              const SizedBox(height: 24),

              // Botón PIN
              OutlinedButton.icon(
                onPressed: _authenticatePin,
                icon: const Icon(Icons.pin_outlined, size: 20),
                label: const Text('Ingresar con PIN'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade400,
                  side: BorderSide(color: Colors.grey.shade700),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
