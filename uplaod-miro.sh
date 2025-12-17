#!/usr/bin/env bash
set -euo pipefail

# =========================
# Configuration
# =========================

MIRO_TOKEN="${MIRO_TOKEN:?MIRO_TOKEN not set}"
BOARD_ID="${BOARD_ID:?BOARD_ID not set}"

IMAGE_FILE="${1:?Image file path must be provided as the first argument}"
DIAGRAM_NAME="${2:?Diagram name must be provided as the second argument}"

DEFAULT_X=0
DEFAULT_Y=0

API_BASE="https://api.miro.com/v2"

# =========================
# Helpers
# =========================

auth_header() {
  echo "Authorization: Bearer $MIRO_TOKEN"
}

log() {
  echo "[$(date +'%H:%M:%S')] $1"
}

# =========================
# 1. Find existing widget
# =========================

log "Searching for existing diagram '$DIAGRAM_NAME'…"

WIDGET_ID=$(curl -s \
  -H "$(auth_header)" \
  "$API_BASE/boards/$BOARD_ID/items?limit=50" \
  | jq -r "
  .data[]
  | select(.type == \"image\")
  | select(.data.title == \"$DIAGRAM_NAME\")
  | .id
" | head -n 1)

# =========================
# 2. If exists → get position
# =========================


if [[ -n "${WIDGET_ID:-}" ]]; then
  log "Found existing widget: $WIDGET_ID"

  POSITION=$(curl -s \
    -H "$(auth_header)" \
    "$API_BASE/boards/$BOARD_ID/items/$WIDGET_ID")

  X=$(echo "$POSITION" | jq -r '.position.x')
  Y=$(echo "$POSITION" | jq -r '.position.y')

  log "Preserving position x=$X y=$Y"

  # =========================
  # 3. Delete old widget
  # =========================

  log "Deleting old diagram…"

  curl -s -X DELETE \
    -H "$(auth_header)" \
    "$API_BASE/boards/$BOARD_ID/items/$WIDGET_ID" \
    > /dev/null

else
  log "No existing diagram found, creating new one"

  X=$DEFAULT_X
  Y=$DEFAULT_Y
fi

# =========================
# 4. Upload image
# =========================

if [[ ! -f "$IMAGE_FILE" ]]; then
  log "Error: Image file not found: $IMAGE_FILE"
  exit 1
fi

log "Uploading $IMAGE_FILE to Miro…"

UPLOAD_RESPONSE=$(curl -s -X POST \
  -H "$(auth_header)" \
  -F "resource=@$IMAGE_FILE" \
  "$API_BASE/boards/$BOARD_ID/images")

ITEM_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id')

if [[ -z "$ITEM_ID" || "$ITEM_ID" == "null" ]]; then
  log "Error: Failed to upload file. Response: $UPLOAD_RESPONSE"
  exit 1
fi

log "File uploaded successfully. Item ID: $ITEM_ID"

# =========================
# 5. Update metadata
# =========================

log "Updating metadata (title and position)…"

curl -s -X PATCH \
  -H "$(auth_header)" \
  -H "Content-Type: application/json" \
  "$API_BASE/boards/$BOARD_ID/items/$ITEM_ID" \
  -d "{
    \"data\": {
      \"title\": \"$DIAGRAM_NAME\"
    },
    \"position\": {
      \"x\": $X,
      \"y\": $Y
    }
  }" > /dev/null

log "Done. Diagram '$DIAGRAM_NAME' is up to date."