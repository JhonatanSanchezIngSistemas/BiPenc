# 💎 BiPenc Diamond Edition

<div align="center">
  <img src="https://raw.githubusercontent.com/username/bipenc/main/assets/readme_hero.png" alt="BiPenc Hero" width="800"/>
  <br/>
  <p align="center">
    <b>Sistema POS de Alto Rendimiento con Gestión de Pedidos por Imagen y OCR</b>
    <br/>
    <i>"La evolución definitiva de la gestión de librerías y comercios minoristas."</i>
  </p>
</div>

---

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.19.0-blue.svg?style=for-the-badge&logo=flutter" alt="Flutter"/>
  <img src="https://img.shields.io/badge/Dart-3.3.0-0175C2.svg?style=for-the-badge&logo=dart" alt="Dart"/>
  <img src="https://img.shields.io/badge/Supabase-Backend-3ECF8E.svg?style=for-the-badge&logo=supabase" alt="Supabase"/>
  <img src="https://img.shields.io/badge/Diamond-Edition-FFD700.svg?style=for-the-badge" alt="Edition"/>
</p>

## 🚀 Vision General

**BiPenc Diamond Edition** es un ecosistema diseñado para digitalizar el caos de las listas de pedidos manuales. Utilizando algoritmos de procesamiento de imagen avanzados y OCR (Reconocimiento Óptico de Caracteres), BiPenc permite a los operarios capturar pedidos en papel y vincularlos instantáneamente a un inventario inteligente en la nube.

### 🌟 Pilares "Diamond"

- **📸 Digitalización Inteligente:** Captura listas de pedidos, aplica filtros de contraste y extrae texto para agilizar el POS.
- **🛡️ Gobernanza Operativa:** Control de roles (RBAC) donde solo el Administrador puede realizar operaciones críticas de precios y eliminaciones.
- **💼 Identidad Corporativa:** Gestión centralizada de RUC, Razón Social y Logos para comprobantes profesionales.
- **📑 Reporting Analítico:** Cierres de caja automáticos con exportación a WhatsApp y PDF de alta calidad.
- **🌑 Obsidian Design:** Interfaz Glassmorphism optimizada para entornos de alta productividad y fatiga visual reducida.

---

## 🏗️ Arquitectura del Sistema

El proyecto sigue un patrón **Clean Architecture** segmentado por módulos funcionales:

```bash
lib/
├── datos/              # Modelos y DTOs persistentes
├── servicios/          # Lógica de negocio y comunicación (Supabase, PDF, OCR)
├── utilidades/         # Helpers transversales (Fiscal, Imagen, Logs)
├── ui/                 # Componentes globales y temas Obsidian
└── modulos/            # Funcionalidades aisladas
    ├── administracion/ # Dashboard Admin y Cierre de Caja
    ├── caja/           # Punto de Venta (POS)
    ├── inventario/     # Gestión de 1000+ SKUs
    └── pedidos/        # Listas por imagen y seguimiento
```

---

## 🛠️ Stack Tecnológico

| Área | Tecnología |
| :--- | :--- |
| **Framework** | Flutter (Multiplatform: Android, Linux Desktop) |
| **Base de Datos** | Supabase (PostgreSQL) + SQLite (Local Cache) |
| **Autenticación** | Supabase Auth (Invites & Roles) |
| **Procesamiento** | Google ML Kit (OCR) + Custom Image Filters |
| **Reportes** | PDF Widgets + Share Plus |

---

## 🗺️ Roadmap de Implementación

- [x] **v1.0.0:** Foundation (Supabase Sync & POS).
- [x] **v1.1.0:** Diamond UI (Glassmorphism & Drawer).
- [x] **v1.2.0:** Gobernanza Administrativa & Perfil de Negocio.
- [ ] **v1.3.0:** Facturación Electrónica Nativa (OSE Integration).
- [ ] **v1.4.0:** Analítica de Ventas con IA (Predicción de Stock).

---

## 🔧 Instalación y Desarrollo

1. Clonar el repositorio.
2. Configurar el archivo `.env` con `SUPABASE_URL` y `SUPABASE_ANON_KEY`.
3. Ejecutar `flutter pub get`.
4. Ejecutar el proyecto:
   ```bash
   flutter run -d linux # Para Desktop
   flutter run -d [device_id] # Para Android
   ```

---

<div align="center">
  <sub>Desarrollado con ❤️ por <b>Jhonatan Sanchez</b> - Arquitecto de Software & Ing. de Sistemas</sub><br/>
  <sub><b>Versión Actual:</b> 1.2.0 | <b>Última Actualización:</b> Marzo 2026</sub>
</div>
