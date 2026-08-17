# NOOK ☕

Nook es una aplicación social iOS 18+ cuyo flujo de dominio es `persona → coffee like → match → cafetería real → propuesta → confirmación → conversación`. El repositorio contiene la app SwiftUI, la API Spring Boot/PostgreSQL y la landing Next.js.

## Arquitectura

- iOS: SwiftUI, MVVM, `async/await`, CoreLocation, MapKit, PhotosUI y Keychain. Las vistas consumen contratos de repositorio; `APIRepository` centraliza HTTP, JWT, refresh automático y errores.
- Backend: controladores REST → servicios/casos de uso → puertos de salida → adaptadores de autenticación, Google Places, notificaciones, media y PostgreSQL. Los DTO REST nunca son entidades JPA.
- Datos: PostgreSQL + Flyway. Hibernate usa `ddl-auto=validate`; las migraciones son la única autoridad del esquema.
- Seguridad: access JWT breve, refresh token rotatorio almacenado con hash, logout/revocación, autorización por participante, bloqueos y rate limiting.

## Inicio local

```bash
cp .env.example .env
# Rellena GOOGLE_PLACES_API_KEY y secretos locales.
docker compose up -d --build
curl http://localhost:8080/actuator/health
open http://localhost:8080/swagger-ui/index.html
```

`docker-compose.yml` levanta PostgreSQL 16 con healthcheck y espera a que esté sano antes de iniciar la API. No se guardan secretos en Git. En desarrollo sin Docker puede usarse PostgreSQL local y `scripts/run-local-backend.zsh`.

## Autenticación

Endpoints: Apple, Google, Facebook, teléfono/OTP, refresh, logout y `users/me`. Apple/Google validan firma OIDC, issuer, audience y expiración en backend. Facebook valida el token con Graph. El perfil `development` permite un OTP efímero dev devuelto solo en esa configuración; producción requiere un adaptador SMS real.

Google Login usa OAuth 2.0 con PKCE en iOS y valida el `id_token` de nuevo en backend. Configura el mismo client ID iOS en `GOOGLE_IOS_CLIENT_ID` (Xcode) y `GOOGLE_CLIENT_ID` (backend/Render), además del esquema inverso en `GOOGLE_REVERSED_CLIENT_ID`. La URI autorizada es `<esquema-inverso>:/oauth2redirect/google`. Sin esos valores el botón permanece visible y devuelve un error de configuración, sin crear ninguna sesión local.

Variables relevantes: `APPLE_CLIENT_ID`, `GOOGLE_CLIENT_ID`, `FACEBOOK_APP_ID`, `FACEBOOK_APP_SECRET`, `JWT_SECRET`, `JWT_ACCESS_MINUTES` y `JWT_REFRESH_DAYS`. Sign in with Apple también exige capability y provisioning profile válidos para el bundle iOS.

## Google Places y ubicación

La clave de Places vive exclusivamente en backend (`GOOGLE_PLACES_API_KEY`). iOS envía el origen real activo —GPS, midpoint geográfico o ubicación seleccionada— a `GET /api/v1/cafes/nearby`. El backend usa Places API New, filtra establecimientos no cafetería, conserva el `google_place_id`, coordenadas exactas, fotos y metadatos disponibles, y cachea resultados. Nunca se hace fallback silencioso a cafeterías ficticias en producción.

## Fotos

`MediaStoragePort` desacopla la aplicación del proveedor. Desarrollo usa filesystem y PostgreSQL conserva solo URL/metadata. En producción puede sustituirse por S3/GCS sin cambiar controladores o casos de uso. Límite: ocho fotos; eliminar, ordenar y elegir principal se validan también en backend.

## iOS

Abre `ios/Nook.xcodeproj`. Para dispositivo físico, configura `NOOK_API_URL` con una URL HTTPS pública o la IP LAN del Mac, por ejemplo `http://192.168.1.20:8080/api/v1/`. El refresh token se guarda en Keychain; la fuente de verdad de perfiles, matches, cafés, propuestas y mensajes es la API.

## Pruebas

```bash
cd backend && ./mvnw clean test
cd .. && ./scripts/e2e-local.zsh
xcodebuild -project ios/Nook.xcodeproj -scheme Nook \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Los tests cubren arquitectura, validaciones, midpoint/distancia, permisos de propuestas, autorización de chat e idempotencia de mensajes. `scripts/e2e-local.zsh` prueba contra PostgreSQL y Google Places reales: dos autenticaciones, onboarding persistido, coffee likes recíprocos, match único, cafetería real, propuesta aceptada y mensaje recuperado tras reautenticar.

## Operación y despliegue

- Health: `/actuator/health`
- OpenAPI desarrollo: `/v3/api-docs`
- Swagger desarrollo: `/swagger-ui/index.html`
- Docker: `docker compose up -d --build`
- Render: `render.yaml` provisiona API Docker y PostgreSQL gestionado. Añade allí los secretos antes de desplegar.

En producción Swagger queda desactivado, los secretos deben provenir del proveedor, la API debe usar HTTPS y la clave de Google debe restringirse al backend. Para diagnóstico revisa primero health, conectividad PostgreSQL/Flyway, variables de proveedor y que `NOOK_API_URL` sea alcanzable desde el iPhone.
