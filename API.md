# API REST

Base `/api/v1`. Swagger: `/swagger-ui.html`. Autenticación: `Authorization: Bearer <JWT>`. Errores: `{timestamp,status,code,message,path,fields}`.

- `POST /auth/register|login|refresh|logout|apple|google|facebook`; `POST /auth/phone/request-code|verify-code`
- `GET|PATCH|DELETE /users/me`; `GET|PUT /users/me/settings`; `PUT /users/me/location`
- `POST /users/me/photos`; `PATCH /users/me/photos/reorder|{id}/primary`; `DELETE /users/me/photos/{id}`
- `GET /discover`; `POST /coffee-likes/{userId}`; `POST /coffee-passes/{userId}`
- `GET /matches`; `DELETE /matches/{id}`
- `GET /cafes/nearby`; `GET /coffee-shops/{id}`
- `POST|GET /coffee-dates`; `GET|PATCH /coffee-dates/{id}`; acciones `accept|decline|cancel|complete|counter`
- `GET /conversations`; `GET|POST /conversations/{id}/messages`
- `POST /users/{id}/block|report`; `GET /notifications`; gestión de lectura y dispositivos push

Listas extensibles usan `page`, `size`, `content` y `hasMore`. Fechas son ISO-8601 UTC.
