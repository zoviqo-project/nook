#!/bin/zsh
set -euo pipefail

API_URL="${NOOK_API_URL:-http://127.0.0.1:8080/api/v1}"
RUN_ID="$(date +%s)"
EMAIL_A="e2e-a-${RUN_ID}@nook.local"
EMAIL_B="e2e-b-${RUN_ID}@nook.local"
PASSWORD='Coffee123!'
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

request() {
  curl --fail-with-body --silent --show-error --connect-timeout 10 --max-time 150 "$@"
}

register() {
  local email="$1" name="$2" output="$3"
  request -H 'Content-Type: application/json' -X POST "$API_URL/auth/register" \
    -d "{\"email\":\"$email\",\"password\":\"$PASSWORD\"}" > "$output"
}

register "$EMAIL_A" 'E2E A' "$TMP_DIR/a.json"
register "$EMAIL_B" 'E2E B' "$TMP_DIR/b.json"
TOKEN_A="$(jq -r .accessToken "$TMP_DIR/a.json")"
TOKEN_B="$(jq -r .accessToken "$TMP_DIR/b.json")"
USER_A="$(jq -r .user.id "$TMP_DIR/a.json")"
USER_B="$(jq -r .user.id "$TMP_DIR/b.json")"

# Onboarding progress is server-owned and must survive a new session/device.
request -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' -X PATCH "$API_URL/users/me" \
  -d '{"name":"E2E A","birthDate":"1994-04-12","gender":"OTHER","lookingFor":"OPEN_ENDED","onboardingStep":4}' >/dev/null
request -H "Authorization: Bearer $TOKEN_A" "$API_URL/users/me" > "$TMP_DIR/onboarding-resume.json"
[[ "$(jq -r .onboardingStep "$TMP_DIR/onboarding-resume.json")" == "4" ]]

if ! request -H "Authorization: Bearer $TOKEN_A" -X POST "$API_URL/users/me/photos" \
  -F "file=@ios/Nook/Resources/Assets.xcassets/NookBrandMark.imageset/NookBrandMark.png;type=image/png" \
  > "$TMP_DIR/photo.json"; then
  jq '{status,code,message,path}' "$TMP_DIR/photo.json"
  exit 1
fi
request -H "Authorization: Bearer $TOKEN_B" -X POST "$API_URL/users/me/photos" \
  -F "file=@ios/Nook/Resources/Assets.xcassets/NookBrandMark.imageset/NookBrandMark.png;type=image/png" \
  > "$TMP_DIR/photo-b.json"
PHOTO_URL="$(jq -r .url "$TMP_DIR/photo.json")"
API_ORIGIN="${API_URL%/api/v1}"
if ! request -H 'Accept: image/*' "$API_ORIGIN$PHOTO_URL" > "$TMP_DIR/photo-content"; then
  print -r -- "Photo retrieval failed for path: $PHOTO_URL"
  exit 1
fi

request -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' -X PATCH "$API_URL/users/me" \
  -d '{"bio":"Cuenta de validación end-to-end","city":"Sant Vicenç dels Horts","coffeePersonality":"Cortado","preferredPlan":"LONG_TALKS","preferredVibe":"CALM","coffeesPerDay":2,"favoriteCoffeeMoment":"AFTERWORK","minAge":18,"maxAge":80,"maxDistanceKm":50,"coffeePreferences":["CORTADO"],"onboardingComplete":true,"onboardingStep":15}' >/dev/null
request -H "Authorization: Bearer $TOKEN_B" -H 'Content-Type: application/json' -X PATCH "$API_URL/users/me" \
  -d '{"name":"E2E B","birthDate":"1994-04-12","gender":"OTHER","lookingFor":"OPEN_ENDED","bio":"Cuenta de validación end-to-end","city":"Barcelona","coffeePersonality":"Cortado","preferredPlan":"LONG_TALKS","preferredVibe":"CALM","coffeesPerDay":2,"favoriteCoffeeMoment":"AFTERWORK","minAge":18,"maxAge":80,"maxDistanceKm":50,"coffeePreferences":["CORTADO"],"onboardingComplete":true,"onboardingStep":15}' >/dev/null

CAPTURED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
request -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' -X PUT "$API_URL/users/me/location" \
  -d "{\"latitude\":41.3936,\"longitude\":2.0093,\"accuracyMeters\":18,\"capturedAt\":\"$CAPTURED_AT\"}" >/dev/null
request -H "Authorization: Bearer $TOKEN_B" -H 'Content-Type: application/json' -X PUT "$API_URL/users/me/location" \
  -d "{\"latitude\":41.3874,\"longitude\":2.1686,\"accuracyMeters\":18,\"capturedAt\":\"$CAPTURED_AT\"}" >/dev/null

request -H "Authorization: Bearer $TOKEN_A" -X POST "$API_URL/coffee-likes/$USER_B" > "$TMP_DIR/like-a.json"
request -H "Authorization: Bearer $TOKEN_B" -X POST "$API_URL/coffee-likes/$USER_A" > "$TMP_DIR/like-b.json"
MATCH_ID="$(jq -r .match.id "$TMP_DIR/like-b.json")"
CONVERSATION_ID="$(jq -r .match.conversationId "$TMP_DIR/like-b.json")"

request -H "Authorization: Bearer $TOKEN_A" "$API_URL/matches/$MATCH_ID/meeting-point" > "$TMP_DIR/midpoint.json"
MIDPOINT_LAT="$(jq -r .latitude "$TMP_DIR/midpoint.json")"
MIDPOINT_LNG="$(jq -r .longitude "$TMP_DIR/midpoint.json")"
request "$API_URL/cafes/nearby?latitude=$MIDPOINT_LAT&longitude=$MIDPOINT_LNG&radius=3000" > "$TMP_DIR/cafes.json"
CAFE_ID="$(jq -r '.[0].id' "$TMP_DIR/cafes.json")"
PROPOSED_AT="$(date -u -v+1d '+%Y-%m-%dT18:30:00Z')"
PROPOSAL_KEY="$(uuidgen | tr '[:upper:]' '[:lower:]')"
request -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' -X POST "$API_URL/coffee-dates" \
  -d "{\"matchId\":\"$MATCH_ID\",\"coffeeShopId\":\"$CAFE_ID\",\"proposedAt\":\"$PROPOSED_AT\",\"paymentPreference\":\"SPLIT\",\"nookChoice\":true,\"idempotencyKey\":\"$PROPOSAL_KEY\",\"timeZoneId\":\"Europe/Madrid\"}" > "$TMP_DIR/proposal.json"
PROPOSAL_ID="$(jq -r .id "$TMP_DIR/proposal.json")"
request -H "Authorization: Bearer $TOKEN_B" -X POST "$API_URL/coffee-dates/$PROPOSAL_ID/accept" > "$TMP_DIR/accepted.json"

# An accepted coffee is still active and must prevent duplicate proposals.
DUPLICATE_STATUS="$(curl --silent --output "$TMP_DIR/duplicate.json" --write-out '%{http_code}' \
  --connect-timeout 10 --max-time 150 -H "Authorization: Bearer $TOKEN_A" \
  -H 'Content-Type: application/json' -X POST "$API_URL/coffee-dates" \
  -d "{\"matchId\":\"$MATCH_ID\",\"coffeeShopId\":\"$CAFE_ID\",\"proposedAt\":\"$PROPOSED_AT\",\"paymentPreference\":\"SPLIT\",\"nookChoice\":false,\"idempotencyKey\":\"$(uuidgen | tr '[:upper:]' '[:lower:]')\",\"timeZoneId\":\"Europe/Madrid\"}")"
[[ "$DUPLICATE_STATUS" == "409" ]]

request -H "Authorization: Bearer $TOKEN_A" -X POST "$API_URL/coffee-dates/$PROPOSAL_ID/cancel" > "$TMP_DIR/cancelled.json"

# Create a second proposal, counter it through the dedicated endpoint and accept it.
SECOND_KEY="$(uuidgen | tr '[:upper:]' '[:lower:]')"
request -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' -X POST "$API_URL/coffee-dates" \
  -d "{\"matchId\":\"$MATCH_ID\",\"coffeeShopId\":\"$CAFE_ID\",\"proposedAt\":\"$PROPOSED_AT\",\"paymentPreference\":\"SPLIT\",\"nookChoice\":false,\"idempotencyKey\":\"$SECOND_KEY\",\"timeZoneId\":\"Europe/Madrid\"}" > "$TMP_DIR/proposal-2.json"
PROPOSAL_2_ID="$(jq -r .id "$TMP_DIR/proposal-2.json")"
request -H "Authorization: Bearer $TOKEN_B" -H 'Content-Type: application/json' -X POST \
  "$API_URL/coffee-dates/$PROPOSAL_2_ID/counter" \
  -d "{\"proposedAt\":\"$PROPOSED_AT\",\"coffeeShopId\":\"$CAFE_ID\",\"paymentPreference\":\"SPLIT\"}" \
  > "$TMP_DIR/counter.json"
request -H "Authorization: Bearer $TOKEN_A" -X POST "$API_URL/coffee-dates/$PROPOSAL_2_ID/accept" > "$TMP_DIR/accepted-2.json"
request -H "Authorization: Bearer $TOKEN_B" -X POST "$API_URL/coffee-dates/$PROPOSAL_2_ID/cancel" > "$TMP_DIR/cancelled-2.json"

# A rejected proposal must persist and return the card to a state that can propose again.
THIRD_KEY="$(uuidgen | tr '[:upper:]' '[:lower:]')"
request -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' -X POST "$API_URL/coffee-dates" \
  -d "{\"matchId\":\"$MATCH_ID\",\"coffeeShopId\":\"$CAFE_ID\",\"proposedAt\":\"$PROPOSED_AT\",\"paymentPreference\":\"SPLIT\",\"nookChoice\":false,\"idempotencyKey\":\"$THIRD_KEY\",\"timeZoneId\":\"Europe/Madrid\"}" > "$TMP_DIR/proposal-3.json"
PROPOSAL_3_ID="$(jq -r .id "$TMP_DIR/proposal-3.json")"
request -H "Authorization: Bearer $TOKEN_B" -X POST "$API_URL/coffee-dates/$PROPOSAL_3_ID/decline" > "$TMP_DIR/declined.json"

CLIENT_MESSAGE_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
request -H "Authorization: Bearer $TOKEN_A" -H 'Content-Type: application/json' -X POST "$API_URL/conversations/$CONVERSATION_ID/messages" \
  -d "{\"body\":\"Mensaje persistente E2E ☕\",\"clientMessageId\":\"$CLIENT_MESSAGE_ID\"}" > "$TMP_DIR/message.json"

request -H 'Content-Type: application/json' -X POST "$API_URL/auth/login" \
  -d "{\"email\":\"$EMAIL_B\",\"password\":\"$PASSWORD\"}" > "$TMP_DIR/relogin.json"
TOKEN_B2="$(jq -r .accessToken "$TMP_DIR/relogin.json")"
request -H "Authorization: Bearer $TOKEN_B2" "$API_URL/matches" > "$TMP_DIR/matches.json"
request -H "Authorization: Bearer $TOKEN_B2" "$API_URL/coffee-dates" > "$TMP_DIR/dates.json"
request -H "Authorization: Bearer $TOKEN_B2" "$API_URL/my-cafes" > "$TMP_DIR/my-cafes.json"
request -H "Authorization: Bearer $TOKEN_B2" "$API_URL/conversations/$CONVERSATION_ID/messages" > "$TMP_DIR/messages.json"

REFRESH_B2="$(jq -r .refreshToken "$TMP_DIR/relogin.json")"
request -H 'Content-Type: application/json' -X POST "$API_URL/auth/logout" \
  -d "{\"refreshToken\":\"$REFRESH_B2\"}" >/dev/null
REVOKED_STATUS="$(curl --silent --output "$TMP_DIR/revoked.json" --write-out '%{http_code}' \
  --connect-timeout 10 --max-time 150 -H 'Content-Type: application/json' -X POST "$API_URL/auth/refresh" \
  -d "{\"refreshToken\":\"$REFRESH_B2\"}")"
[[ "$REVOKED_STATUS" == "401" ]]

jq -n \
  --arg auth "$(jq -r 'if .accessToken then "ok" else "failed" end' "$TMP_DIR/relogin.json")" \
  --arg match "$(jq -r --arg id "$MATCH_ID" 'if any(.[]; .id == $id) then "persisted" else "missing" end' "$TMP_DIR/matches.json")" \
  --arg proposal "$(jq -r --arg accepted "$PROPOSAL_2_ID" --arg declined "$PROPOSAL_3_ID" 'if (any(.[]; .id == $accepted and .status == "CANCELLED") and any(.[]; .id == $declined and .status == "DECLINED")) then "lifecycle-persisted" else "missing" end' "$TMP_DIR/dates.json")" \
  --arg counter "$(jq -r --arg id "$PROPOSAL_2_ID" 'if (.id == $id and .status == "COUNTER_PROPOSED") then "persisted" else "missing" end' "$TMP_DIR/counter.json")" \
  --arg myCafes "$(jq -r --arg match "$MATCH_ID" 'if any(.[]; .matchId == $match and (.availableActions | index("PROPOSE"))) then "consistent" else "missing" end' "$TMP_DIR/my-cafes.json")" \
  --arg duplicate "$([[ "$DUPLICATE_STATUS" == "409" ]] && echo blocked || echo allowed)" \
  --arg logout "$([[ "$REVOKED_STATUS" == "401" ]] && echo revoked || echo active)" \
  --arg message "$(jq -r 'if any(.content[]; .body == "Mensaje persistente E2E ☕") then "persisted" else "missing" end' "$TMP_DIR/messages.json")" \
  --arg cafes "$(jq -r 'if length > 0 then "real-results" else "missing" end' "$TMP_DIR/cafes.json")" \
  --arg midpoint "$(jq -r 'if (.latitude > 41.38 and .latitude < 41.41 and .longitude > 2.07 and .longitude < 2.10) then "geographic" else "invalid" end' "$TMP_DIR/midpoint.json")" \
  --arg photo "$([[ -s "$TMP_DIR/photo-content" ]] && echo persisted || echo missing)" \
  --arg onboarding "$([[ "$(jq -r .onboardingStep "$TMP_DIR/onboarding-resume.json")" == "4" ]] && echo resumed || echo lost)" \
  '{authentication:$auth,onboarding:$onboarding,photo:$photo,match:$match,midpoint:$midpoint,cafes:$cafes,proposal:$proposal,counter:$counter,myCafes:$myCafes,duplicateProposal:$duplicate,message:$message,logout:$logout}'
