#!/bin/bash
set -e

echo "🔍 Analizando proyecto Flutter..."
flutter analyze --no-pub --no-fatalWarnings 2>&1 | tail -5

echo ""
echo "✅ Análisis completado!"
echo ""
echo "📝 Para compilar, ejecuta:"
echo "   flutter build apk --debug"
echo ""
echo "📱 Para ejecutar en dispositivo:"
echo "   flutter run --debug -d SM"
