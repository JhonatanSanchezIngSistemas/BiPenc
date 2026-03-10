-- 003_triggers_audit.sql
-- Crea tabla de auditoría y trigger genérico para auditar cambios.

CREATE TABLE IF NOT EXISTS public.audit_log (
  id bigserial PRIMARY KEY,
  schema_name text NOT NULL,
  table_name text NOT NULL,
  operation text NOT NULL, -- INSERT, UPDATE, DELETE
  record jsonb,
  changed_by text,
  changed_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.audit_if_changes() RETURNS trigger AS $$
BEGIN
  IF (TG_OP = 'DELETE') THEN
    INSERT INTO public.audit_log(schema_name, table_name, operation, record, changed_by)
    VALUES (TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, row_to_json(OLD.*), auth.uid());
    RETURN OLD;
  ELSIF (TG_OP = 'UPDATE') THEN
    INSERT INTO public.audit_log(schema_name, table_name, operation, record, changed_by)
    VALUES (TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, row_to_json(NEW.*), auth.uid());
    RETURN NEW;
  ELSIF (TG_OP = 'INSERT') THEN
    INSERT INTO public.audit_log(schema_name, table_name, operation, record, changed_by)
    VALUES (TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, row_to_json(NEW.*), auth.uid());
    RETURN NEW;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Adjuntar triggers a tablas críticas (si existen)
DO $$
DECLARE
  tbl text;
  tablas text[] := ARRAY['ventas','venta_items','productos','print_queue'];
BEGIN
  FOREACH tbl IN ARRAY tablas LOOP
    IF EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=tbl) THEN
      EXECUTE format('DROP TRIGGER IF EXISTS audit_trigger ON public.%I', tbl);
      EXECUTE format('CREATE TRIGGER audit_trigger AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.audit_if_changes()', tbl);
    END IF;
  END LOOP;
END$$;
