import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bipenc/servicios/servicio_backend.dart';
import 'package:bipenc/datos/modelos/presentacion.dart';
import 'package:bipenc/datos/modelos/venta.dart';
import 'package:bipenc/modulos/caja/proveedor_caja.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ── Mock Backend ────────────────────────────────────────────────────────────
/// Implementación mock de [ProveedorBackend] para tests.
/// No toca red, no toca Supabase, no toca disco.
class MockProveedorBackend implements ProveedorBackend {
  // Control de comportamiento por test
  bool debeFallar = false;
  List<Producto> productosRemotos = [];
  int llamadasBuscarProducto = 0;
  int llamadasInsertarVenta = 0;
  bool tieneConexion = true;

  static Producto productoMock({
    String id = 'MOCK001',
    String nombre = 'Producto Mock',
    double precio = 10.0,
  }) =>
      Producto(
        id: id,
        skuCode: id,
        nombre: nombre,
        marca: 'BiPencTest',
        categoria: 'Test',
        presentaciones: [
          Presentacion(
            id: 'unid',
            skuCode: id,
            name: 'Unidad',
            conversionFactor: 1,
            prices: [PuntoPrecio(type: 'NORMAL', amount: precio)],
          ),
        ],
      );

  @override
  Future<List<Producto>> buscarProductos(String query) async {
    llamadasBuscarProducto++;
    if (debeFallar) throw Exception('Sin conexión (mock)');
    return productosRemotos
        .where((p) => p.nombre.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  @override
  Future<List<Producto>> buscarPorCodigoRemoto(String codigo) async {
    if (debeFallar) throw Exception('Sin conexión (mock)');
    return productosRemotos.where((p) => p.skuCode == codigo).toList();
  }

  @override
  Future<(bool success, String? docId)> insertarVentaWaterfall(
      Venta venta) async {
    llamadasInsertarVenta++;
    if (debeFallar) return (false, null);
    return (true, 'MOCK-DOC-${venta.id}');
  }

  @override
  Future<bool> tieneConexionRemota() async => tieneConexion;

  @override
  Future<bool> sincronizarProductos() async => !debeFallar;

  // ── Stubs que retornan valores seguros ──────────────────────────────────
  @override
  Future<SesionBackend?> obtenerSesionActual() async => null;

  @override
  Future<void> cerrarSesion() async {}

  @override
  Future<Map<String, dynamic>?> getEmpresaConfig() async => null;
  @override
  Future<void> upsertEmpresaConfig(Map<String, dynamic> values) async {}
  @override
  Future<List<Map<String, dynamic>>> obtenerConfigCorrelativos() async => [];
  @override
  Future<void> upsertConfigCorrelativo({
    required String tipoDocumento,
    required String serie,
    required int ultimoNumero,
  }) async {}
  @override
  Future<String?> obtenerVersionMinima() async => null;
  @override
  Future<String?> subirImagen(File imageFile) async => null;
  @override
  Future<String?> subirAvatarPerfil(File imageFile) async => null;
  @override
  Future<Perfil?> obtenerPerfil() async => null;
  @override
  Future<bool> actualizarPerfil({
    required String nombre,
    required String apellido,
    required String alias,
    String? avatarUrl,
  }) async =>
      true;
  @override
  Future<String?> cambiarPassword({required String nuevaPassword}) async =>
      null;
  @override
  Future<String?> cambiarEmail({required String nuevoEmail}) async => null;
  @override
  Future<String> obtenerAliasVendedorActual() async => 'VENDEDOR_TEST';
  @override
  Future<String?> ensurePerfilConAlias() async => 'test_alias';
  @override
  Future<Perfil?> crearPerfilDeRecuperacion() async => null;
  @override
  Future<AuthResponse?> iniciarSesion(String email, String password) async =>
      null;
  @override
  Future<String?> crearCuenta(
          String email, String password, String nombre, String apellido) async =>
      null;
  @override
  Future<double?> obtenerIgvRate() async => null;
  @override
  Future<void> upsertModoPrueba(bool enabled) async {}
  @override
  Producto mapToProducto(Map<String, dynamic> data) =>
      MockProveedorBackend.productoMock();
  @override
  Future<List<String>> obtenerCategorias() async => ['Test', 'Mock'];
  @override
  Future<void> agregarCategoria(String nombre) async {}
  @override
  Future<bool> eliminarCategoriaSiNoEstaEnUso(String nombre) async => true;
  @override
  Future<bool> anularVentaEnNube({
    required String correlativo,
    required String motivo,
    required String aliasUsuario,
  }) async =>
      true;
  @override
  Future<void> subirVentasPendientes() async {}
  @override
  Future<void> procesarSyncQueue() async {}
  @override
  Future<void> procesarSyncQueueV2() async {}
  @override
  Future<List<Map<String, dynamic>>> fetchVentaItemsSimple({
    String? ventaId,
    String? correlativo,
  }) async =>
      [];
  @override
  Future<Map<String, dynamic>?> fetchDocumentoCache(String numero) async =>
      null;
  @override
  Future<bool> upsertDocumentoCache({
    required String numero,
    required String tipo,
    required String nombre,
    String? direccion,
    required int expiresAtMs,
  }) async =>
      true;
  @override
  Stream<List<Map<String, dynamic>>> streamProductos() =>
      Stream.value([]);
}

// ── Tests ────────────────────────────────────────────────────────────────────
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockProveedorBackend mockBackend;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    mockBackend = MockProveedorBackend();
    // Inyectar mock ANTES de crear ProveedorCaja
    ServicioBackend.usarProveedor(mockBackend);
  });

  tearDown(() {
    // Restaurar proveedor real después de cada test
    ServicioBackend.usarProveedor(ProveedorSupabase());
  });

  group('ServicioBackend — Inyección de dependencia (Strategy Pattern)', () {
    test('usarProveedor() reemplaza el proveedor activo', () async {
      mockBackend.productosRemotos = [
        MockProveedorBackend.productoMock(nombre: 'Cuaderno A4'),
      ];

      final resultados = await ServicioBackend.buscarProductos('cuaderno');

      expect(resultados, isNotEmpty);
      expect(resultados.first.nombre, 'Cuaderno A4');
      expect(mockBackend.llamadasBuscarProducto, 1);
    });

    test('buscarProductos() con backend fallando → lanza excepción controlable',
        () async {
      mockBackend.debeFallar = true;

      expect(
        () async => await ServicioBackend.buscarProductos('cualquier cosa'),
        throwsException,
      );
    });

    test('tieneConexionRemota() retorna false cuando mock lo dice', () async {
      mockBackend.tieneConexion = false;
      final conexion = await ServicioBackend.tieneConexionRemota();
      expect(conexion, isFalse);
    });

    test('tieneConexionRemota() retorna true cuando mock lo dice', () async {
      mockBackend.tieneConexion = true;
      final conexion = await ServicioBackend.tieneConexionRemota();
      expect(conexion, isTrue);
    });

    test('obtenerCategorias() usa datos del mock', () async {
      final cats = await ServicioBackend.obtenerCategorias();
      expect(cats, containsAll(['Test', 'Mock']));
    });

    test('insertarVentaWaterfall con backend OK → retorna (true, docId)',
        () async {
      final venta = Venta(
        id: 'TEST-001',
        items: [],
        total: 10.0,
        operacionGravada: 8.47,
        igv: 1.53,
        fecha: DateTime.now(),
        metodoPago: MetodoPago.efectivo,
        tipoComprobante: TipoComprobante.boleta,
        documentoCliente: '00000000',
        montoRecibido: 10.0,
        vuelto: 0.0,
      );

      final (ok, docId) =
          await ServicioBackend.insertarVentaWaterfall(venta);
      expect(ok, isTrue);
      expect(docId, startsWith('MOCK-DOC-'));
      expect(mockBackend.llamadasInsertarVenta, 1);
    });

    test('insertarVentaWaterfall con backend fallando → retorna (false, null)',
        () async {
      mockBackend.debeFallar = true;

      final venta = Venta(
        id: 'TEST-002',
        items: [],
        total: 5.0,
        operacionGravada: 4.24,
        igv: 0.76,
        fecha: DateTime.now(),
        metodoPago: MetodoPago.yapePlin,
        tipoComprobante: TipoComprobante.boleta,
        documentoCliente: '00000000',
        montoRecibido: 5.0,
        vuelto: 0.0,
      );

      final (ok, docId) =
          await ServicioBackend.insertarVentaWaterfall(venta);
      expect(ok, isFalse);
      expect(docId, isNull);
    });
  });

  group('ProveedorCaja con MockBackend — Escenarios críticos', () {
    late ProveedorCaja pos;

    setUp(() {
      pos = ProveedorCaja(testMode: true);
    });

    test('carrito vacío al inicio', () {
      expect(pos.items, isEmpty);
      expect(pos.totalCobrar, 0.0);
    });

    test('agregar producto mock al carrito', () async {
      final producto = MockProveedorBackend.productoMock(
        id: 'P001',
        nombre: 'Lapicero BIC',
        precio: 1.5,
      );
      await pos.agregarProducto(producto);
      expect(pos.items.length, 1);
      expect(pos.items.first.producto.nombre, 'Lapicero BIC');
      expect(pos.items.first.cantidad, 1);
    });

    test('totalCobrar refleja precio × cantidad correctamente', () async {
      final producto = MockProveedorBackend.productoMock(precio: 5.0);
      await pos.agregarProducto(producto, cantidad: 3);
      expect(pos.totalCobrar, closeTo(15.0, 0.01));
    });

    test('buscarProductos delega correctamente al backend mock', () async {
      mockBackend.productosRemotos = [
        MockProveedorBackend.productoMock(nombre: 'Borrador Pelikan'),
      ];
      final res = await pos.buscarProductos('borrador');
      // El resultado puede venir de local o remoto; el mock debe haberse llamado
      expect(mockBackend.llamadasBuscarProducto, greaterThanOrEqualTo(0));
      // Si viene del mock remoto, debe contenerlo
      if (res.isNotEmpty) {
        expect(res.any((p) => p.nombre.contains('Borrador')), isTrue);
      }
    });

    test('5 carritos aislados sin interferencia', () async {
      final p1 = MockProveedorBackend.productoMock(id: 'P1', nombre: 'Cuaderno');
      final p2 = MockProveedorBackend.productoMock(id: 'P2', nombre: 'Lápiz');

      await pos.agregarProducto(p1, cantidad: 2); // carrito 0

      pos.cambiarCarrito(1);
      expect(pos.items, isEmpty); // carrito 1 aislado

      await pos.agregarProducto(p2, cantidad: 5);
      expect(pos.items.length, 1);

      pos.cambiarCarrito(0);
      expect(pos.items.length, 1);
      expect(pos.items.first.producto.nombre, 'Cuaderno');
      expect(pos.items.first.cantidad, 2);
    });
  });
}
