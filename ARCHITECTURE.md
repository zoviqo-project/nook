# Arquitectura

La API versionada `/api/v1` separa `controller`, `service`, `repository`, `domain`, `dto`, `mapper`, `security`, `config` y `exception`. Los controllers solo exponen DTOs. Las reglas sociales viven en servicios transaccionales y las invariantes también se protegen en PostgreSQL.

`PlacesProviderPort` y `PlacePhotoPort` desacoplan el catálogo y sus imágenes. `GooglePlacesProvider` es el adaptador productivo; `SeedPlacesProvider` solo se activa con el perfil explícito `demo-seed`. El chat REST encapsula conversación/mensajes para añadir WebSocket sin cambiar el dominio.

Los adaptadores de autenticación externa, push y almacenamiento multimedia también se exponen mediante puertos. En producción las fotos se guardan en PostgreSQL para sobrevivir al sistema de archivos efímero de Render; en desarrollo se usa el adaptador local.

iOS sigue MVVM: vistas SwiftUI → view models `@MainActor` → protocolo `NookRepository` → actor `APIRepository`. JWT/refresh persisten en Keychain; ubicación se encapsula con CoreLocation. La navegación usa `NavigationStack`.

Privacidad: discovery nunca serializa coordenadas, email o teléfono ajenos; solo distancia redondeada. Bloqueos se filtran en ambos sentidos.
