# 🚀 BiPenc - Sistema de Gestión de Ventas

BiPenc es una aplicación móvil moderna desarrollada con **Flutter** orientada a la seguridad, rapidez en ventas y flexibilidad de precios. Diseñada con una estética **Premium Dark** y optimizada para dispositivos Android de última generación.

---

## ✨ Características Principales

### 1. Seguridad Avanzada
- **Acceso Biométrico**: Autenticación nativa por huella digital con indicador visual de halo dinámico (Teal Glow).
- **Respaldo por PIN**: Sistema de contingencia mediante código numérico para asegurar el acceso en cualquier situación.

### 2. Módulo de Ventas Inteligente
- **Búsqueda Dinámica**: Búsqueda en tiempo real (mín. 3 caracteres) con agrupación automática por marcas.
- **Catálogo Organizado**: Navegación fluida con encabezados fijos (Sticky Headers) para una mejor organización visual de marcas como Scribe, Stanford, etc.

### 3. Carrito de Compras Flexible
- **Precio Amigo**: Capacidad de editar precios manualmente en tiempo real con validación visual (precio original tachado en rojo y nuevo precio en verde esmeralda).
- **Modo Mayorista**: Interruptor rápido para aplicar tarifas por volumen.
- **Resumen de Ahorro**: Visualización clara del ahorro total acumulado para incentivar la venta.
- **Finalización de Venta**: Soporte para emisión de Boleta Simple o Factura (con ingreso de DNI/RUC).

---

## 🛠️ Stack Tecnológico
- **Framework**: Flutter (Canal Stable)
- **Lenguaje**: Dart
- **UI/UX**: Material 3, Dark Mode, Google Fonts (Inter)
- **Seguridad**: local_auth v3

---

## 💻 Desarrollo y Configuración (Fedora Linux)
Para replicar el entorno de desarrollo en Fedora 43 (Rawhide/Workstation):

### Requisitos del Sistema
- **Java**: Java 21 (LTS). Es crítico evitar Java 25 para compatibilidad con Gradle.
- **Android SDK**: API 36 (Android 16) con Build-tools 36.0.0.
- **UDEV Rules**: Reglas configuradas para reconocimiento de dispositivos Samsung/Android vía USB.

### Comandos de Instalación Rápidos
```bash
# Configurar Java 21
sudo dnf install -y java-21-openjdk-devel
sudo alternatives --config java

# Ejecutar aplicación
flutter run -d [DEVICE_ID]
```

---

## 📅 Resumen de Avances Significativos
1. **Semana 1**: Configuración de infraestructura en Fedora y vinculación de dispositivos físicos.
2. **Semana 2**: Implementación del núcleo de seguridad biometríca y estructura de base de datos mock.
3. **Actual**: Finalización del flujo de ventas y optimización de la lógica de precios personalizados.

---
*Desarrollado con enfoque en la eficiencia para LIBRERIAPP.*
