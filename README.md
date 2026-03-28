# 🚀 BiPenc - Sistema Experto de Inventario y POS (Offline-First)

---
![Banner](https://img.shields.io/badge/Status-Productor_Beta-brightgreen)
![Tech](https://img.shields.io/badge/Stack-Flutter_%7C_Supabase_%7C_SQLite-blue)
![Security](https://img.shields.io/badge/Security-PII_Encyption_%7C_Blind_Index-red)
![ISO](https://img.shields.io/badge/Compliance-ISO_25010_%7C_27001-orange)

**BiPenc** es una solución robusta de punto de venta (POS) y gestión de inventarios diseñada para operar en condiciones críticas de conectividad. Ideal para el sector retail (librerías, bodegas, tiendas especializadas), combina la agilidad de una base de datos local con la potencia de sincronización en la nube.

---

## 🏗️ Arquitectura del Sistema: "Offline-First"

La arquitectura se basa en la **continuidad operativa total**. El usuario nunca se detiene, incluso si el internet falla.

```mermaid
graph TD
    UI[Interfaz de Usuario (Flutter)] -->|Escribe| SQL[Repositorio Local (SQLite)]
    SQL -->|Encola| SQ[Sync Queue V2]
    SQ -->|Procesa / Reintenta| SB[Servicio Backend (Supabase)]
    SB -->|Almacena| DB[(PostgreSQL Cloud)]
    
    SB -.->|Sync Incremental| SQL
```

### Componentes Clave:
- **Capa Local (SQLite)**: Persistencia inmediata para ventas, inventario y correlativos.
- **Cola de Sincronización (Sync Queue)**: Motor de reintentos asíncrono con manejo de conflictos.
- **Sincronización Incremental**: Descarga solo cambios (deltas) de productos cada 24h para optimizar datos.

---

## 🛡️ Seguridad y Protección de Datos (PII)

BiPenc está diseñado con principios de **Security by Design** para cumplir con estándares de privacidad:

1.  **Blind Indexing (HMAC-SHA256)**: Los documentos sensibles (DNI/RUC) se almacenan como hashes no reversibles. Esto permite búsquedas rápidas sin exponer el dato original en texto plano.
2.  **Cifrado AES-256**: Los datos de clientes (Nombres, Direcciones) se cifran localmente antes de guardarse en SQLite.
3.  **Row Level Security (RLS)**: En Supabase, cada tabla está protegida por políticas que aseguran que los usuarios solo accedan a lo que les pertenece.
4.  **Secure Storage**: Las llaves criptográficas se guardan en el Keystore (Android) o Keychain (iOS).

---

## 🛠️ Servicios Core "Enormes"

### 📋 Sincronización Inteligente (`ServicioSincronizacion`)
- **Atomicidad**: Usa RPCs (`insert_venta_with_items`) para asegurar que una venta y sus productos suban como una sola unidad.
- **Compatibilidad**: Motor de "Waterfall" que detecta cambios de esquema en el servidor y reintenta envíos con campos de fallback (ej: `dni_cliente` -> `dni_ruc`).

### 🖨️ Impresión Térmica Profesional (`ServicioImpresion`)
- **Hardware**: Optimizado para impresoras **PT-210** (58mm/80mm) vía Bluetooth.
- **Gráficos**: Incluye un motor de **Dithering Floyd-Steinberg** manual para convertir logos de color a blanco y negro puro sin pérdida de detalle.
- **Cola de Impresión**: Si la impresora se apaga, el ticket se encola y se imprime automáticamente al reconectar.

### 📸 Visión Artificial y OCR (`ServicioMLKit`)
- **Document Scanning**: Uso de `google_mlkit_document_scanner` para detección de bordes y auto-recorte.
- **Limpieza de Imagen**: Algoritmos de binarización y corrección de perspectiva para fotos de listas de útiles.
- **OCR Local**: Reconocimiento de texto en el dispositivo, sin enviar datos a la nube.

### 💰 Pagos Digitales (`ServicioYape`)
- **Listener Silencioso**: Escucha notificaciones de entrada de Yape/Plin para confirmar pagos en tiempo real sin salir de la pantalla de caja.

---

## 📂 Organización del Proyecto (Roots)

```text
lib/
├── base/                # Temas, estilos y llaves globales.
├── datos/
│   ├── modelos/         # Entidades: Producto, Venta, Cliente, Pedido.
│   └── logica/          # Business logic pura (cálculos fiscales, precios).
├── modulos/             # UI por Dominio Funcional
│   ├── caja/            # Punto de Venta, Gestión de Carrito, Descuentos.
│   ├── inventario/      # Catálogo, Stock, Categorías, Búsqueda Local.
│   ├── pedidos/         # Gestión de Listas, Fotos y OCR.
│   └── reportes/        # Cierres de caja, Historial de ventas (Z-Reports).
├── servicios/           # Corazón técnico
│   ├── db_local/        # Migraciones SQLite y Repositorios.
│   └── supabase/        # Conectividad remota y RPCs.
├── ui/                  # Widgets y Modales compartidos.
└── utilidades/          # Loggers, Formateadores fiscales e internacionalización.
```

---

## ⚙️ Variables de Entorno y Configuración

El archivo `.env` controla el comportamiento de la app:
- `SUPABASE_URL`: Endpoint de base de datos.
- `OTA_STRICT`: Habilita verificación de SHA256 antes de actualizar la APK.
- `OTA_ALLOWLIST`: Dominios permitidos para descargas externas.
- `DOCUMENT_CACHE_SHARED`: Permite compartir el cache de DNI/RUC entre dispositivos.

---

## 🚀 Requerimientos y Cumplimiento

### Requisitos de Hardware
- Android 7.0 (API 24) o superior.
- Impresora Térmica Bluetooth (ESC/POS).
- Cámara con Auto-foco (mínimo 8MP para OCR).

### Estándares de Calidad
- **ISO/IEC 25010**: Enfoque en Adecuación Funcional y Capacidad de Recuperación (Offline).
- **ISO/IEC 27001**: Controles de acceso, cifrado y auditoría.
- **ISO/IEC 27701**: Gestión de privacidad de datos personales.

---

## 📝 Roadmap
- [ ] Integración directa con Facturación Electrónica SUNAT (PSE/OSE).
- [ ] Exportación de reportes a Excel/PDF avanzado.
- [ ] Dashboard de analítica predictiva de stock.

---
**Desarrollado por Jhonatan (Ingeniero de Sistemas) - BiPenc Team 2026**
