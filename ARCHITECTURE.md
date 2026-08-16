# Arquitectura

La API versionada `/api/v1` separa `controller`, `service`, `repository`, `domain`, `dto`, `mapper`, `security`, `config` y `exception`. Los controllers solo exponen DTOs. Las reglas sociales viven en servicios transaccionales y las invariantes también se protegen en PostgreSQL.

`PlacesProvider` desacopla el catálogo: `SeedPlacesProvider` sirve la demo y puede sustituirse por Google Places, Foursquare u Overpass. El chat REST encapsula conversación/mensajes para añadir WebSocket sin cambiar el dominio.

iOS sigue MVVM: vistas SwiftUI → view models `@MainActor` → protocolo `NookRepository` → actor `APIRepository`. JWT/refresh persisten en Keychain; ubicación se encapsula con CoreLocation. La navegación usa `NavigationStack`.

Privacidad: discovery nunca serializa coordenadas, email o teléfono ajenos; solo distancia redondeada. Bloqueos se filtran en ambos sentidos.
