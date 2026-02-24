import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Esquema de colores profesional basado en Material Design 3
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: Colors.teal),
            onPressed: () => context.push('/cierre_caja'),
            tooltip: 'Auditoría y Cierre Z',
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.grey),
            onPressed: () => context.push('/settings'),
            tooltip: 'Configuración del Negocio',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            // Logo Central
            Center(
              child: Image.asset(
                'assets/logo/logo_bipenc.png',
                width: 180,
                height: 180,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => 
                    const Icon(Icons.inventory_2, size: 100, color: Colors.teal),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'BiPenc',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            Text(
              'Sistema de Inventario & POS',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(flex: 2),
            
            // Botones de Acción
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.push('/pos'),
                    icon: const Icon(Icons.point_of_sale, size: 28),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Text('Nueva Venta', style: TextStyle(fontSize: 18)),
                    ),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/inventario'),
                    icon: const Icon(Icons.inventory, size: 28),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Text('Inventario', style: TextStyle(fontSize: 18)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colorScheme.primary, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const Spacer(flex: 1),
            // Footer - Indicador de Autoría
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                'v1.0.0 • Desarrollado por Jhonatan',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Modo Debug: Recolector de Basura (Imágenes) activo mediante try-finally en producto_form. Tickets cargados dinámicamente desde SharedPreferences.'),
              backgroundColor: Colors.deepPurple,
              duration: Duration(seconds: 4),
            ));
        },
        backgroundColor: Colors.deepPurple.withValues(alpha: 0.8),
        mini: true,
        tooltip: 'Modo Debug (QA)',
        child: const Icon(Icons.bug_report, color: Colors.white),
      ),
    );
  }
}
