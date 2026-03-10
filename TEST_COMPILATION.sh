#!/bin/bash
echo "═══════════════════════════════════════════════════════════"
echo "🧪 TEST DE COMPILACIÓN - BiPenc"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "1️⃣  Verificando sintaxis Dart..."
if dart analyze lib/main.dart 2>&1 | grep -q "Parse error"; then
  echo "❌ FALLO: Errores de sintaxis en main.dart"
  exit 1
else
  echo "✅ PASÓ: Sintaxis correcta"
fi

echo ""
echo "2️⃣  Buscando errores de compilación..."
if flutter analyze lib/ 2>&1 | grep -E "^  error •" > /dev/null; then
  echo "❌ FALLO: Errores detectados"
  flutter analyze lib/ 2>&1 | grep -E "^  error •" | head -5
  exit 1
else
  echo "✅ PASÓ: Sin errores bloquentes"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✨ RESULTADO: 🟢 PROYECTO COMPILABLE"
echo "═══════════════════════════════════════════════════════════"
