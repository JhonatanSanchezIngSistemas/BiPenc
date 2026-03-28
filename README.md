<div align="center">
  <img src="https://raw.githubusercontent.com/JhonatanSanchezIngSistemas/BiPenc/main/assets/logo/logo.png" width="120" height="120" alt="BiPenc Logo" />
  
  # BiPenc
  ### 💎 Sistema Experto de Inventario & POS (Offline-First)
  
  [![Version](https://img.shields.io/badge/Version-1.0.1%2B2-7928CA?style=for-the-badge&logo=flutter&logoColor=white)](https://github.com/JhonatanSanchezIngSistemas/BiPenc)
  [![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-0070F3?style=for-the-badge&logo=android&logoColor=white)](https://github.com/JhonatanSanchezIngSistemas/BiPenc)
  [![Security](https://img.shields.io/badge/Security-AES--256--CBC-FF0080?style=for-the-badge&logo=lock&logoColor=white)](https://github.com/JhonatanSanchezIngSistemas/BiPenc)
  
  ---
  
  **BiPenc** no es solo un POS; es el núcleo operativo para negocios que no pueden permitirse detenerse. Diseñado con una arquitectura de **continuidad absoluta**, garantiza que cada venta y cada producto estén seguros, incluso en el corazón de la falta de conectividad.
  
</div>

---

## ✨ Características Premium

### 🏢 Continuidad "Offline-First"
Operación total sin internet. Sincronización inteligente en segundo plano mediante **Sync Queue V2**. Nunca pierdas una venta por problemas de red.

### 🛡️ Seguridad de Datos de Grado Bancario
- **Cifrado PII**: Nombres y direcciones protegidos bajo **AES-256-CBC**.
- **Blind Indexing**: Búsqueda ultrarrápida de DNI/RUC mediante **HMAC-SHA256** sin exponer datos sensibles.
- **Secure Storage**: Llaves maestras resguardadas en el hardware (Keystore/Keychain).

### 🖨️ Ecosistema Térmico Avanzado
Soporte nativo para impresoras **PT-210**. Algoritmo de **Dithering** propietario para logos nítidos y tickets profesionales optimizados para 58mm/80mm.

### 📸 Visión Artificial (ML Kit)
Detección inteligente de bordes, corrección de perspectiva y binarización adaptativa para la captura de listas de útiles y documentos físicos.

---

## 🏗️ Arquitectura de Élite

```mermaid
graph LR
    subgraph "Local Edge"
        UI[Flutter UI] --- SQL[(SQLite Global)]
        SQL --- Q[Sync Queue]
    end
    
    subgraph "Cloud Core"
        Q --> |Atómico| SB[Supabase DB]
        SB --> |RLS Protected| SEC[Security Layer]
    end
    
    style UI fill:#0070F3,color:#fff
    style SB fill:#7928CA,color:#fff
    style SQL fill:#000,color:#fff
```

---

## 📂 Estructura del Proyecto

Organizado bajo principios de **Clean Architecture** para mantenimiento a largo plazo:

- `lib/modulos/`: Dominios funcionales (Caja, Inventario, Pedidos).
- `lib/servicios/`: Motores core (Impresión, Sincronización, OCR).
- `lib/datos/`: Modelos atómicos y lógica de negocio.
- `lib/base/`: Temas y configuraciones globales estandarizadas.

---

## 🚀 Guía de Inicio Rápido

### Requisitos
- Flutter SDK `^3.5.0`
- Android Studio / VS Code
- Archivo `.env` configurado (Ver `.env.example`)

### Instalación
```bash
# 1. Clonar repositorio
git clone https://github.com/JhonatanSanchezIngSistemas/BiPenc.git

# 2. Instalar dependencias
flutter pub get

# 3. Iniciar en modo producción
flutter run --release
```

---

<div align="center">
  <sub>Desarrollado con ❤️ por <b>Jhonatan Sanchez</b> - Arquitecto de Software & Ing. de Sistemas</sub><br/>
  <sub><b>Versión:</b> 1.0.1+2 | <b>Sincronización:</b> 28 de Marzo, 2026</sub>
</div>
