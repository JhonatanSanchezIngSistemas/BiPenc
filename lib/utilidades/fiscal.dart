class ParFiscal {
  final double $1;
  final double $2;
  ParFiscal(this.$1, this.$2);
}

class UtilFiscal {
  static double _round2(num v) => (v * 100).round() / 100;

  /// Calcula desglose base/igv a partir del total asumido incluido IGV.
  /// Por compatibilidad con código existente devuelve un objeto con campos $1 (base) y $2 (igv).
  static ParFiscal calcularDesglose(double total, {double tasa = 0.18}) {
    final base = _round2(total / (1 + tasa));
    final igv = _round2(total - base);
    return ParFiscal(base, igv);
  }
}
