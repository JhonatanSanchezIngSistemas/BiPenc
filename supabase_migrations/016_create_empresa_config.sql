CREATE TABLE IF NOT EXISTS public.empresa_config (
  id              integer PRIMARY KEY DEFAULT 1,
  logo_url        text,
  ruc             text,
  razon_social    text,
  direccion       text,
  telefono        text,
  ticket_header   text,
  ticket_footer   text,
  pdf_terminos    text
);

INSERT INTO public.empresa_config
  (id, logo_url, ruc, razon_social, direccion, telefono, ticket_header, ticket_footer, pdf_terminos)
VALUES
  (1, NULL, '00000000000', 'BiPenc', 'Ciudad Principal', '+51 900000000', 'BI PENC', 'Gracias por su compra', '')
ON CONFLICT (id) DO NOTHING;
