-- 004_correlativo.sql
-- Función para generar correlativos por scope (p.ej. por tienda o tipo de doc).
-- Usa la tabla `correlativos` creada en 002_indexes_constraints.sql

CREATE OR REPLACE FUNCTION public.generar_siguiente_correlativo(p_scope text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
  v_next bigint;
BEGIN
  LOOP
    -- Intentar actualizar la fila; si existe, incrementamos atomícamente
    UPDATE public.correlativos SET last = last + 1, updated_at = now()
      WHERE scope = p_scope
      RETURNING last INTO v_next;
    IF FOUND THEN
      RETURN v_next;
    END IF;

    -- Si no existe la fila, intentamos insertarla con valor 1
    BEGIN
      INSERT INTO public.correlativos(scope, last, updated_at) VALUES (p_scope, 1, now());
      RETURN 1;
    EXCEPTION WHEN unique_violation THEN
      -- alguien insertó simultáneamente, intentar de nuevo
      NULL;
    END;
  END LOOP;
END;
$$;

-- Ejemplo de uso desde la aplicación (SQL):
-- SELECT public.generar_siguiente_correlativo('store_42');
