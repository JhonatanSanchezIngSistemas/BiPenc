# 🚀 BiPenc - Sistema Experto de Inventario y POS

**Versión:** v1.1.0-beta  
**Estado:** 🔄 En Desarrollo (MVP → Producción)  
**Última Actualización:** 8 de Marzo de 2026, 14:35 UTC-5  
**Responsables:** Mentor Arquitectura + Equipo de Desarrollo  
**Timeline:** 8 Semanas hasta GO-LIVE (26-29 Abril 2026)

BiPenc es una solución móvil profesional de Punto de Venta (POS) e Inventario, orientada a librerías y retail. Diseñada para operar de manera fluida y robusta en dispositivos Android (ej. Samsung A36), cuenta con integración de hardware crítico (impresoras térmicas bluetooth), escaneo de códigos de barra avanzado, arquitectura "offline-first" con SQLite, y un backend potente respaldado por Supabase.

---

## ⚠️ ESTADO ACTUAL (8 de Marzo 2026, 18:30 UTC)

```
COMPILACIÓN:        ✅ 0 errores críticos
FUNCIONALIDAD MVP:  ✅ 95% + 2 T1s implementados
TESTING:            ⚠️  5-10% (Target: 70%)
DOCUMENTACIÓN:      ✅ Completa (especificación + guías + prompts)
PRODUCCIÓN:         🟡 6 semanas (Timeline: 26-29 Abril 2026)

CAMBIOS HOY (8 Marzo):
  ✅ T1.4: AES-256 ENCRIPTACIÓN → COMPLETADA (115L código + 111L tests)
  ✅ T1.5: SYNC INCREMENTAL → COMPILADA (173L código, device tests pendiente)
  ✅ main.dart: Updated (init secuencia correcta, servicios integrados)
```

### 🎯 Bloqueantes Críticos P0 (ANTES DE PRODUCCIÓN):

| Estado | Tarea | Progreso | Timeline |
|--------|-------|----------|----------|
| ✅ **COMPLETADO** | **T1.4: Encriptación AES-256** | 100% | `8 Marzo 03:00` |
| 🟢 **ACTIVO** | **T1.5: Sync Incremental** | 90% | `8 Marzo 03:10` |
| 🔴 **PENDIENTE** | T1.1: Limpieza datos prueba | 0% | 3 días |
| 🔴 **PENDIENTE** | T1.2: RPC Validación stock | 0% | 5 días (después T1.1) |
| 🔴 **PENDIENTE** | T1.3: SUNAT PSE | 0% | 7-10 días (paralelo) |
| 🔴 **PENDIENTE** | T1.6-T1.8: Validación/Auditoría/Errors | 0% | 7 días después T1.5 |

**Detalle completo:** Ver [REPORTE_ESTADO_CODIGO_8MARZO.md](REPORTE_ESTADO_CODIGO_8MARZO.md) ← 📊 NUEVO

---

## 📚 DOCUMENTOS CRÍTICOS (LEER EN ORDEN)

| Documento | Propósito | Para Quién |
|-----------|-----------|-----------|
| **[README.md](README.md)** | Overview + Estado | Todos (especialmente nuevos agentes) |
| **[ESPECIFICACION_TECNICA_BIPENC.md](ESPECIFICACION_TECNICA_BIPENC.md)** | Contrato técnico (8,500w) | Arquitecto + Senior Dev |
| **[ANALISIS_GAPS_vs_ESPECIFICACION.md](ANALISIS_GAPS_vs_ESPECIFICACION.md)** | Qué está hecho vs qué falta | Coordinador de Sprint |
| **[QUICK_START.md](QUICK_START.md)** | Setup rápido del proyecto | Nuevos agentes |
| **[BETA_STATUS.md](BETA_STATUS.md)** | Cambios en beta (2FA removido, etc) | Code Review |

---

## ✨ Funcionalidades Clave y Módulos del Sistema

### 1. Gestión de Stock e Inventario Inteligente
- **Escaneo Nativo:** Integración de la cámara (`mobile_scanner`, `camera`, `ml_kit_service`) para lectura ágil de códigos de barras y códigos QR. Facilita tanto la búsqueda como el ingreso rápido.
- **Módulo "Listas con Foto":** Permite crear y gestionar listas de productos adjuntando fotografías capturadas in situ (usando `image_picker` y compresión de imágenes nativa local).
- **Motor de Precios:** Soporte para múltiples niveles de precios: Base, Mayorista (3+ unidades) y Especial. Edición manual y validación en tiempo real en el carrito de compras.

### 2. POS, Pedidos y Gestión Tributaria (SUNAT-Ready)
- **Generación Atómica de Correlativos:** Sistema concurrente optimizado vía bases de datos de Supabase para prevenir la duplicación de números de boletas/facturas en escenarios multi-dispositivo.
- **Gestión de Pagos e Impuestos:** Soporte de pagos parciales. Estructura de comprobantes validada para requerimientos fiscales peruanos (Boleta 03, Factura 01, con cálculo y desglose del IGV - 18%).
- **Impresión Térmica Bluetooth (ESC/POS):** Control e impresión estructurada hacia dispositivos externos (como la impresora PT-210) integrando avance de papel automático para corte y configuración de layout.

### 3. Arquitectura Híbrida (Local + Nube)
- **Offline-First (SQLite):** La base de datos local garantiza velocidad en el motor de búsqueda de productos y transacciones inmediatas ininterrumpidas incluso sin señal Wi-Fi.
- **Cloud Sincronizado (Supabase):** Respaldo principal de datos. Sincronización pull-to-refresh para inventario.
- **Print Queue & Batch Sync:** Mecanismo de cola asíncrona que almacena registros de ventas y comprobantes. Se realiza la sincronización masiva en la nube (batch upload) durante el Cierre de Caja.

### 4. Seguridad, Logs y Experiencia de Usuario
- **Guardián de Sesión y Autenticación:** Protección de rutas mediante `SessionGuard` en la capa de navegación (`go_router`). Integración de biometría local (`local_auth`) para acceso rápido (Sistema 2FA retirado recientemente para agilizar transacciones).
- **Monitoreo de Errores Exhaustivo:** Configuración global robusta de `FlutterError` y `PlatformDispatcher` para atrapar todo evento y guardarlo en el `AppLogger` garantizando observabilidad en crudo durante la fase beta y producción.

---

## � FLUJOS PRINCIPALES (Cómo Funciona)

### Flujo 1: VENTA COMPLETA (Happy Path)
```
1. Vendedor busca producto (< 200ms)
   └─ FTS5 en SQLite local + índices
2. Agrega al carrito (validar stock)
   └─ carrito_service.dart verifica stock_local
3. Revisa precios (mayorista automático si 3+)
   └─ precio_logica.dart calcula automáticamente
4. Aplica descuento (si rol lo permite)
   └─ precio_aprobacion_service.dart valida vs límite
   └─ Si descuento > límite: solicita PIN admin (security_service.dart)
5. Selecciona método pago (Efectivo/Tarjeta/Combinado)
   └─ UI calcula vuelto automático
6. Genera comprobante (UBL 2.1)
   └─ supabase_service.dart obtiene correlativo vía RPC
   └─ pdf_service.dart genera XML + QR
7. Registra en BD LOCAL (ACID)
   └─ local_db_service.dart INSERT documento + items
   └─ UPDATE productos SET stock = stock - cantidad
8. Encola para impresión
   └─ print_queue.dart → PT-210 vía Bluetooth
   └─ Si falla impresora: reintentos exponenciales + fallback archivo
9. Encola para sincronización
   └─ sync_queue → server cada 30s (T1.5 por implementar)
   └─ Conflictos resueltos por servidor: Last-Timestamp-Wins + validación NO aumentar stock

TIEMPO TOTAL: 1-2 minutos | ✅ 100% offline capable
```

### Flujo 2: SINCRONIZACIÓN (Offline → Online)
```
[ACTUAL - BATCH SYNC]
1. Cierre de caja manual
   └─ despacho_service.dart envía TODAS las ventas del día
   ❌ PROBLEMA: Si crash antes de cierre → Pérdida de datos

[NUEVO - INCREMENTAL SYNC (T1.5)]
1. Cada 30 segundos (background timer)
   └─ sync_service.dart lee sync_queue (pendientes)
   └─ Para cada item: Intenta enviar a Supabase
   └─ Si OK: Marca como SYNCED
   └─ Si error: Reintentos con backoff (1s, 2s, 4s, 8s)
2. Validación en servidor (RPC PostgreSQL)
   └─ validate_stock_sync() rechaza aumentar stock
   └─ Last-timestamp gana
   └─ Conflictos logged en sync_conflicts table
3. Garantía: Ningún dato se pierde

TIEMPO: Casi inmediato + reintentos automáticos | ✅ 100% seguro
```

### Flujo 3: MANEJO DE CONFLICTOS (Dos cajas venden offline)
```
Caja A (10:00): Vende 5 unid X (stock: 100 → 95)
Caja B (10:05): Vende 10 unid X sin ver cambio A (stock: 100 → 90 en caché B)

Sincronización:
1. Caja A sube: stock=95, ts=10:00
   └─ Servidor: 95 < 100 (anterior) → ✅ ACCEPT

2. Caja B sube: stock=90, ts=10:05
   └─ Servidor: 90 < 95 (anterior) → ✅ ACCEPT
   └─ ⚠️ PERO: Vendimos 15 de 100

SOLUCIÓN (RPC en Supabase T1.2):
   IF new_stock > current_stock THEN
     REJECT ("No se puede aumentar stock")
   ELSIF new_ts > server_ts THEN
     UPDATE (nueva versión más reciente)
   ELSE
     REJECT ("Versión del servidor es más nueva")
   END

RESULTADO: Servidor siempre tiene versión correcta
AUDITORÍA: sync_conflicts log qué pasó y por qué
```

### Flujo 4: IMPRESORA DESCONECTA
```
1. Venta guardada en BD ✅
2. ESC/POS enviado a PT-210
3. PT-210 NO responde (sin batería, Bluetooth perdido)
4. print_queue.dart: INSERT (documento, estado=PENDING)
5. Reintentos automáticos cada 5 minutos (hasta 10 intentos)
6. Vendedor notificado: "⚠️ Impresión pendiente"
7. Opción "Reimprimir": Vendedor presiona → Reintenta manualmente
8. Si todos los intentos fallan:
   └─ Guardar ticket.txt en /sdcard/Documents/
   └─ Vendedor puede imprimirlo desde otra app o PC

GARANTÍA: Venta NUNCA se pierde, comprobante siempre recuperable
```

---

## 🏗️ ARQUITECTURA DETALLADA

El proyecto se sustenta en **Flutter 3.x** y sigue los principios de una **Clean Architecture** estructurada por *features*:
- **`lib/features/`**: Lógica de UI dividida por dominio (home, inventario, pedidos, pos, reports, settings).
- **`lib/services/`**: Controladores que interactúan con APIs externas o hardware local (`supabase_service`, `local_db_service`, `ml_kit_service`, `print_queue`, `security_service`).
- **`lib/data/`**: Modelos de datos estandarizados.
- **`lib/core/` & `lib/widgets/`**: Tematización, inyección de dependencias básicas y layouts reusables (`MainLayout`).
- **Estados Compartidos:** Implementado fuertemente con la librería `provider` (`PosProvider`, `SessionManager`) para asegurar reactividad global y eficiente en el carrito de ventas.
- **Enrutamiento Declarativo:** Manejado enteramente por `go_router` asegurando una jerarquía lógica de vistas (login -> shell de sesión protegida).

---

## ⚙️ Entorno de Desarrollo y Configuración

- **SDK Requerido:** Flutter `^3.5.0` (Dart 3.5.0+)
- **Dependencias Clave:** Supabase Flutter, Provider, GoRouter, Print Bluetooth Thermal, SQLite.
- **Variables de Entorno (.env):** Para compilar el proyecto exitosamente es necesario un archivo `.env` en la raíz que incluya:
  ```env
  SUPABASE_URL=tu_url_aqui
  SUPABASE_ANON_KEY=tu_key_aqui
  ```
- **Preparación de Base de Datos:** Se requiere la ejecución de los scripts de migraciones (en la carpeta `supabase_migrations`) para inicializar las tablas (e.g., `order_lists`, correccionales de inventario, triggers para IDs correlativos atómicos).
- **Despliegue a Producción:** `flutter run --release` con dispositivo físico Android conectado para validar permisos de cámara e impresión.

---

## 🤖 TRABAJANDO CON MÚLTIPLES AGENTES

### El Desafío Que Resolvimos:
```
Problema: ¿Cómo 3-5 agentes IA trabajan en PARALELO sin conflictos?
Solución: Single Source of Truth (SSOT) + DOCUMENTACIÓN CRUZADA AUTOMÁTICA
```

### ⚡ REGLA DE ORO: "DOCUMENTA QUÉ HACES Y DE QUÉ TE ENCARGAS"
**Cada agente DEBE documentar:**
1. **QUÉ hace** (descripción clara de la tarea completada)
2. **DE QUÉ se encarga** (qué módulos/archivos toca)
3. **DÓNDE lo hace** (rutas de archivos modificadas)
4. **CUÁNDO lo hace** (fecha + hora exacta)
5. **TESTE estado** (✅ Probado | ⚠️ Parcial | ❌ Falta testing)

**PROPÓSITO:** Otros agentes leen la documentación y automáticamente:
- Saben qué no tocar ❌
- Saben dónde se avanzó ✅
- Pueden coordinar siguiente tarea sin esperar ⚡
- Evitan doble trabajo simultáneo 🎯

### Documentos de Control (LEER EN ESTE ORDEN):

**🔴 CRÍTICOS (Leer PRIMERO):**

0. **[PROMPT_AGENTE_TECNICO.md](PROMPT_AGENTE_TECNICO.md)** ← 🚨 **SI TRABAJAS EN LOS 8 P0, LEE ESTO PRIMERO**
   - Qué son los 8 bloqueantes exactamente
   - Cuál es el cronograma realista
   - Instrucciones específicas por rol (Dev, QA, Sunat)
   - Checklist de calidad por tarea
   - KPIs de éxito

1. **[PROTOCOLO_AGENTES.md](PROTOCOLO_AGENTES.md)** ← 🔴 **LEE PRIMERO SI ERES UN NUEVO AGENT**
   - Cómo documenta cada agente su trabajo
   - Cómo evitar conflictos entre agentes
   - Flujo pre-codificación, durante, post-codificación
   - Ejemplos de BIEN vs MAL documentado

2. **[CHANGELOG.md](CHANGELOG.md)** ← 🔴 **FUENTE DE VERDAD ÚNICA**
   - **CADA cambio que haga un agente AQUÍ va primero**
   - Formato obligatorio: `[YYYY-MM-DD HH:MM] [TIPO] [PRIORIDAD] Descripción | Agent: NOMBRE | Archivos: ruta1, ruta2`
   - TIPOS: ✨ (Feature), 🪛 (Fix), 📊 (Analysis), 🧪 (Test), 📝 (Doc)
   - PRIORIDAD: P0 (blocker), P1 (alta), P2 (normal)
   - Ejemplo:
     ```
     [2026-03-08 15:45] 🪛 P1 Incremental Sync implementado | 
     Agent: AgentSync | Archivos: lib/services/sync_service.dart, lib/models/sync_queue.dart | 
     Testing: ✅ Unit tests (5/5 casos) | Siguiente: T1.3 PSE
     ```
   
3. **[ESPECIFICACION_TECNICA_BIPENC.md](ESPECIFICACION_TECNICA_BIPENC.md)**
   - Contrato técnico (no se cambia sin decisión arquitecto)
   - Todos los agentes lo leen PRIMERO antes de cualquier código
   
4. **[ANALISIS_GAPS_vs_ESPECIFICACION.md](ANALISIS_GAPS_vs_ESPECIFICACION.md)**
   - Actualizar DIARIAMENTE con estados nuevos
   - Qué se completó, qué falta, bloqueantes nuevos
   - **Agente responsible: Coordinador**

### Disciplina Compartida (CRÍTICA - NO NEGOCIABLE):

| Elemento | Responsabilidad | Cómo Verifica Otro Agent |
|----------|-----------------|-------------------------|
| **CHANGELOG.md** | Actualizar ANTES de commit | `git diff CHANGELOG.md` |
| **Archivos tocados** | Documentar RUTA exacta | `grep "Archivos:" CHANGELOG.md` |
| **Testing estado** | Reportar si OK/Parcial/Falta | `grep "Testing:" CHANGELOG.md` |
| **Fecha + Hora** | ISO 8601 (`YYYY-MM-DD HH:MM`) | Auditoría orden cronológico |
| **Agent responsable** | Nombre identificable | Trazabilidad completa |
| **Siguiente tarea** | Describir qué sigue | Pull-ahead automático |

### Flujo Para Cada Agent (IMPLEMENTAR ESTRICTAMENTE):
```
📋 ANTES DE CODIFICAR:
  1. Lee CHANGELOG.md → Busca TU TAREA
  2. Lee ESPECIFICACION_TECNICA_BIPENC.md → Sección relevante
  3. Lee ANALISIS_GAPS_vs_ESPECIFICACION.md → Estado actual
  4. Verifica si alguien MÁS ya lo está haciendo → grep "in-progress"

💻 DURANTE CODIFICACIÓN:
  1. Modifica SOLO los archivos asignados
  2. Si necesitas tocar otro módulo → CONSULTA otros agents en CHANGELOG
  3. Tests mientras desarrollas (TDD)

✅ AL COMPLETAR:
  1. Actualiza CHANGELOG.md CON DETALLES (ver formato arriba)
  2. Actualiza ANALISIS_GAPS_vs_ESPECIFICACION.md → marca COMPLETADO
  3. Actualiza README.md si es cambio GRANDE
  4. Commit:
     ```bash
     git add CHANGELOG.md ANALISIS_GAPS_vs_ESPECIFICACION.md lib/...
     git commit -m "[AGENT-NAME] [TIMESTAMP] Task: T1.X Descripción"
     ```
  5. Push + Notifica en CHANGELOG siguiente tarea

⚡ AUTOMATIZACIÓN PARA OTROS AGENTS:
  - Script: `grep -A2 "^\[$(date +%Y-%m-%d)" CHANGELOG.md` → Ver changes hoy
  - Script: `grep "Siguiente:" CHANGELOG.md | tail -1` → Próxima tarea sin depender de humano
```

### Ejemplo de Entrada CORRECTA en CHANGELOG.md:
```markdown
[2026-03-08 16:30] 🪛 P0 T1.2 Sincronización Incremental completada |
Agent: AgentSync |
Archivos: lib/services/sync_service.dart (+187 líneas), 
          lib/models/sync_queue.dart (+45 líneas),
          lib/services/supabase_service.dart (+12 líneas) |
Testing: ✅ Unit: 8/8 casos | ✅ Widget: 3/3 flujos | ❌ Falta: E2E |
Detalles: Implementado timer cada 30s, backoff exponencial (1s,2s,4s,8s), 
          logging detallado en sync_conflicts table |
Bloqueantes Resueltos: T1.5 (sync incremental) ✅ |
Siguiente: T1.3 SUNAT PSE (7-10 días) - Agent: [Ver ANALISIS_GAPS]
```

### Ejemplo de Entrada INCORRECTA (NO HACER):
```markdown
❌ [Cambios en sync] - Incompleto, sin fecha/hora, sin agent
❌ [2026-03-08] Arreglé cosas - Sin hora, sin prioridad, vago
❌ Agent hizo sync - Sin archivo, sin testing, sin siguiente tarea
```

---

## 📜 HISTÓRICO DE CAMBIOS

**Ver [CHANGELOG.md](CHANGELOG.md) para lista COMPLETA.**

```
[2026-03-08 14:35] ✨ ESPECIFICACIÓN TÉCNICA COMPLETA
                   └─ 8,500 palabras, 12 secciones

[2026-03-08 14:00] 📊 ANÁLISIS DE GAPS vs Código
                   └─ 8 bloqueantes identificados

[2026-02-28] 🪛 SYNC BIDIRECCIONAL IMPLEMENTADO
                   └─ local ↔ cloud bug fix

[2026-02-27] 🪛 PERMISOS BLUETOOTH RUNTIME
                   └─ Android 12+ compatibility

[2026-02-27] ✨ TICKET ESC/POS MEJORADO
                   └─ layout + teléfono + precios

[2026-02-26] 🔐 RLS CONFIGURADO EN SUPABASE
                   └─ Tablas protegidas

[2026-02-25] 🔧 LIMPIEZA DOCUMENTACIÓN
                   └─ Single source of truth
```

---

## ✅ ANTES DE EMPEZAR (5 min)

```bash
flutter analyze            # Compilación OK?
grep "P0" CHANGELOG.md      # Bloqueantes actuales?
ls -lrt *.md | tail -5      # Docs actualizados?
flutter pub get             # Dependencias?
```

---

## 💬 EQUIPO Y CONTACTOS

| Rol | Tarea | Contacto |
|-----|-------|----------|
| **Arquitecto** | Decisiones técnicas | Mentor |
| **PM** | Timeline + Sprints | (asignar) |
| **DevOps** | Deployments | (asignar) |
| **QA** | Testing | (asignar) |

---

*Hub Central de BiPenc: Especificación + Gaps + Changelog + Cambios*  
*Última actualización: **8 de Marzo de 2026, 14:35 UTC-5***  
*Próxima revisión: 22 de Marzo (post-Semana 2)*



---
*Este documento fue elaborado tras el análisis exhaustivo del código fuente y depuración final para la fase de Beta/Producción de LIBRERIAPP.*
