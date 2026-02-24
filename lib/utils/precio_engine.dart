/// Motor de precios BIPENC con:
/// - Categorización triple: Económico / Intermedio / Premium
/// - Umbrales de volumen por SKU (escala automática de precios)
/// - Redondeo ceiling Pro-Empresa: (total * 10).ceil() / 10
library;
import 'dart:convert';
import '../models/producto.dart' as model;

// ──────────────────────────────────────────────
// Categorías de producto
// ──────────────────────────────────────────────

enum CategoriaTier {
  economico,   // Genérico, marcas blancas, chamaquito
  intermedio,  // Marcas conocidas de gama media
  premium,     // Stanford, Play-Doh, Faber-Castell
}

extension CategoriaTierLabel on CategoriaTier {
  String get label {
    switch (this) {
      case CategoriaTier.economico:  return 'Económico';
      case CategoriaTier.intermedio: return 'Intermedio';
      case CategoriaTier.premium:    return 'Premium';
    }
  }

  // Color asociado para la UI
  String get hexColor {
    switch (this) {
      case CategoriaTier.economico:  return '#78909C'; // gris-azul
      case CategoriaTier.intermedio: return '#FFA726'; // naranja
      case CategoriaTier.premium:    return '#AB47BC'; // violeta
    }
  }
}

// ──────────────────────────────────────────────
// Catálogo de umbrales por SKU
// ──────────────────────────────────────────────

class PrecioEngine {

  /// Umbrales configurables por SKU.
  /// Cada entrada define: cantidad mínima, máxima, precio unitario, nombre presentación.
  static const Map<String, List<EscalaPrecio>> umbrales = {

    // ── Hojas Bond A4 (Chamaquito - Económico) ──
    'BOND_A4_CHAMAQUITO': [
      EscalaPrecio(nombre: 'Unidad',      minCantidad: 1,   maxCantidad: 24,  precioUnitario: 0.10),
      EscalaPrecio(nombre: '1/4 Ciento',  minCantidad: 25,  maxCantidad: 99,  precioUnitario: 0.06),
      EscalaPrecio(nombre: 'Resma 500',   minCantidad: 100, maxCantidad: 9999, precioUnitario: 0.024),
    ],

    // ── Lapiceros Estándar ──
    'LAPICERO_STD': [
      EscalaPrecio(nombre: 'Unidad',  minCantidad: 1,   maxCantidad: 11,  precioUnitario: 0.50),
      EscalaPrecio(nombre: 'Docena',  minCantidad: 12,  maxCantidad: 99,  precioUnitario: 0.42),
      EscalaPrecio(nombre: 'Ciento',  minCantidad: 100, maxCantidad: 9999, precioUnitario: 0.38),
    ],

    // ── Lapiceros Stanford (Premium) ──
    'LAPICERO_STANFORD': [
      EscalaPrecio(nombre: 'Unidad',  minCantidad: 1,  maxCantidad: 11,  precioUnitario: 1.20),
      EscalaPrecio(nombre: 'Docena',  minCantidad: 12, maxCantidad: 99,  precioUnitario: 1.00),
      EscalaPrecio(nombre: 'Ciento',  minCantidad: 100, maxCantidad: 9999, precioUnitario: 0.90),
    ],

    // ── Plastilina Play-Doh (Premium) ──
    'PLASTILINA_PLAYDOH': [
      EscalaPrecio(nombre: 'Unidad',  minCantidad: 1, maxCantidad: 9999, precioUnitario: 18.50),
    ],

    // ── Plastilina Jumbo (Económica) ──
    'PLASTILINA_JUMBO': [
      EscalaPrecio(nombre: 'Unidad',  minCantidad: 1, maxCantidad: 9999, precioUnitario: 4.50),
    ],

    // ── Colores Faber-Castell (Premium) ──
    'COLORES_FABER': [
      EscalaPrecio(nombre: 'Caja 12', minCantidad: 1, maxCantidad: 9999, precioUnitario: 12.00),
    ],

    // ── Default: sin reglas especiales ──
    '_DEFAULT': [
      EscalaPrecio(nombre: 'Unidad', minCantidad: 1, maxCantidad: 9999, precioUnitario: 0.0),
    ],
  };

  // ──────────────────────────────────────────────
  // Catálogo de tiers por marca
  // ──────────────────────────────────────────────

  static const Map<String, CategoriaTier> tierPorMarca = {
    'Stanford':       CategoriaTier.premium,
    'Faber-Castell':  CategoriaTier.premium,
    'Play-Doh':       CategoriaTier.premium,
    'Maped':          CategoriaTier.intermedio,
    'Artesco':        CategoriaTier.intermedio,
    'Chamaquito':     CategoriaTier.economico,
    'Genérico':       CategoriaTier.economico,
  };

  static CategoriaTier getTier(String marca) =>
      tierPorMarca[marca] ?? CategoriaTier.economico;

  // ──────────────────────────────────────────────
  // Cálculo de precio con umbrales
  // ──────────────────────────────────────────────

  /// Retorna el precio unitario y presentación para el SKU y cantidad dados.
  static ResultadoPrecio calcularPrecio({
    required String sku,
    required int cantidad,
    required double precioBase,
  }) {
    final reglas = umbrales[sku] ?? umbrales['_DEFAULT']!;

    EscalaPrecio? matched;
    for (final p in reglas) {
      if (cantidad >= p.minCantidad && cantidad <= p.maxCantidad) {
        matched = p;
        break;
      }
    }

    final precioUnit = (matched?.precioUnitario ?? 0) > 0
        ? matched!.precioUnitario
        : precioBase;

    return ResultadoPrecio(
      precioUnitario: precioUnit,
      presentacion: matched?.nombre ?? 'Unidad',
      subtotal: precioUnit * cantidad,
    );
  }

  /// Lista de presentaciones disponibles para mostrar como burbujas en UI.
  static List<EscalaPrecio> getPresentaciones(String sku) =>
      umbrales[sku] ?? umbrales['_DEFAULT']!;

  // ──────────────────────────────────────────────
  // Redondeo Ceiling Pro-Empresa
  // Fórmula oficial: (total * 10).ceil() / 10
  // ──────────────────────────────────────────────

  static double ceilingTotal(double total) {
    return (total * 10).ceilToDouble() / 10;
  }

  static double ahorroRedondeo(double original, double redondeado) =>
      (redondeado - original).clamp(0.0, double.infinity);

  // ──────────────────────────────────────────────
  // Lógica Fiscal (Gross-Up)
  // Fórmula: Subtotal = Total / 1.18, IGV = Total - Subtotal
  // ──────────────────────────────────────────────

  static DesgloseFiscal calcularDesgloseFiscal(double total) {
    final subtotal = total / 1.18;
    final igv = total - subtotal;
    return DesgloseFiscal(
      subtotal: subtotal,
      igv: igv,
      total: total,
    );
  }

  // ──────────────────────────────────────────────
  // Validación de cantidades
  // ──────────────────────────────────────────────

  /// Retorna null si la cantidad es válida, o un mensaje de sugerencia.
  static String? validarCantidad(String sku, int cantidad) {
    final reglas = umbrales[sku];
    if (reglas == null) return null;

    for (final p in reglas) {
      if (cantidad >= p.minCantidad && cantidad <= p.maxCantidad) return null;
    }

    final mayor = reglas.last;
    if (cantidad > mayor.maxCantidad) {
      return 'Máximo ${mayor.maxCantidad} por ${mayor.nombre}';
    }
    return null;
  }
}

// ──────────────────────────────────────────────
// Modelos auxiliares
// ──────────────────────────────────────────────

class EscalaPrecio {
  final String nombre;
  final int minCantidad;
  final int maxCantidad;
  final double precioUnitario;

  const EscalaPrecio({
    required this.nombre,
    required this.minCantidad,
    required this.maxCantidad,
    required this.precioUnitario,
  });
}

class ResultadoPrecio {
  final double precioUnitario;
  final String presentacion;
  final double subtotal;

  const ResultadoPrecio({
    required this.precioUnitario,
    required this.presentacion,
    required this.subtotal,
  });
}

class DesgloseFiscal {
  final double subtotal;
  final double igv;
  final double total;

  const DesgloseFiscal({
    required this.subtotal,
    required this.igv,
    required this.total,
  });
}
