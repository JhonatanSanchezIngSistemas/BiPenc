import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const emailRegex = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const rolesPermitidos = new Set(['ADMIN', 'VENTAS']);

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    status,
  });
}

Deno.serve(async (req) => {
  // Manejo de preflight (CORS)
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Método no permitido' }, 405);
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return jsonResponse({ error: 'No autorizado' }, 401);
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    );

    // 1. Obtener usuario actual desde el JWT
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) throw new Error('No autorizado');

    // 2. Verificar que el remitente sea ADMIN
    const { data: profile, error: profileError } = await supabaseClient
      .from('perfiles')
      .select('rol')
      .eq('id', user.id)
      .single();

    if (profileError || profile?.rol !== 'ADMIN') {
      throw new Error('Permisos insuficientes. Se requiere rol ADMIN.');
    }

    // 3. Procesar payload
    const body = await req.json();
    const email = String(body?.email ?? '').trim().toLowerCase();
    const nombre = String(body?.nombre ?? '').trim();
    const apellido = String(body?.apellido ?? '').trim();
    const rol = String(body?.rol ?? '').trim().toUpperCase();

    if (!emailRegex.test(email)) {
      return jsonResponse({ error: 'Email inválido' }, 400);
    }
    if (!nombre) {
      return jsonResponse({ error: 'Nombre es obligatorio' }, 400);
    }
    if (!apellido) {
      return jsonResponse({ error: 'Apellido es obligatorio' }, 400);
    }
    if (!rolesPermitidos.has(rol)) {
      return jsonResponse({ error: 'Rol inválido' }, 400);
    }

    // Cliente administrativo (para bypass de RLS y Auth Admin)
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // 4. Invitar usuario vía Auth
    const { data: inviteData, error: inviteError } = await supabaseAdmin.auth.admin.inviteUserByEmail(email, {
      data: { nombre, apellido, rol_inicial: rol }
    });

    if (inviteError) throw inviteError;
    if (!inviteData?.user?.id) {
      throw new Error('No se pudo crear el usuario');
    }

    // 5. Crear perfil en public.perfiles
    // Generamos un alias base: nombre.apellido
    const aliasBase = `${nombre.toLowerCase()}.${apellido.toLowerCase()}`.replace(/\s+/g, '');
    const { error: insertError } = await supabaseAdmin
      .from('perfiles')
      .insert({
        id: inviteData.user.id,
        nombre: nombre,
        apellido: apellido,
        alias: `${aliasBase}.${Math.floor(Math.random() * 1000)}`, // Sufijo para asegurar unicidad
        rol: rol,
        estado: 'ACTIVO',
      });

    if (insertError) throw insertError;

    return jsonResponse({ message: `Invitación enviada a ${email} exitosamente.` }, 200);

  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 400);
  }
});
