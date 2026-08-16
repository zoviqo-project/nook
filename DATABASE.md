# Base de datos

PostgreSQL 16 y Flyway. `V1__social_schema.sql` crea UUID nativos, enums, checks 18+, claves foráneas, timestamps e índices.

La pareja de un match se almacena ordenada y tiene `UNIQUE(user_one_id,user_two_id)`. Coffee likes usa `UNIQUE(sender_id,receiver_id)`. La combinación garantiza un único match incluso bajo concurrencia; cada match tiene una conversación única.

Coordenadas exactas solo existen en `user_profiles` y no aparecen en DTOs públicos. Las propuestas mantienen historial por estado; no se borran al reiniciar porque PostgreSQL usa volumen persistente.
