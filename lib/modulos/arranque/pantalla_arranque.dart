import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PantallaArranque extends StatefulWidget {
  const PantallaArranque({super.key});

  @override
  State<PantallaArranque> createState() => _PantallaArranqueState();
}

class _PantallaArranqueState extends State<PantallaArranque> {
  @override
  void initState() {
    super.initState();
    // Breve delay para mostrar logo mientras se cargan servicios.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      context.go('/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B132B),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 160,
              height: 160,
              child: Image.asset('assets/logo/logo.png', fit: BoxFit.contain),
            ),
            const SizedBox(height: 24),
            const Text(
              'BiPenc POS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.tealAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
