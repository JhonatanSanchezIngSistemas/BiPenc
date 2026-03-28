# admin_invitar_usuario

Edge Function para invitar usuarios desde el panel admin de BiPenc.

## Seguridad
- Requiere JWT valido.
- Verifica que el usuario remitente tenga rol `ADMIN` en `public.perfiles`.
- Usa `SUPABASE_SERVICE_ROLE_KEY` solo dentro de la funcion para operar Auth Admin y crear el perfil.

## Request
- Metodo: `POST`
- Headers:
  - `Authorization: Bearer <token>`
  - `Content-Type: application/json`

Body JSON:
```json
{
  "email": "usuario@dominio.com",
  "nombre": "Juan",
  "apellido": "Perez",
  "rol": "VENTAS"
}
```

Validaciones:
- `email` debe tener formato valido.
- `nombre` y `apellido` no pueden ser vacios.
- `rol` permitido: `ADMIN` | `VENTAS`.

## Response
- `200 OK`
```json
{ "message": "Invitacion enviada a usuario@dominio.com exitosamente." }
```

- `400 Bad Request`
```json
{ "error": "<mensaje>" }
```

- `401 Unauthorized` si no hay JWT.
- `405 Method Not Allowed` si no es POST.

## Notas
- Crea el perfil en `public.perfiles` con `estado: ACTIVO`.
- Genera `alias` usando `nombre.apellido` + sufijo aleatorio.
