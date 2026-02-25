import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Indicador de conexión discreto para el AppBar.
/// Constitución BiPenc — Artículo 1.3: "Un indicador discreto siempre visible en la barra superior."
class ConectividadIndicador extends StatefulWidget {
  const ConectividadIndicador({super.key});

  @override
  State<ConectividadIndicador> createState() => _ConectividadIndicadorState();
}

class _ConectividadIndicadorState extends State<ConectividadIndicador> {
  bool _isSupabaseReachable = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    // Verificamos cada 15 segundos para no saturar pero mantener info fresca
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _checkStatus());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    bool reachable = false;
    try {
      // Intento de ping ligero a Supabase
      final response = await Supabase.instance.client
          .from('productos')
          .select('sku')
          .limit(1)
          .timeout(const Duration(seconds: 5));
      reachable = true;
    } catch (_) {
      reachable = false;
    }
    if (mounted) {
      setState(() => _isSupabaseReachable = reachable);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _isSupabaseReachable 
          ? 'Conectado a la Nube (Supabase) ✅' 
          : 'Modo Offline — Sin conexión a la Nube 🔴',
      child: Container(
        width: 12,
        height: 12,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isSupabaseReachable ? Colors.greenAccent : Colors.redAccent,
          boxShadow: [
            BoxShadow(
              color: (_isSupabaseReachable ? Colors.greenAccent : Colors.redAccent)
                  .withOpacity(0.6),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}
