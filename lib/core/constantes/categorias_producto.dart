/// Constantes y configuración de categorías de productos para BiPenc
class CategoriasProducto {
  // Lista por defecto si no hay categorías en Supabase
  static const List<String> lista = [
    'Escritura',
    'Escolar',
    'Papelería',
    'Oficina',
    'Arte y Manualidades',
    'Importados',
  ];

  // Colores asociados a categorías (para futuros usos)
  static const Map<String, int> coloresCategoria = {
    'Escritura': 0xFF2196F3,      // Azul
    'Escolar': 0xFF4CAF50,         // Verde
    'Papelería': 0xFFFFC107,       // Amarillo
    'Oficina': 0xFF9C27B0,         // Púrpura
    'Arte y Manualidades': 0xFFFF5722,  // Naranja
    'Importados': 0xFF00BCD4,      // Cian
  };

  // Descripciones de categorías
  static const Map<String, String> descripcionesCategoria = {
    'Escritura': 'Bolígrafos, lápices, marcadores',
    'Escolar': 'Cuadernos, libretas, papelería escolar',
    'Papelería': 'Papel, sobres, papel de regalo',
    'Oficina': 'Articulos para oficina y negocio',
    'Arte y Manualidades': 'Materiales artísticos y manualidades',
    'Importados': 'Productos importados y especiales',
  };
}
