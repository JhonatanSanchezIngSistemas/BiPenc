class FiscalPair {
  final double $1;
  final double $2;
  FiscalPair(this.$1, this.$2);
}

class FiscalUtils {
  /// Calcula desglose base/igv a partir del total asumido incluido IGV.
  /// Por compatibilidad con código existente devuelve un objeto con campos $1 (base) y $2 (igv).
  static FiscalPair calcularDesglose(double total, {double tasa = 0.18}) {
    final base = total / (1 + tasa);
    final igv = total - base;
    return FiscalPair(base, igv);
  }
}
