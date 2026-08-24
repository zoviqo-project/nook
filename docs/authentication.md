# Autenticación de Nook

La distribución actual para iPhone ofrece Google y email. Ambos métodos llegan al backend,
crean o recuperan una identidad única y almacenan access/refresh tokens en Keychain.

## Sign in with Apple

El código iOS (`AppleSignInCoordinator`), el endpoint `/api/v1/auth/apple`, la validación OIDC
y `APPLE_CLIENT_ID=com.albertesteveferres.nook` están preparados. No se muestra el botón en
la distribución firmada con el equipo personal actual porque Apple no permite añadir la
capacidad Sign in with Apple a perfiles de aprovisionamiento de equipos personales.

Para activarlo:

1. Usar una membresía activa de Apple Developer Program.
2. Habilitar **Sign in with Apple** para el App ID `com.albertesteveferres.nook`.
3. Regenerar el perfil de aprovisionamiento.
4. Configurar `CODE_SIGN_ENTITLEMENTS = Nook/Nook.entitlements` en Debug y Release.
5. Verificar que Render mantiene `APPLE_CLIENT_ID=com.albertesteveferres.nook`.
6. Volver a mostrar la acción Apple en `QuickAccessView` y ejecutar pruebas de usuario nuevo
   y existente con credenciales reales.

## Teléfono

El backend contiene endpoints OTP y protección frente a reintentos, pero el adaptador de
producción todavía no tiene un proveedor SMS configurado. El acceso por teléfono permanece
oculto hasta conectar un proveedor real; no debe activarse usando códigos de desarrollo.
