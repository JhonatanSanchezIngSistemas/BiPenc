-- 005_generar_correlativo_rpc.sql
-- Crea la tabla de correlativos y el RPC atómico que el cliente Flutter consume.
-- El cliente llama: client.rpc('generar_correlativo', params: {'alias': alias}).maybeSingle()
-- y espera el resultado: { "correlativo": "B001-00001" }

-- Tabla de correlativos: un registro por scope (serie de boleta/factura)
CREATE TABLE IF NOT EXISTS public.correlativos (
  scope      text PRIMARY KEY,
  last       bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Asegurar que solo usuarios autenticados pueden leer/escribir correlativos
ALTER TABLE public.correlativos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_can_use_correlativos"
  ON public.correlativos FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- RPC atómica: generar_correlativo(alias text) → TABLE(correlativo text)
-- Usa UPDATE+RETURNING en loop con INSERT ON CONFLICT para garantizar atomicidad
-- sin race conditions en entornos multi-dispositivo.
CREATE OR REPLACE FUNCTION public.generar_correlativo(alias text)
RETURNS TABLE(correlativo text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_scope text := 'B001';   -- Serie fija; ampliar en el futuro si se requieren múltiples series
  v_next  bigint;
BEGIN
  LOOP
    -- Camino feliz: la fila ya existe → incremento atómico
    UPDATE public.correlativos
      SET last       = last + 1,
          updated_at = now()
      WHERE scope = v_scope
      RETURNING last INTO v_next;

    IF FOUND THEN
      correlativo := v_scope || '-' || LPAD(v_next::text, 5, '0');
      RETURN NEXT;
      RETURN;
    END IF;

    -- Primera vez: insertar con valor 1
    BEGIN
      INSERT INTO public.correlativos(scope, last)
        VALUES (v_scope, 1);
      correlativo := v_scope || '-' || '00001';
      RETURN NEXT;
      RETURN;
    EXCEPTION WHEN unique_violation THEN
      -- Inserción concurrente de otro proceso → reintentar
      NULL;
    END;
  END LOOP;
END;
$$;

-- Permitir que usuarios autenticados llamen la función (SECURITY DEFINER ya la eleva)
GRANT EXECUTE ON FUNCTION public.generar_correlativo(text) TO authenticated;
