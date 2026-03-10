class PrecioEngine {
  /// Redondea al superior más cercano (monedas de 10 céntimos).
  static double ceilingTotal(double total) {
    return (total * 10).ceilToDouble() / 10.0;
  }
}
