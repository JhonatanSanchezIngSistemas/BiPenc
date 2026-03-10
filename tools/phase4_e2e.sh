#!/usr/bin/env bash
set -euo pipefail

DEVICE_ID="${1:-RFCY327NSEY}"
PACKAGE="com.jhonatan.bipenc"
OUT_DIR="${2:-/tmp/bipenc_phase4}"
mkdir -p "$OUT_DIR"
LOG_FILE="$OUT_DIR/phase4_$(date +%Y%m%d_%H%M%S).log"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Falta comando: $1"; exit 1; }
}

need_cmd adb
need_cmd rg

echo "[1/8] Verificando dispositivo $DEVICE_ID..."
adb -s "$DEVICE_ID" get-state >/dev/null

echo "[2/8] Reiniciando logs de Android..."
adb -s "$DEVICE_ID" logcat -c

echo "[3/8] Capturando logs en: $LOG_FILE"
adb -s "$DEVICE_ID" logcat | tee "$LOG_FILE" >/dev/null &
LOG_PID=$!
cleanup() {
  kill "$LOG_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo ""
echo "=== FASE 4 E2E BIPEC ==="
echo "Haz estos pasos en el teléfono y pulsa ENTER en cada punto:"

echo "Paso A: Abre BiPenc e inicia sesión."
read -r

echo "Paso B: Desactiva WiFi/Datos (modo offline)."
read -r

echo "Paso C: Registra una venta completa (con DNI/RUC), genera PDF e intenta impresión térmica."
read -r

echo "Paso D: Reactiva WiFi, espera 45-60s para sync automático."
read -r

echo "Paso E: Verifica que el indicador nube/printer cambie a conectado."
read -r

echo "[4/8] Esperando 10s extra para consolidar logs..."
sleep 10

cleanup
trap - EXIT

echo "[5/8] Resumen de hallazgos"

echo "-- Errores críticos detectados --"
rg -n "PGRST205|42P17|infinite recursion|ERROR \[SYNC\]|PostgrestException|Stack trace|Unhandled|FATAL EXCEPTION" "$LOG_FILE" || echo "(sin críticos)"

echo ""
echo "-- Señales de éxito detectadas --"
rg -n "Supabase inicializado|SyncService background iniciado|Venta guardada en Supabase|Sync completado sin errores|Impresión cola exitosa|PDF" "$LOG_FILE" || echo "(sin señales claras)"

echo ""
echo "[6/8] Métricas rápidas"
CRIT=$(rg -c "PGRST205|42P17|infinite recursion|ERROR \[SYNC\]|PostgrestException|FATAL EXCEPTION" "$LOG_FILE" || echo 0)
SYNC_OK=$(rg -c "Sync completado sin errores|Venta guardada en Supabase" "$LOG_FILE" || echo 0)
PRINT_OK=$(rg -c "Impresión cola exitosa|Iniciando impresión de comprobante" "$LOG_FILE" || echo 0)
PDF_OK=$(rg -c "PDF|generateVentaPdf" "$LOG_FILE" || echo 0)
echo "criticos=$CRIT sync_ok=$SYNC_OK print_signals=$PRINT_OK pdf_signals=$PDF_OK"

echo ""
echo "[7/8] Recomendación automática"
if [[ "${CRIT:-0}" -gt 0 ]]; then
  echo "Resultado: FALLA. Revisar errores críticos en $LOG_FILE"
  exit 2
fi

echo "Resultado: OK preliminar. Revisar detalle en $LOG_FILE"

echo "[8/8] Log guardado en: $LOG_FILE"
