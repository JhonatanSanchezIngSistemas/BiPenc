import 'package:flutter/material.dart';

/// Botón circular con efecto de halo luminoso (glow) en color Teal.
/// Usado en la pantalla de login para activar la autenticación biométrica.
class BotonBiometrico extends StatefulWidget {
  final VoidCallback onTap;
  final bool isLoading;

  const BotonBiometrico({
    super.key,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  State<BotonBiometrico> createState() => _BotonBiometricoState();
}

class _BotonBiometricoState extends State<BotonBiometrico>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 8.0, end: 28.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return GestureDetector(
          onTap: widget.isLoading ? null : widget.onTap,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A1A2E),
              border: Border.all(
                color: Colors.tealAccent.withValues(alpha: 0.6),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.tealAccent.withValues(alpha: 0.4),
                  blurRadius: _glowAnimation.value,
                  spreadRadius: _glowAnimation.value * 0.3,
                ),
                BoxShadow(
                  color: Colors.teal.withValues(alpha: 0.2),
                  blurRadius: _glowAnimation.value * 2,
                  spreadRadius: _glowAnimation.value * 0.5,
                ),
              ],
            ),
            child: Center(
              child: widget.isLoading
                  ? const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        color: Colors.tealAccent,
                        strokeWidth: 3,
                      ),
                    )
                  : const Icon(
                      Icons.fingerprint,
                      size: 64,
                      color: Colors.tealAccent,
                    ),
            ),
          ),
        );
      },
    );
  }
}
