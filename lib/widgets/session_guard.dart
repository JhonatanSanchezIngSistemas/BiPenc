import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session_manager.dart';

/// Constitución BiPenc — Artículo 1
/// Widget que envuelve la app y muestra una pantalla de bloqueo 
/// si SessionManager detecta inactividad > 15 min.
class SessionGuard extends StatelessWidget {
  final Widget child;

  const SessionGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionManager>(
      builder: (context, session, _) {
        if (session.bloqueado) {
          return _LockScreen(session: session);
        }
        return Listener(
          onPointerDown: (_) {
            if (!session.bloqueado) session.registrarActividad();
          },
          behavior: HitTestBehavior.translucent,
          child: child,
        );
      },
    );
  }
}

class _LockScreen extends StatefulWidget {
  final SessionManager session;
  const _LockScreen({required this.session});

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  bool _unlocking = false;

  Future<void> _onUnlockPressed() async {
    if (_unlocking) return;
    setState(() => _unlocking = true);
    final ok = await widget.session.desbloquear();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Autenticación fallida')),
      );
    }
    if (mounted) setState(() => _unlocking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 80, color: Colors.teal),
            const SizedBox(height: 24),
            const Text(
              'BiPenc Protegido',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Bloqueado por inactividad',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: 200,
              height: 50,
              child: FilledButton.icon(
                onPressed: _unlocking ? null : _onUnlockPressed,
                icon: Icon(widget.session.biometricoDisponible ? Icons.fingerprint : Icons.lock_open),
                label: Text(_unlocking
                    ? 'VERIFICANDO...'
                    : (widget.session.biometricoDisponible ? 'USAR HUELLA' : 'DESBLOQUEAR')),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
