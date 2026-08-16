# API REST

Base `/api/v1`. Swagger: `/swagger-ui.html`. Autenticación: `Authorization: Bearer <JWT>`. Errores: `{timestamp,status,code,message,path,fields}`.

- `POST /auth/register|login|refresh|logout`
- `GET|PATCH|DELETE /users/me`; `POST /users/me/photos`; `DELETE /users/me/photos/{id}`
- `GET /discover`; `POST /coffee-likes/{userId}`
- `GET /matches`; `DELETE /matches/{id}`
- `GET /coffee-shops/nearby`; `GET /coffee-shops/{id}`
- `POST|GET /coffee-dates`; `PATCH /coffee-dates/{id}`
- `GET /conversations`; `GET|POST /conversations/{id}/messages`
- `POST /users/{id}/block|report`; `GET /notifications`

Listas extensibles usan `page`, `size`, `content` y `hasMore`. Fechas son ISO-8601 UTC.
