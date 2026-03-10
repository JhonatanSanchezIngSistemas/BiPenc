# 📘 ESPECIFICACIÓN TÉCNICA Y FUNCIONAL - BiPenc
**Versión:** 2.0 (Producción)  
**Fecha:** 8 de Marzo de 2026  
**Autor:** Arquitectura + Mentor Technical  
**Estado:** ✅ DOCUMENTO CONTROLADOR (Biblia del Proyecto)

---

## 📋 TABLA DE CONTENIDOS
1. [Visión y Alcance](#visión-y-alcance)
2. [Decisiones Arquitectónicas Clave](#decisiones-arquitectónicas-clave)
3. [Requisitos Funcionales Detallados](#requisitos-funcionales-detallados)
4. [Requisitos No-Funcionales](#requisitos-no-funcionales)
5. [Especificación de Datos](#especificación-de-datos)
6. [Flujos Críticos Paso-a-Paso](#flujos-críticos-paso-a-paso)
7. [Manejo de Errores y Fallbacks](#manejo-de-errores-y-fallbacks)
8. [Casos de Uso Críticos y Soluciones](#casos-de-uso-críticos-y-soluciones)
9. [Matriz de Priorización](#matriz-de-priorización)
10. [Testing y Validación](#testing-y-validación)
11. [Trade-offs y Sacrificios](#trade-offs-y-sacrificios)
12. [Roadmap Técnico](#roadmap-técnico)

---

## 🎯 VISIÓN Y ALCANCE

### Objetivo Principal
**BiPenc es un sistema de Punto de Venta (POS) + Gestión de Inventario móvil, diseñado para librerías y tiendas retail, con operación 100% offline-first y sincronización bidireccional con una nube confiable (Supabase).**

### Principios de Diseño (No Negociables)
```
1. OFFLINE-FIRST
   ¿Por qué? Las librerías no siempre tienen WiFi/4G estable.
   Implicación: SQLite es fuente de verdad local; Supabase es respaldo.

2. SIMPLE PERO ROBUSTO
   ¿Por qué? El usuario es vendedor, no ingeniero; el código debe ser mantenible.
   Implicación: No arquitecturas sobre-ingenierizadas; patrones claros.

3. DATOS CORRECTOS SIEMPRE
   ¿Por qué? Una discrepancia de inventario = pérdida de confianza en sistema.
   Implicación: Validaciones múltiples, auditoría completa, versionamiento.

4. IMPRESIÓN GARANTIZADA
   ¿Por qué? El comprobante es el contrato con el cliente.
   Implicación: Buffer persistente; re-intento automático; fallback a archivo.

5. ZERO FRICTION PARA EL USUARIO
   ¿Por qué? Cada segundo cuenta en caja; frustración = abandono.
   Implicación: Búsquedas <200ms; flujos optimizados; atajos de teclado.
```

### Alcance: MVP vs V2.0
```
🔴 MVP (Hoy - Abril 2026)
   • Venta básica (búsqueda + carrito + cobro)
   • Impresión térmica
   • Sincronización batch
   • Login simple
   • Inventario read-only desde nube

🟢 V2.0 (Post-MVP)
   • Reportes avanzados (Top-sellers, tendencias)
   • Devoluciones y notas de crédito
   • Múltiples usuarios simultáneos
   • Integración con APIs externas (proveedores)
   • App de administrador web
```

---

## 🏗️ DECISIONES ARQUITECTÓNICAS CLAVE

### 1. Base de Datos: SQLite Local + Supabase Cloud
**Decisión:** Híbrida (Offline-first)

**Alternativas Consideradas:**
- ❌ Solo cloud (Firebase/Supabase): Requiere WiFi siempre
- ❌ Solo local (SQLite): Sin histórico centralizado
- ✅ Híbrida: Lo mejor de ambos mundos

**Implementación:**
```
┌─────────────────────┐
│   USUARIO EN CAJA   │
│   (Samsung A36)     │
└──────────┬──────────┘
           │
      ┌────▼────────────────────┐
      │   SQLite LOCAL (Caché)  │
      │                         │
      │ • Productos activos     │
      │ • Carrito actual        │
      │ • Ventas sin sincronizar│
      │ • Print queue           │
      │ • Sync queue            │
      └────┬─────────────────────┘
           │
      [WiFi cada 30 segundos - Background sync]
           │
      ┌────▼──────────────────────┐
      │   SUPABASE (Fuente Real)  │
      │                           │
      │ • Productos maestro       │
      │ • Historial de ventas     │
      │ • Usuarios y permisos     │
      │ • Auditoría              │
      │ • Números correlativos   │
      └───────────────────────────┘
```

**Garantía:** Si cae WiFi, el sistema sigue 100% funcional. Los datos nunca se pierden.

---

### 2. Estado Global: Provider (No Redux)
**Decisión:** Usar Provider para state management

**Razonamiento:**
- ✅ Integración nativa con Flutter
- ✅ Menor complejidad vs Redux
- ✅ Performance suficiente (no hay 10,000 usuarios simultáneos)
- ❌ Redux sería over-engineering para este caso

**Estructura:**
```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => PosProvider()),
    ChangeNotifierProvider(create: (_) => InventarioProvider()),
    ChangeNotifierProvider(create: (_) => SessionManager()),
  ],
)
```

---

### 3. Impresión: ESC/POS Directo (No PDF)
**Decisión:** ESC/POS a impresora térmica PT-210 vía Bluetooth

**Trade-off:**
```
✅ Ventajas:
  • Impresión inmediata (sin renderizar PDF)
  • Bajo consumo de memoria
  • Rápido (1-2 segundos)
  • Control fino del layout (ancho 58mm)
  
❌ Desventajas:
  • No hay vista previa en pantalla
  • Difícil cambiar formato después
  • Específico a impresoras térmicas
  
Mitiga: Si en V2.0 necesitas PDF, agregas una capa de abstracción:
interface PrinterAdapter {
  void print(Document doc);
}
```

**NO haremos:**
- ❌ Generar PDF primero
- ❌ Vista previa en UI
- ❌ Impresoras de formato grande (80mm+)

**SÍ haremos:**
- ✅ Buffer de ESC/POS con reintentos
- ✅ Fallback a guardar en archivo si impresora falla

---

### 4. Sincronización: Incremental + Last-Timestamp-Wins
**Decisión:** No batch sync (peligroso); sync incremental cada 30s con resolución de conflictos

**Algoritmo de Conflictos:**
```
Escenario: Dos cajas venden el mismo producto offline

Caja A (10:00 UTC):
  Producto X: stock 100 → 95
  Timestamp local: 10:00
  Versión: 1

Caja B (10:05 UTC - sin conexión):
  Producto X: stock 100 → 90 (su caché es antiguo)
  Timestamp local: 10:05
  Versión: 1

Sincronización:
  A sube a las 10:30 → Supabase: stock=95, ts=10:00, v=1
  B sube a las 10:35 → Supabase recibe: stock=90, ts=10:05, v=1
  
Resolución (Last Timestamp Wins):
  10:05 > 10:00 → B gana
  Resultado: stock=90 en Supabase
  
⚠️ PROBLEMA: Vendimos 15 unidades cuando solo había 10.
SOLUCIÓN: Implementar validación en servidor:

```sql
CREATE FUNCTION sync_stock_safe(product_id, new_stock, timestamp, version) 
RETURNS conflict_result AS $$
BEGIN
  IF new_stock > current_stock THEN
    RETURN 'CONFLICT_INCREASE_REJECTED';
  END IF;
  
  IF timestamp > existing_timestamp THEN
    UPDATE productos SET stock = new_stock WHERE id = product_id;
    RETURN 'OK';
  ELSE
    RETURN 'CONFLICT_OLDER_VERSION';
  END IF;
END $$ LANGUAGE plpgsql;
```

**Garantía:** El servidor NUNCA permite aumentar stock en sync (solo decrementar o rechazar).

---

### 5. Autenticación: Simple (No OAuth)
**Decisión:** Email + Contraseña (Supabase Auth) + Biometría Opcional

**NO hacemos:**
- ❌ Google Login (demasiado offline-incompatible)
- ❌ 2FA obligatorio (fricción)
- ❌ Cambio de contraseña frecuente

**SÍ hacemos:**
- ✅ Token JWT en secure_storage
- ✅ Refresh automático
- ✅ PIN de admin offline
- ✅ Rate limiting en login (5 intentos/15 min)

---

### 6. Validación de Documentos: Estructura Primera (SUNAT Después)
**Decisión:** Implementar estructura UBL 2.1 primero; integración PSE SUNAT en paralelo

**Esto significa:**
```
MES 1-2: El sistema genera boletas válidas en estructura UBL 2.1
         (con XML correcto, pero sin validación SUNAT)

MES 3: Se integra PSE SUNAT cuando obtengamos credenciales

MES 4: Validación real SUNAT en producción
```

**Ventaja delantala:**
- Los datos boletados son legales desde el inicio
- Si PSE falla, la boleta local es válida
- No esperamos a SUNAT para hacer MVP

---

## 📋 REQUISITOS FUNCIONALES DETALLADOS

### RF-1: AUTENTICACIÓN Y SESIÓN

#### RF-1.1: Login Exitoso
```
Endpoint: POST /auth/login
Input:
  email: "vendedor@libreria.com"
  password: "securePass123"

Output:
  ✅ {
    user_id: "uuid-xxxxx",
    token: "eyJhbGc...",
    refresh_token: "eyJhbGc...",
    user: {
      id, nombre, rol, email, max_discount: 10
    }
  }

Validaciones:
  • Email no vacío ✓
  • Contraseña >= 8 caracteres ✓
  • Usuario existe en Supabase ✓
  • Usuario no está desactivado ✓
  
Fallback Offline:
  Si no hay conexión → Usar último token guardado
  Si token expiró > 7 días → Pedir login
```

#### RF-1.2: Biometría Opcional
```
Precondición: Usuario tiene sesión guardada

Flujo:
  1. App detecta sesión existente
  2. Muestra opción "Acceso rápido con huella"
  3. Si usuario presiona → Validar biometría
  4. Si OK → Login automático con token guardado
  5. Si falla → Pedir contraseña

NO es bloqueante: Si no hay sensor biométrico,
                  entra directo con contraseña
```

#### RF-1.3: PIN Admin (Offline)
```
Caso de Uso: Aprobación de precio especial sin WiFi

Flujo:
  1. Vendedor intenta descuento > 20%
  2. Sistema solicita "PIN del Supervisor"
  3. Admin ingresa PIN (6 dígitos)
  4. Validar contra hash en SQLite local
  5. Si OK → Aprobar descuento

PIN is never sent to cloud; validated locally only.
```

---

### RF-2: PROCESO DE VENTA COMPLETO

#### RF-2.1: Búsqueda de Productos
```
Input: Query (texto) o Código de barras

Performance Target: < 200ms para base de 5,000 productos

Implementación:
  1. Usar SQLite FTS5 (Full-Text Search)
  2. Indexar: código, descripción, marca, modelo
  
SQL:
  CREATE VIRTUAL TABLE productos_fts USING fts5(
    codigo, descripcion, marca, modelo
  );

Query:
  SELECT * FROM productos_fts 
  WHERE productos_fts MATCH 'QUERY' 
  LIMIT 20;
  
Results:
  ✓ Coincidencias exactas primero
  ✓ Luego parciales
  ✓ Máximo 20 resultados
```

#### RF-2.2: Agregar al Carrito
```
Input:
  - Producto ID
  - Cantidad
  - Precio unitario (puede diferir de precio base)

Validaciones:
  ✓ Cantidad > 0
  ✓ Stock disponible >= Cantidad
  ✓ Precio > 0
  ✓ Producto no duplicado (sumar cantidad)

Output:
  ItemCarrito {
    id: "uuid",
    producto: Producto,
    cantidad: 5,
    precio_unitario: 45.00,
    subtotal: 225.00,
    es_mayorista: false,
    precio_manual_override: null,
  }

Si Error: Mostrar SnackBar rojo con motivo
```

#### RF-2.3: Cálculo de Totales
```
Algoritmo:

1. Subtotal = SUM(item.cantidad * item.precio_unitario)

2. Descuentos Aplicados:
   - Por mayorista (automático si cantidad >= 3)
   - Manual (si rol lo permite)
   - Descuento máximo según rol:
     * Vendedor: 15%
     * Supervisor: 30%
     * Gerente/Admin: Sin límite

3. Base Imponible = Subtotal - DescuentoTotal

4. IGV = Base Imponible * 0.18

5. TOTAL = Base Imponible + IGV

Desglose mostrado al usuario:
```
Subtotal:     S/. 225.00
Descuento:    S/. -22.50  (-10%)
Base:         S/. 202.50
IGV (18%):    S/. 36.45
─────────────────────────
TOTAL:        S/. 238.95
```

#### RF-2.4: Procesan de Pago
```
Métodos Soportados:
  1. Efectivo
  2. Tarjeta de crédito/débito
  3. Combinado (parcial efectivo + parcial tarjeta)

Flujo:
  1. Mostrar total a pagar
  2. Usuario selecciona método
  
  Si Efectivo:
    - Ingresar monto recibido
    - Calcular vuelto = monto - total
    - Mostrar vuelto de forma clara
  
  Si Tarjeta:
    - [NO implementamos reader de tarjeta]
    - Solo registramos que fue "Tarjeta"
    - Manual: vendedor anota número
    
  Si Combinado:
    - Ingresar monto en efectivo
    - Saldo faltante = Tarjeta

Validaciones:
  ✓ Monto >= Total
  ✓ Monto es número válido
```

#### RF-2.5: Generación de Comprobante
```
Input: Carrito completo + Método pago + Cliente (opcional para boleta)

Output: Documento UBL 2.1 (XML) + ESC/POS (bytes para impresora)

Estructura del Comprobante:
  • Tipo: BOLETA (si sin RUC) | FACTURA (si con RUC)
  • Correlativo: B-001-000001 (boleta) o F-001-000001 (factura)
  • Emisor: Datos de la empresa
  • Receptor: DNI o RUC (opcional para boleta)
  • Fecha/Hora: NOW()
  • Ítems: [{ descripción, cantidad, precio, subtotal }, ...]
  • Totales: { subtotal, igv, total }
  • QR: Código QR con resumen
  
Generación del número correlativo:
  Query supabase:
    SELECT generar_correlativo('BOLETA') 
    → Retorna: B-001-000123
    
  Garantía: Atómico, sin duplicados
  
  ** IMPORTANTE **:
    Si sin conexión → Usar contador local
    Cuando sincroniza → Validar no duplicados
```

#### RF-2.6: Impresión en PT-210
```
Hardware: Impresora térmica Bluetooth 58mm (PT-210)

Protocolo: ESC/POS (Epson Standard Command Set)

Flujo:
  1. Generar buffer ESC/POS a partir del documento
  2. Conectar a PT-210 via Bluetooth
  3. Enviar buffer
  4. Esperar confirmación o timeout (5s)
  5. Si OK → ✓ Impreso
  6. Si falla → Encolar para reintentar

Estructura del Ticket Térmico:
```
[CENTERED] LIBRERÍA NOMBRE
RUC: 12345678901
Dir: Calle X, Ciudad

─────────────────────────────────
Boleta Nº: B-001-000123
Fecha: 08/03/2026 - 14:25

Producto              Cant. Precio Subtotal
─────────────────────────────────────────
Libro Ficción Bla...    2   45.00   90.00
Cuaderno Rayado 80h     5   12.50   62.50
Bolígrafo azul         10    1.50   15.00

─────────────────────────────────
Subtotal:                      167.50
Descuento:                       0.00
Base Imponible:               167.50
IGV (18%):                     30.15
─────────────────────────────────
TOTAL A PAGAR:                197.65

Método: EFECTIVO
Recibido: 200.00
Vuelto:     2.35

QR: [QR code here]

¡Gracias por su compra!
─────────────────────────────────
```

Comando ESC/POS (pseudocódigo):
```
data = []
data += ESC_CENTER  // Centrado
data += encode("LIBRERÍA NOMBRE")
data += LF
data += ESC_NORMAL  // Alineación normal
data += encode("Boleta Nº: B-001-000123")
data += LF
data += ESC_UNDERLINE
data += encode("Producto        Cant. Precio")
data += ESC_NO_UNDERLINE
// ... más líneas ...
data += ESC_CUT  // Corte automático

bluetooth.send(data)
```

---

### RF-3: GESTIÓN DE INVENTARIO

#### RF-3.1: Actualización de Stock
```
Cuando: Cada vez que se procesa una venta

Movimiento:
  stock_anterior = 100
  cantidad_vendida = 5
  stock_nuevo = 95

SQLite Update:
  UPDATE productos 
  SET stock = stock - 5,
      last_sync_timestamp = NOW(),
      local_version = local_version + 1
  WHERE id = 'product-uuid'

Garantía:
  ✓ Stock decrementado LOCAL de inmediato
  ✓ Operación ACID (SQLite transaction)
  ✓ Timestamp registrado para conflicto resolver
```

#### RF-3.2: Sincronización de Stock
```
Trigger: Background service cada 30 segundos + Pull refresh manual

Algoritmo:

PULL (Actualizar inventario desde Supabase):
  1. Obtener productos con timestamp > last_sync
  2. Comparar local vs remoto
  3. Si remoto es más reciente → Actualizar local
  4. Log en sync_log

PUSH (Enviar cambios locales):
  1. Obtener productos con local_version != server_version
  2. Para cada diferencia:
     - Enviarversion local a Supabase
     - Validar con servidor (no aumentar stock)
  3. Si OK → Marcar como sincronizado
  4. Si error → Reintentos exponenciales

Reintentos Exponenciales:
  Intento 1: Inmediato
  Intento 2: 1 segundo
  Intento 3: 2 segundos
  Intento 4: 4 segundos
  Intento 5: 8 segundos (máximo 5 intentos)
```

#### RF-3.3: Resolución de Conflictos
```
Escenario: Dos cajas venden offline

Caja A (10:00):
  Producto X: 100 → 95
  last_sync_ts: 10:00

Caja B (10:05):
  Producto X: 100 → 90 (caché antigua)
  last_sync_ts: 10:05

Sincronización en Supabase:

1. A intenta subir:
   UPDATE productos SET stock=95 WHERE id=X
   ✓ OK (stock bajó)

2. B intenta subir:
   A. Leer stock actual en servidor → 95
   B. B quiere poner 90 (< 95) → ✓ Permitir
   C. Actualizar → stock=90
   
⚠️ PROBLEMA: Vendimos 15 unidades de 10. Solución en validación:

Validación en RPC:

```sql
CREATE FUNCTION sync_inventory() RETURNS TABLE (...) AS $$
BEGIN
  -- NO PERMITIR AUMENTAR STOCK
  IF NEW.stock > OLD.stock THEN
    INSERT INTO sync_conflicts (...) VALUES (...);
    RAISE EXCEPTION 'Intento de aumentar stock';
  END IF;
  
  -- TIMESTAMP más reciente gana
  IF NEW.last_sync_ts > OLD.last_sync_ts THEN
    UPDATE productos SET stock = NEW.stock WHERE id = NEW.id;
  ELSE
    --- Mantener valor anterior (más reciente en servidor)
  END IF;
END $$ LANGUAGE plpgsql;
```

GARANTÍA: El servidor hace el arbitraje final. Local nunca está "más correcto".
```

---

### RF-4: COMPROBANTES ELECTRÓNICOS (SUNAT)

#### RF-4.1: ​Estructura UBL 2.1
```
XML Schema Simplificado:

<Invoice>
  <UBLVersionID>2.1</UBLVersionID>
  <CustomizationID>2.0</CustomizationID>
  
  <ID>B-001-000123</ID>
  <IssueDate>2026-03-08</IssueDate>
  <IssueTime>14:25:00</IssueTime>
  
  <AccountingSupplierParty>
    <Party>
      <PartyName>
        <Name>LIBRERÍA EJEMPLO S.A.C</Name>
      </PartyName>
      <PartyIdentification>
        <ID>20123456789</ID> <!-- RUC -->
      </PartyIdentification>
    </Party>
  </AccountingSupplierParty>
  
  <AccountingCustomerParty>
    <Party>
      <PartyIdentification>
        <ID>12345678</ID> <!-- DNI o RUC -->
      </PartyIdentification>
    </Party>
  </AccountingCustomerParty>
  
  <TaxTotal>
    <TaxAmount>30.15</TaxAmount>
    <TaxSubtotal>
      <TaxAmount>30.15</TaxAmount>
      <TaxCategory>
        <Percent>18</Percent>
        <TaxScheme>
          <ID>1000</ID> <!-- IGV -->
        </TaxScheme>
      </TaxCategory>
    </TaxSubtotal>
  </TaxTotal>
  
  <LegalMonetaryTotal>
    <LineExtensionsAmount>167.50</LineExtensionsAmount>
    <TaxInclusiveAmount>197.65</TaxInclusiveAmount>
    <PayableAmount>197.65</PayableAmount>
  </LegalMonetaryTotal>
  
  <InvoiceLine>
    <ID>1</ID>
    <InvoicedQuantity>2</InvoicedQuantity>
    <LineExtensionAmount>90.00</LineExtensionAmount>
    <Item>
      <Description>Libro Ficción Blabla</Description>
      <SellersItemIdentification>
        <ID>LIBRO-001</ID> <!-- Código interno -->
      </SellersItemIdentification>
    </Item>
    <Price>
      <PriceAmount>45.00</PriceAmount>
    </Price>
  </InvoiceLine>
  
  [ ... más ítems ... ]
  
</Invoice>
```

Generación en Dart:
```dart
class ComprobantePdf {
  String generateUBL(Venta venta) {
    final xml = XmlDocument();
    final invoice = xml.buildElement('Invoice');
    
    invoice.buildElement('UBLVersionID', text: '2.1');
    invoice.buildElement('CustomizationID', text: '2.0');
    invoice.buildElement('ID', text: venta.numeroComprobante);
    invoice.buildElement('IssueDate', text: venta.fecha);
    invoice.buildElement('IssueTime', text: venta.hora);
    
    // ... más campos ...
    
    return xml.toXmlString();
  }
}
```

#### RF-4.2: QR Code
```
Contenido del QR (estándar SUNAT):

{
  "ruc": "20123456789",
  "tipo_comprobante": "01" (factura) o "03" (boleta),
  "numero_serie": "F-001" o "B-001",
  "numero_correlativo": "000123",
  "fecha": "08/03/2026",
  "monto_total": "197.65", 
  "monto_igv": "30.15",
  "ruc_cliente": "", (opcional para boleta)
  "firma_digital": base64(hash_documento)
}

Generación:
  qr_data = json.encode(...)
  qr_code = QR(qr_data).generate()
  image = qr_code.toImage()
```

#### RF-4.3: Integración SUNAT PSE (FASE 2)
```
Cronología:

MES 1 (Ahora):
  - Sistema genera UBL 2.1 válido (sin validación SUNAT)
  - Boletas se emiten localmente
  - XML se guarda en almacenamiento local

MES 2-3:
  - Obtener credenciales SUNAT (certificado digital, RUC)
  - Implementar cliente SOAP/REST para PSE
  - Testing en ambiente demo de SUNAT

MES 4:
  - Validación real en PSE producción
  - Fallback: Si PSE no responde, boleta local válida

Implementación (pseudocódigo):

class SunatPseClient {
  Future<SunatValidationResult> validarBoleta(String xmlFirmado) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.sunat.gob.pe/validar'),
        headers: {
          'Content-Type': 'application/xml',
          'Authorization': 'Bearer $token',
        },
        body: xmlFirmado,
      );
      
      if (response.statusCode == 200) {
        return SunatValidationResult.success(
          numeroAceptacion: parse(response.body)['numero_aceptacion'],
        );
      } else {
        // Fallback: validar localmente
        return validateLocally(xmlFirmado);
      }
    } catch (e) {
      // Sin conexión: usar validación local
      return validateLocally(xmlFirmado);
    }
  }
  
  String validateLocally(String xml) {
    // Validación básica: estructura, campos obligatorios
    final isValid = XMLValidator.validate(xml);
    return isValid ? 'VALID_LOCAL' : 'INVALID';
  }
}
```

---

## 📊 REQUISITOS NO-FUNCIONALES

### RNF-1: Performance
```
Métrica                          Target          Actual (Esperado)
─────────────────────────────────────────────────────────────
Búsqueda de productos           < 200ms         ~100ms (FTS5)
Cálculo de totales              < 50ms          ~10ms
Añadir producto carrito         < 100ms         ~30ms
Generar comprobante             < 1s            ~800ms
Impresión (hasta PT-210)        < 3s            ~2s
Carga de app (cold start)       < 3s            ~2.5s
Scroll de lista (1000 items)    60 FPS          60 FPS (SliverList)
```

**Medición:**
```dart
final stopwatch = Stopwatch()..start();
// Operación aquí
stopwatch.stop();
print('Tiempo: ${stopwatch.elapsedMilliseconds}ms');
```

### RNF-2: Seguridad
```
Requerimiento                   Implementación
─────────────────────────────────────────────────────
Encriptación en tránsito        HTTPS (Supabase)
Encriptación en reposo          AES-256 (flutter_secure_storage)
Validación de entrada           WhiteList + Sanitize
Rate limiting                   5 intentos/15min en login
Token expiry                    Cada 24 horas
Refresh token                   Cada 7 días
Auditoría de acciones críticas  Log en audit_log (Supabase)
NO logs de contraseñas          NUNCA
Certificado SSL pinned          Opcional (V2.0)
```

### RNF-3: Disponibilidad
```
Característa                     Target
─────────────────────────────────────────────────
Uptime offline                  100% (sin internet)
Uptime online                   99.5% (con issues de red)
Data durability                 ACID + Backups
Recuperación de crash           Automática (última transacción safe)
Máximo downtime tolerable       30 minutos
```

### RNF-4: Escalabilidad
```
Cargas soportadas:

Inventario:
  • Hasta 50,000 productos
  • Búsqueda sigue siendo <200ms (índices FTSS5)

Historial de ventas:
  • Hasta 100,000 transacciones locales
  • Sincronización batch máximo 10MB por ciclo

Usuarios simultáneos:
  • 1 dispositivo por caja (no multi-user en mismo A36)
  • Múltiples A36 sincronizados en paralelo (Supabase maneja)

Almacenamiento:
  • ~500MB máximo en SQLite local
  • Android 12+ tiene 64GB disponibles
```

---

## 🗂️ ESPECIFICACIÓN DE DATOS

### Modelo de BD Relacional

```sql
-- USUARIOS (Supabase Auth + tabla propia)
CREATE TABLE users (
  id UUID PRIMARY KEY (FK supabase.auth),
  email TEXT UNIQUE NOT NULL,
  nombre TEXT NOT NULL,
  rol ENUM('vendedor', 'supervisor', 'gerente', 'admin') DEFAULT 'vendedor',
  max_descuento_porcentaje INT DEFAULT 15,
  esta_activo BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- PRODUCTOS (Inventario maestro)
CREATE TABLE productos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo_barras TEXT UNIQUE NOT NULL,
  sku TEXT UNIQUE NOT NULL,
  descripcion TEXT NOT NULL,
  marca TEXT,
  modelo TEXT,
  color TEXT,
  categoria TEXT,
  precio_base DECIMAL(10,2) NOT NULL,
  precio_mayorista DECIMAL(10,2),
  stock INTEGER DEFAULT 0,
  stock_minimo INTEGER DEFAULT 10,
  imagen_url TEXT,
  activo BOOLEAN DEFAULT true,
  
  -- Versionamiento para sync
  last_sync_timestamp TIMESTAMP DEFAULT NOW(),
  local_version INTEGER DEFAULT 0,
  sync_hash TEXT,
  
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  
  UNIQUE(codigo_barras, sku)
);

-- DOCUMENTOS (Boletas y Facturas)
CREATE TABLE documentos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo ENUM('BOLETA', 'FACTURA') NOT NULL,
  serie TEXT NOT NULL,           -- B-001 o F-001
  correlativo INTEGER NOT NULL,  -- 000001, 000002, ...
  numero_completo TEXT GENERATED ALWAYS AS (serie || '-' || LPAD(correlativo::TEXT, 6, '0')) STORED,
  
  usuario_id UUID NOT NULL (FK users),
  cliente_ruc_dni TEXT,
  fecha DATE NOT NULL,
  hora TIME NOT NULL,
  
  subtotal DECIMAL(10,2) NOT NULL,
  descuento DECIMAL(10,2) DEFAULT 0,
  base_imponible DECIMAL(10,2) NOT NULL,
  igv DECIMAL(10,2) NOT NULL,
  total DECIMAL(10,2) NOT NULL,
  
  metodo_pago ENUM('EFECTIVO', 'TARJETA', 'COMBINADO') NOT NULL,
  
  estado ENUM('PENDIENTE', 'IMPRESO', 'ANULADO') DEFAULT 'PENDIENTE',
  xml_ubl TEXT,
  qr_code TEXT,
  
  sync_status ENUM('PENDING', 'SYNCED', 'CONFLICT') DEFAULT 'PENDING',
  
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  
  UNIQUE(serie, correlativo) -- Evitar correlativo duplicado
);

-- ITEMS DEL DOCUMENTO (Líneas de venta)
CREATE TABLE documento_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  documento_id UUID NOT NULL (FK documentos),
  producto_id UUID NOT NULL (FK productos),
  
  cantidad INTEGER NOT NULL,
  precio_unitario DECIMAL(10,2) NOT NULL,
  subtotal DECIMAL(10,2) NOT NULL,
  es_precio_especial BOOLEAN DEFAULT false,
  razon_precio_especial TEXT,
  
  created_at TIMESTAMP DEFAULT NOW()
);

-- COLA DE SINCRONIZACIÓN (Local en SQLite)
CREATE TABLE sync_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tabla TEXT NOT NULL,
  operacion TEXT NOT NULL, -- 'INSERT', 'UPDATE', 'DELETE'
  datos_antes TEXT,        -- JSON
  datos_nuevos TEXT,       -- JSON
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  intentos INTEGER DEFAULT 0,
  error_mensaje TEXT,
  sincronizado BOOLEAN DEFAULT FALSE
);

-- CONFLICTOS DE SINCRONIZACIÓN (Auditoría)
CREATE TABLE sync_conflicts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tabla TEXT NOT NULL,
  registro_id TEXT,
  version_local INTEGER,
  version_servidor INTEGER,
  timestamp_local DATETIME,
  timestamp_servidor DATETIME,
  resultado TEXT, -- 'LOCAL_WINS', 'SERVER_WINS', 'MERGE'
  resuelto_en DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- AUDITORÍA (Qué pasó, quién lo hizo)
CREATE TABLE audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id UUID (FK users),
  acccion TEXT NOT NULL,
  tabla_afectada TEXT,
  registro_id TEXT,
  datos_anteriores TEXT,  -- JSON
  datos_nuevos TEXT,      -- JSON
  ip_address TEXT,
  timestamp TIMESTAMP DEFAULT NOW()
);

-- COLA DE IMPRESIÓN (Local en SQLit)
CREATE TABLE print_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  documento_id TEXT NOT NULL,
  data_escpos BLOB NOT NULL,
  intentos INTEGER DEFAULT 0,
  impreso BOOLEAN DEFAULT FALSE,
  error_mensaje TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ÍNDICES CRÍTICOS
CREATE INDEX idx_productos_sku ON productos(sku);
CREATE INDEX idx_productos_codigo_barras ON productos(codigo_barras);
CREATE INDEX idx_documentos_usuario ON documentos(usuario_id);
CREATE INDEX idx_documentos_fecha ON documentos(fecha);
CREATE INDEX idx_documento_items_documento ON documento_items(documento_id);
CREATE INDEX idx_sync_queue_sincronizado ON sync_queue(sincronizado);

-- FULL-TEXT SEARCH
CREATE VIRTUAL TABLE productos_fts USING fts5(
  codigo_barras, sku, descripcion, marca, modelo
);

-- VIEW: Resumen de ventas hoy
CREATE VIEW ventas_del_dia AS
SELECT 
  DATE(d.fecha) as fecha,
  COUNT(d.id) as cantidad_documentos,
  SUM(d.total) as total_vendido,
  SUM(d.igv) as igv_total
FROM documentos d
WHERE d.fecha = CURRENT_DATE
GROUP BY DATE(d.fecha);
```

---

## 🔄 FLUJOS CRÍTICOS PASO-A-PASO

### FLUJO 1: Venta Completa (Happy Path)

```
INICIO: Vendedor abre app

[1] BUSCAR PRODUCTO
    Acción: Scan código QR / Ingresa texto
    Validación: Código válido
    Resultado: Producto encontrado & datos cargados
    
[2] AGREGAR AL CARRITO
    Acción: Presiona "Agregar"
    Validación: Stock suficiente
    Resultado: Producto en carrito (cantidad inicial = 1)
    
[3] AJUSTAR CANTIDAD
    Acción: Vendedor cambia cantidad a 5
    Validación: 5 <= stock disponible
    Resultado: Subtotal actualizado
    
[4] REPETIR SI NECESARIO
    Acción: Busca & agrega más productos
    Resultado: Carrito con múltiples ítems
    
[5] REVISAR CARRITO
    Estado mostrado:
      Producto A: 2 × $45 = $90
      Producto B: 5 × $12.50 = $62.50
      ───────────────────────
      Subtotal: $152.50
      Desc.: $0
      Base: $152.50
      IGV: $27.45
      ───────────────────────
      TOTAL: $179.95
    
    Opción: "Cambiar cantidad", "Quitar", "Aplicar descuento"
    
[6] APLICAR DESCUENTO (Opcional)
    Si vendedor presiona "Descuento":
      - Ingresa porcentaje (ej: 10%)
      - Sistema valida vs rol (máx 15% para vendedores)
      - Si OK → Recalcula totales
      - Si > permiso → Solicita PIN admin
    
    Resultado: Descuento aplicado & registrado
    
[7] PROCEDER A COBRO
    Acción: Presiona "COBRAR"
    
[8] SELECCIONAR MÉTODO DE PAGO
    Opciones:
      □ Efectivo
      □ Tarjeta
      □ Combinado
    
    Si EFECTIVO:
      - Sistema pide: "Monto recibido"
      - Calcula vuelto automáticamente
      - Muestra: "Vuelto: $20.05"
    
    Si TARJETA:
      - Sistema registra como "TARJETA" (sin integración de reader)
    
    Si COMBINADO:
      - Acción: "¿Cuánto en efectivo?"
      - Sistema calcula saldo = Total - Efectivo
      - Muestra: "Efectivo: $100 + Tarjeta: $79.95"
    
[9] GENERAR COMPROBANTE
    Sistema:
      1. Genera número correlativo (B-001-000001)
      2. Crea XML UBL 2.1
      3. Genera QR code
      4. Formatea ESC/POS para impresora
      5. Crea JSON para auditoría
    
    Resultado: Comprobante listo
    
[10] REGISTRAR EN BD LOCAL
     SQLite transaction:
       BEGIN;
       INSERT INTO documentos (...);
       INSERT INTO documento_items (...) x N items;
       UPDATE productos SET stock = stock - cantidad WHERE id = ... (para cada item);
       INSERT INTO audit_log (...);
       COMMIT;
    
     Garantía: ACID - todo o nada
    
[11] ENCOLAR PARA IMPRESIÓN
     INSERT INTO print_queue (documento_id, data_escpos, ...);
     
     Si impresora conectada:
       → Imprimir de inmediato
       → Mostrar "✓ Impreso"
     
     Si impresora desconectada:
       → Mostrar "Impresión pendiente"
       → Botón "Reintentar impresión"
    
[12] ENCOLAR PARA SINCRONIZACIÓN
     INSERT INTO sync_queue (tabla='documentos', operacion='INSERT', datos_nuevos=...);
     INSERT INTO sync_queue (tabla='productos', operacion='UPDATE', ...);
     
     Backend task (cada 30s):
       → Leer sync_queue
       → Enviar a Supabase
       → Si OK → Marcar como sincronizado
       → Si error → Reintentar (exponencial)
    
[13] MOSTRAR RECIBO EN PANTALLA
     UI muestra:
       "✓ Pago recibido"
       "Vuelto: $20.05"
       "Boleta: B-001-000001"
       
       Botones:
       [Imprimir de Nuevo] [Nueva Venta] [Reportes]
    
[14] NUEVA VENTA
     Acción: Presiona "Nueva Venta"
     Estado: Carrito se limpia
     Regresa a [1]

FIN

═══════════════════════════════════════════════════════════

TIEMPO TOTAL ESTIMADO: 1-2 minutos
CRITICAL PATH: Búsqueda (<200ms) → Agregar carrito (x vendidos) → Cobro (10s) → Impresión (2s)

VARIACIONES:
- Sin WiFi: Mismo flujo, sync ocurre después
- Impresora desconectada: Flujo continúa, reintentos en background
- Descuento requiere PIN: Se añaden 10-20s al proceso
```

### FLUJO 2: Sincronización Offline → Online

```
ESCENARIO: Vendedor hizo 50 ventas offline (sin WiFi)
           Recupera conexión
           Sistema debe sincronizar sin perder datos

[1] DETECCIÓN DE CONEXIÓN
    Listener en connectivity_plus:
    "WiFi conectada"
    
[2] INICIAR SYNC
    Background service ejecuta:
    
    sync_process() {
      1. Leer sync_queue
      2. Para cada item:
        - Enviar a Supabase
        - Manejar conflictos
        - Marcar como sincronizado
      3. Regenerar números correlativo si hubo conflicto
      4. Log de resultados
    }
    
[3] PROCESO POR ITEM
    
    ITEM: Documento de venta
    
    a) Validar en servidor:
       SELECT * FROM documentos 
       WHERE numero_completo = 'B-001-000050'
       
       Si EXISTE → CONFLICT (mismo número en dos cajas)
         Solución: Regenerar número locally + volver a enviar
       
       Si NO existe → Enviar INSERT
    
    b) Si es UPDATE de stock:
       Validación servidor:
       IF new_stock > current_stock THEN
         REJECT (no aumentar stock)
       ELSE
         UPDATE productos SET stock = new_stock
       END
    
    c) Si OK → Marcar como SYNCED en sync_queue
    
    d) Si ERROR → Incrementar intentos, reintentar después
       (exponencial backoff: 1s, 2s, 4s, 8s)
    
[4] CONFLICTOS RESUELTOS
    
    Cada conflicto se registra:
    INSERT INTO sync_conflicts (
      tabla, registro_id, version_local, version_servidor, 
      resultado, ...
    )
    
    Resultado: AUDITABLE - qué pasó y cómo se resolvió
    
[5] SINCRONIZACIÓN COMPLETA
    
    Estado final:
    - sync_queue vacío (o solo items fallidos > 5 reintentos)
    - Todos los documentos en Supabase
    - Stock consistente
    - Auditoría registrada
    
[6] NOTIFICACIÓN AL USUARIO
    
    UI muestra:
    "✓ Sincronización completada"
    "50 ventas enviadas"
    "0 conflictos"
    
    Si hubo errores:
    "⚠️ 2 items pendientes - Reintentar?"

FIN

═══════════════════════════════════════════════════════════

GARANTÍAS:
✓ Ningún dato se pierde
✓ Correlativo único en servidor (último check point)
✓ Stock no se duplica
✓ Auditoría completa
✓ User-friendly (notificaciones claras)
```

---

## ⚠️ MANEJO DE ERRORES Y FALLBACKS

### Matriz de Errores Críticos

```
ERROR                           FALLBACK                      UI FEEDBACK
────────────────────────────────────────────────────────────────────────
Falta producto en stock       Mostrar "Stock insuficiente"  ❌ Red snackbar
                              No agregar al carrito

Impresora desconectada        Encolar para reintentar       ⚠️ Yellow banner
                              Continuar venta               "Impresión pendiente"

WiFi cae a mitad de sync      Guardar estado local          ✓ Continuar offline
                              Reintentar cuando vuelva      Info sobre sync

Número correlativo            Regenerar localmente          ⚠️ Notificación
duplicado                     Validar en servidor           "Número ajustado"
                              Re-sincronizar

Impuesto incorrecto           Re-calcular con 18%          ⚠️ Corregir manual
                              Auditar quién lo causó        "IGV recalculado"

RUC/DNI inválido             Rechazar documento            ❌ Red error
(para factura)               Pedir datos válidos            "RUC no válido"

Usuario no autorizado         Rechazar acción              ❌ Red snackbar
para descuento > límite       Solicitar PIN admin           "Requiere aprobación"

Crash antes de impresión     Recuperar desde DB           ✓ "Reimprimiendo..."
                             Reintentar print queue

App se cierra #              Recuperar última transacción  ✓ Clean startup
                             desde ACID SQLite transac     "Última venta guardada"

Database corrupta            Restaurar desde Supabase    ❌ Error grave
                            (si es posible)               "Contactar soporte"
                            Sino: Error fatal
```

---

## 🎯 CASOS DE USO CRÍTICOS Y SOLUCIONES

### UC-1: Dos Cajas Venden el Mismo Producto Offline

```
Timeline:

10:00 - Caja A lee stock Producto X = 100
10:05 - Caja B lee stock Producto X = 100 (sin sync)

10:15 - Caja A vende 5 unidades X
        stock_local_A = 95
        last_sync_ts_A = 10:15
        
10:20 - Caja B ve que "se acabó" (basándose en su caché antigua)
        ¿Stock real? 100 (según su caché local)
        Vende 15 unidades X
        stock_local_B = 85
        last_sync_ts_B = 10:20

10:30 - Caja A se conecta, sube: stock=95, ts=10:15
        Supabase: stock=95 ✓ (bajó, OK)

10:35 - Caja B se conecta, sube: stock=85, ts=10:20
        Validación servidor:
        IF 85 < 95 (anterior) THEN OK (stock bajó)
        ENDIF
        Supabase: stock=85 ✓
        
⚠️ PROBLEMA: Vendimos 20 unidades de 100 = OK
             PERO si Caja B hubiera vendido 150 unidades...
             
SOLUCIÓN: Validación absoluta en servidor

RPC en Supabase:

CREATE FUNCTION validate_stock_sync(
  p_product_id UUID,
  p_new_stock INT,
  p_timestamp TIMESTAMP,
  p_local_version INT
) RETURNS JSON AS $$
DECLARE
  v_current_stock INT;
  v_server_timestamp TIMESTAMP;
  v_server_version INT;
BEGIN
  -- Leer estado actual
  SELECT stock, last_sync_timestamp, local_version
  INTO v_current_stock, v_server_timestamp, v_server_version
  FROM productos WHERE id = p_product_id FOR UPDATE;
  
  -- 1. NO PERMITIR AUMENTAR STOCK
  IF p_new_stock > v_current_stock THEN
    -- Log conflicto
    INSERT INTO sync_conflicts (...) 
    VALUES (p_product_id, ..., 'REJECTED_INCREASE', ...);
    
    RETURN JSON_OBJECT(
      'status' => 'ERROR',
      'code' => 'STOCK_INCREASE_REJECTED',
      'message' => 'Servidor no permite aumentar stock',
      'server_stock' => v_current_stock
    );
  END IF;
  
  -- 2. TIMESTAMP más reciente gana
  IF p_timestamp > v_server_timestamp THEN
    UPDATE productos 
    SET stock = p_new_stock,
        last_sync_timestamp = p_timestamp,
        local_version = p_local_version
    WHERE id = p_product_id;
    
    RETURN JSON_OBJECT(
      'status' => 'OK',
      'reason' => 'NEWER_TIMESTAMP'
    );
  ELSE
    -- Mantener stock del servidor (más reciente en servidor)
    -- Mensaje: "Stock local era antiguo, se usó versión servidor"
    
    RETURN JSON_OBJECT(
      'status' => 'CONFLICT_RESOLVED',
      'reason' => 'SERVER_TIMESTAMP_NEWER',
      'server_stock' => v_current_stock
    );
  END IF;
END $$ LANGUAGE plpgsql;

GARANTÍA:
✓ Servidor tiene versión correcta siempre
✓ Conflictos documentados
✓ Auditable: qué pasó y por qué
```

### UC-2: Impresora Desconecta a Mitad de Venta

```
Escenario:
1. Venta procesada en BD local ✓
2. Comprobante generado ✓
3. ESC/POS enviado a impresora
4. PT-210 se queda sin papel / pierde Bluetooth
5. Impresión FALLA

Soluciones en orden:

[1] BUFFER PERSISTENTE
    
    IF impresion_fallida() {
      INSERT INTO print_queue (documento_id, escpos_data, intentos=0);
      UI.mostrar("⚠️  Impresora no disponible");
      UI.mostrar_boton("Reintentar");
    }
    
[2] REINTENTOS AUTOMÁTICOS
    
    Background service (cada 5 minutos):
    
    SELECT * FROM print_queue WHERE impreso = FALSE
    FOR EACH item:
      TRY impresora.print(data)
      IF OK:
        UPDATE print_queue SET impreso = TRUE
      ELSE:
        UPDATE print_queue SET intentos = intentos + 1
        IF intentos > 10:  // Máximo 10 reintentos
          UPDATE print_queue SET error_mensaje = "Impresora no responde"
        END
    
[3] REINTENTAR MANUAL
    
    Vendedor presiona "Reimprimir"
    Sistema busca documento
    Muestra vista previa del ticket
    Usuario presiona "Imprimir"
    → Reintenta
    
[4] FALLBACK A ARCHIVO
    
    IF todos_intentos_fallaron:
      guardar_en_archivo("/sdcard/Documents/ticket_B-001-000050.txt")
      UI.mostrar("Ticket guardado en teléfono")
      UI.mostrar_boton("Ver archivo")
      
      Vendedor puede:
      - Imprimir desde otra app
      - Enviar por email
      - Mostrar en pantalla al cliente
      
GARANTÍA:
✓ Venta registrada (BD local)
✓ Comprobante recuperable
✓ No hay pérdida de datos
✓ User-friendly (opciones claras)
```

### UC-3: Stock Inconsistente (Auditoría)

```
Escenario: Manager nota que stock en app ≠ contador físico

Acción:
1. Manager abre "Auditoría" en settings
2. Sistema muestra:
   
   HISTORIAL DE CAMBIOS - Producto X (SKU: ABC-123)
   ─────────────────────────────────────────────────────
   2026-03-08 14:25  Vendedor Juan   Venta         -5 (stock: 100→95)
   2026-03-08 14:30  Vendedor María  Venta         -3 (stock: 95→92)
   2026-03-08 14:35  SYNC             Sync conflict ±0 (LastTS resolve)
   2026-03-08 15:00  Manager Admin    Ajuste manual +10 (restock)
   
   STOCK ACTUAL EN APP: 102
   STOCK FÍSICO CONTADO: 100
   DISCREPANCIA: +2
   
3. Manager puede:
   - Ver quién hizo cada cambio
   - Ver motivo (venta, sync, ajuste manual)
   - Hacer ajuste: "Registrar corrección +/- 2"
   
   Sistema crea:
   INSERT INTO documentos_ajuste (
     tipo = 'INVENTORY_CORRECTION',
     cantidad = -2,
     razon = 'Discrepancia en auditoría física',
     usuario = admin_id,
     ...
   )
   
   UPDATE productos SET stock = 100 WHERE id = X;
   INSERT INTO audit_log (...);
   
4. Sincronización:
   Background sync envía corrección a Supabase
   Supabase auditaría: "Manager ajustó stock en A36"

GARANTÍA:
✓ Auditoría completa (rastreable)
✓ Correcciones documentadas
✓ No hay datos perdidos
✓ Manager tiene control

NOTA: Si stock difiere SIEMPRE, podría indicar:
- Bug en sync
- Venta no registrada
- Ingreso manual olvidado
SOLUCIÓN: Investigar en audit_log
```

---

## 📈 MATRIZ DE PRIORIZACIÓN

### Características por Fase

```
┌──────────────┬─────────────────────┬─────────┬──────────┐
│ FEATURE      │ DESCRIPCIÓN         │ MVP     │ IMPACTO  │
├──────────────┼─────────────────────┼─────────┼──────────┤
│ Login        │ Auth básica          │ ✅ P0   │ 🔴 Alto  │
│ POS Venta    │ Flujo de venta       │ ✅ P0   │ 🔴 Alto  │
│ Inventario   │ Stock + búsqueda     │ ✅ P0   │ 🔴 Alto  │
│ Impresión    │ PT-210 térmica       │ ✅ P0   │ 🔴 Alto  │
│ Sincronización│ Local + Cloud       │ ✅ P0   │ 🔴 Alto  │
│ Comprobantes │ UBL 2.1 (sin SUNAT) │ ✅ P1   │ 🟡 Medio │
│ Auditoría    │ Logs de acciones     │ ✅ P1   │ 🟡 Medio │
│ Reportes     │ Cierre de caja       │ ⏳ P2   │ 🟢 Bajo  │
│ Devoluciones │ Notas de crédito     │ ❌ V2   │ 🟢 Bajo  │
│ Multi-user   │ Múltiples vendedores │ ❌ V2   │ 🟡 Medio │
│ Integraciones│ APIs externas        │ ❌ V3   │ 🟢 Bajo  │
└──────────────┴─────────────────────┴─────────┴──────────┘

P0 = Bloqueante (debe estar para MVP)
P1 = Importante (va en primera release)
P2 = Secundario (puede esperar)
V2 = Versión 2 (después de MVP)
V3 = Futuro lejano
```

---

## ✅ TESTING Y VALIDACIÓN

### Test Plan Ejecutable

```
┌──────────────────┬────────────────────────┬──────────┐
│ ÁREA             │ TEST                   │ CRITERIO │
├──────────────────┼────────────────────────┼──────────┤
│ AUTENTICACIÓN    │                        │          │
│                  │ Login con creds válidas│ ✓ Entra  │
│                  │ Login con pwd inválida │ ❌ Error │
│                  │ Token expirado         │ Refresh  │
│                  │ PIN admin offline      │ ✓ OK     │
│                  │ Biometría rechazada    │ Password │
│                  │                        │          │
│ POS              │                        │          │
│                  │ Búsqueda <200ms        │ Benchmark│
│                  │ Cambio precios válido  │ ✓ OK     │
│                  │ Descuento excesivo     │ Requiere │
│                  │                        │ PIN      │
│                  │ Venta sin conexión     │ ✓ Offline│
│                  │ Impresión fallida      │ Retry    │
│                  │                        │          │
│ INVENTARIO       │                        │          │
│                  │ Sync exitosa           │ ✓ OK     │
│                  │ Conflicto de stock     │ LastTS   │
│                  │ 1000+ productos       │ No ANR   │
│                  │ FTS5 search            │ <200ms   │
│                  │                        │          │
│ DATOS            │                        │          │
│                  │ Crash recovery         │ ACID ✓  │
│                  │ Venta sin pérdidas     │ ✓ OK     │
│                  │ Auditoría completa     │ Log OK   │
│                  │ DBcorrupción           │ Restore  │
│                  │                        │          │
│ PERFORMANCE      │                        │          │
│                  │ Cold start <3s         │ ✓ OK     │
│                  │ Scroll 60 FPS          │ Smooth   │
│                  │ Print <3s              │ ✓ OK     │
│                  │ Battery drain <5%/h    │ ✓ OK     │
└──────────────────┴────────────────────────┴──────────┘
```

### Escenarios E2E

```
Escenario 1: Flujo Completo Offline
─────────────────────────────────────
1. App abierta, WiFi OFF
2. Hac 10 ventas completas
3. Impresora funciona todo el tiempo
4. Stock disminuye correctamente
5. Documentos guardados en BD
6. ✓ Activar WiFi → Sync automática
7. Verificar en Supabase: 10 ventas + stock correcto

Escenario 2: Conflicto de Stock
─────────────────────────────────────
1. Caja A y Caja B con Producto X (stock=100)
2. Ambas sin WiFi
3. Caja A vende 30 unidades (stock_A = 70)
4. Caja B vende 50 unidades (stock_B = 50)  ← Error! Só había 20 más
5. Conectar A → Sube stock=70 ✓
6. Conectar B → Intenta subir stock=50
7. Servidor valida: 50 < 70 (anterior) → ACCEPT
8. Resultado: stock=50 en servidor ✓
9. App B recibe: "Conflicto resuelto, 20 unidades no se registraron"
10. Auditoría registra el conflicto

Escenario 3: Impresora Falla
─────────────────────────────────────
1. Venta exitosa en BD
2. Impresa enviado a PT-210
3. PT-210 no responde
4. UI muestra: "Ticket pendiente de impresión"
5. Vendedor presiona "Reintentar"
6. 2do intento: Éxito
7. ✓ Ticket impreso

Si 3er no responde (PT-210 sin batería):
8. UI muestra: "Guardar ticket en teléfono"
9. Vendedor presiona "Guardar"
10. Archivo ticket.txt guardado en /sdcard
11. ✓ Vendedor puede imprimirlo desde otro dispositivo

Escenario 4: Cambio de Precios
─────────────────────────────────────
1. Producto X: precio base = $50
2. Mayor de 3 unidades: mayorista = $40
3. Vendedor vende 2 unidades → $50 c/u ✓
4. Vendedor vende 5 unidades → $40 c/u ✓ (automático)
5. Vendedor quiere 5 unidades a $30 (especial)
   - Descuento: (50-30)/50 = 40%
   - Vendedor NO tiene permiso (máx 15%)
   - Sistema pide PIN admin
   - Admin ingresa PIN
   - ✓ Aprobado, registrado en auditoría

Escenario 5: Auditoría y Corrección
─────────────────────────────────────
1. Manager ve discrepancia en stock
2. Abre "Auditoría" para Producto X
3. Ve historial completo de cambios
4. Identifica: No se registró ingreso de 10 unidades
5. Presiona "Agregar corrección"
6. Registra: "Restock de provedor, 10 unidades"
7. Stock ajustado, auditoría registrada
8. Sync automática sincroniza a Supabase
```

---

## 💔 TRADE-OFFS Y SACRIFICIOS

### Qué SACRIFICAMOS para Simplificar y Llegar al MVP

```
┌─────────────────────────┬──────────────────┬──────────────────┐
│ FEATURE               │ POR QUÉ NO MVP   │ VERSIÓN          │
├─────────────────────────┼──────────────────┼──────────────────┤
│ Reader de tarjeta      │ Integración 3ros,│ V2 o nunca       │
│                        │ complejidad PCI  │ (Sugerir link    │
│                        │                  │  a servicio 3ro) │
│                        │                  │                  │
│ PDF preview tickets    │ Complejidad, no  │ V2 (si necesario)│
│                        │ agrega valor     │                  │
│                        │ (está ESC/POS)   │                  │
│                        │                  │                  │
│ OAuth (Google/Facebook)│ Incompatible con │ Nunca (mantener  │
│                        │ offline          │ simple: email +  │
│                        │                  │ pwd)             │
│                        │                  │                  │
│ Múltiples impresoras   │ Complejidad,     │ V2 (si cliente   │
│ simultáneas            │ caso raro        │ lo pide)         │
│                        │                  │                  │
│ Integración con SUNAT  │ PSE aún en       │ Post-MVP (Abril) │
│ (PSE)                  │ acreditación     │ + testing        │
│                        │                  │                  │
│ Dashboard web          │ Out-of-scope     │ V2 (Web app)     │
│ (admin panel)          │ (focus mobile)   │                  │
│                        │                  │                  │
│ Devoluciones/NC        │ Complejidad en   │ V1.1 o V2       │
│                        │ auditoría        │                  │
│                        │                  │                  │
│ Reportes avanzados     │ MVP es +90% casos│ V2 (dashboards)  │
│ (gráficos)             │ cubiertos        │                  │
│                        │                  │                  │
│ Retención de imágenes  │ Espacio en disk  │ Lazy-load en V2  │
│ de productos           │ (puede llenar    │                  │
│                        │ almacenamiento)  │                  │
│                        │                  │                  │
│ Geolocalización        │ Privacy concerns │ Optional (V2)    │
│                        │ + GPS overhead   │                  │
│                        │                  │                  │
│ Múltiples almacenes    │ Complejidad      │ V2 con multi-   │
│ / sucursales           │ multi-locación   │ location support │
│                        │                  │                  │
│ Integración proveedores│ APIs 3ros, sync  │ V3 (futura)      │
│                        │ compleja         │                  │
└─────────────────────────┴──────────────────┴──────────────────┘
```

### Qué SIMPLIFICAMOS

```
❌ ANTES (Overcomplicated)         → ✅ DESPUÉS (Simple)
───────────────────────────────────────────────────────────
Redux para state management        → Provider (más simple)
OAuth sign-in                      → Email + pwd
2FA obligatorio                    → Biometría opcional
Múltiples impresoras configurables → PT-210 hardcoded (MAC)
RLS complex permissions            → Simple user.rol
PDF rendering                      → ESC/POS directo
Database migrations automáticas    → Migraciones SQL manuales
Sync en tiempo real                → Sync cada 30s (suficiente)
Encriptación e2e (compleja)       → AES-256 (sencillo)
Machine learning para recomend..   → No (MVP NO lo necesita)
```

### Qué ASUMIMOS (Limitaciones)

```
ASUNCIÓN                                IMPLICACIÓN
─────────────────────────────────────────────────────────
1 caja por Samsung A36                  No multi-user local
                                        (pero sí múltiples A36)

WiFi ≥ 30s cada venta                   Sync incremental, no batch

Impresora PT-210 emparejida             Fallback a archivo de texto

SQLite < 500MB                          Limite de historial local
                                        (sincronizar para liberar)

Datos no clasificados                   Todo en app (sin roles 🔐)

Horario normal libería                  No 24/7 support
(9am-6pm)

NO es sistema ERP                       Solo POS + Inventario
                                        No cuentas, nómina, etc.
```

---

## 🚀 ROADMAP TÉCNICO

### Timeline Realista

```
FASE 1: MVP (Ahora - Abril 2026)
├── Semana 1-2: Estabilización + Testing
│   ├─ T1.1: Limpieza datos
│   ├─ T1.2: Conflict Resolution
│   ├─ T1.4: Encriptación
│   └─ Validación en Samsung A36
│
├── Semana 3-4: P0 Items
│   ├─ T1.3: SUNAT PSE (acreditación)
│   ├─ T1.5: Sync Incremental
│   └─ Testing exhaustivo
│
├── Semana 5-6: P1 Items
│   ├─ Auditoría gráficamente
│   ├─ Roles + Aprobaciones
│   ├─ Testing automatizado (70%)
│   └─ Documentación final
│
├── Semana 7-8: Launch
│   ├─ Performance tuning
│   ├─ Security audit
│   ├─ User training
│   └─ ✅ GO-LIVE
│
└── Abril 26: 🎉 MVP EN PRODUCCIÓN

FASE 2: V1.1 (Mayo-Junio 2026)
├── SUNAT PSE integrado (si aprobado)
├── Reportes avanzados
├── Devoluciones/Notas de Crédito
├── Performance optimization
└── Múltiples cajas en paralelo

FASE 3: V2.0 (Julio+ 2026)
├── Dashboard web (admin)
├── Integración proveedores (APIs)
├── Geolocalización (opcional)
├── Múltiples sucursales
└── Reporting avanzado (BI)
```

---

## ✅ CHECKLIST DE ACEPTACIÓN FINAL

Para que BiPenc sea considerado "LISTO PARA PRODUCCIÓN":

```
□ COMPILACIÓN
  □ 0 errores críticos
  □ Warnings < 100 (linting only)
  □ APK release compilado sin issues

□ FUNCIONALIDAD CORE
  □ Login funciona (email + pwd)
  □ Venta completa offline
  □ Impresión en PT-210 funciona
  □ Sincronización sin pérdida de datos
  □ Stock correctamente actualizados

□ RENDIMIENTO
  □ Búsqueda < 200ms
  □ Venta < 2 segundos
  □ Impresión < 3 segundos
  □ Scroll 60 FPS sin lag

□ SEGURIDAD
  □ Credenciales encriptadas
  □ Rate limiting en login
  □ Auditoría completa
  □ Validación de entrada

□ CONFIABILIDAD
  □ ACID transactions
  □ Crash recovery automática
  □ Offline-first garantizado
  □ 0 data loss en edge cases

□ TESTED
  □ 5+ escenarios E2E pasados
  □ Auditoría de stock consistente
  □ Conflictos resueltos correctamente
  □ Fallback de impresora funciona

□ DOCUMENTADO
  □ Este documento (Especificación)
  □ API Documentation
  □ User guide (Vendedores)
  □ Admin guide (Managers)

□ CAPACITADO
  □ Team sabe arquitectura
  □ Vendedores entrenados
  □ Managers pueden auditar
  □ Soporte disponible

□ SUNAT
  □ Estructura UBL 2.1 correcta
  □ PSE en roadmap (post-MVP)
  □ Boletas son legales localmente
  
□ HARDWARE
  □ Funciona en Samsung A36
  □ PT-210 emparejada
  □ Batería: <5% por hora
  □ Storage: <200MB usado

SI TODAS LAS CASILLAS ✅ → PASAR A PRODUCCIÓN
SI ALGUNA ❌: → VOLVER A DESARROLLO
```

---

## 📝 CONTRATO TÉCNICO FINAL

**Este documento es el contrato técnico entre:**
- El equipo de desarrollo
- Los usuarios (vendedores/managers)
- El negocio (dueño de librería)

**Promesas:**
1. ✅ BiPenc hará que la venta sea RÁPIDA (< 2 minutos por transacción)
2. ✅ BiPenc hará que los datos sean SEGUROS (encriptados, auditados)
3. ✅ BiPenc hará que el inventario sea CONSISTENTE (conflictos resueltos)
4. ✅ BiPenc funcionará OFFLINE (sin WiFi es 100% funcional)
5. ✅ BiPenc imprimirá SIEMPRE (buffer + fallback)

**Si algo falla → Seguir las soluciones en "Manejo de Errores"**
**Si algo no está documentado → Escalaciones a Architect**

---

**Fecha:** 8 de Marzo de 2026  
**Versión:** 2.0 (MVP Edition)  
**Próxima Revisión:** Post-MVP (Mayo 2026)  
**Estado:** ✅ APROBADO PARA DESARROLLO

---

*Este documento es la "Biblia" de BiPenc. Cualquier cambio debe ser debatido y documentado here.*

*¿Preguntas o cambios? → Editar esta sección abajo*

### CHANGE LOG
```
2026-03-08: Versión 2.0 inicial (Mentor + Architect review) ✅
```
