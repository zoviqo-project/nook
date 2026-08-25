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

## Teléfono (Twilio Verify)

El acceso por teléfono está disponible junto a Google, Apple, Facebook y email. iOS normaliza
el número al formato E.164 mediante el selector de país (España `+34` por defecto), solicita el
SMS, acepta el código de seis cifras y guarda la sesión resultante en Keychain.

Producción usa Twilio Verify cuando está disponible. Las cuentas trial sin acceso a Verify pueden
usar Programmable Messaging con `TWILIO_FROM_NUMBER`: la plantilla trial `sms_2fa` genera y entrega
el código; Nook conserva solo su hash BCrypt y lo valida en backend. Configura como
secrets `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` y `TWILIO_VERIFY_SERVICE_SID`, o bien
`TWILIO_FROM_NUMBER` para el modo trial. El teléfono de la persona nunca se configura ni almacena en el repo:
se introduce en la pantalla. Si la cuenta Twilio es trial, ese teléfono debe estar verificado en
Twilio; una cuenta de pago puede enviar a números permitidos por su Geo Permissions.

Nook añade un cooldown de 30 segundos para reenvíos, máximo de cinco validaciones por reto,
rate limiting por IP y retos de un solo uso. Twilio aplica además sus propios límites. Los perfiles
`development`/`test` conservan un proveedor aislado que devuelve el código únicamente en la
respuesta de desarrollo; el perfil `prod` nunca expone códigos.
