#!/usr/bin/env bash
# Diagnose benchmark matching: find all free models with missing/partial matches
set -euo pipefail

STATE="${MODEL_GATEWAY_STATE_PATH:-$HOME/.config/model-gateway/routing.sqlite3}"
GATEWAY="${1:-http://127.0.0.1:8008}"

echo "=== Free-model benchmark matching diagnostic ==="
echo "State DB: $STATE"
echo "Gateway:  $GATEWAY"
echo ""

echo "=== Fetching free models... ==="
ALL=$(curl -s "$GATEWAY/v1/free-models?limit=10000")

MATCHED=$(echo "$ALL" | jq '[.data[] | select(.quality != null)]')
UNMATCHED=$(echo "$ALL" | jq '[.data[] | select(.quality == null)]')

MATCHED_COUNT=$(echo "$MATCHED" | jq 'length')
UNMATCHED_COUNT=$(echo "$UNMATCHED" | jq 'length')
TOTAL=$((MATCHED_COUNT + UNMATCHED_COUNT))
PCT=$(awk "BEGIN { printf \"%.1f\", $MATCHED_COUNT * 100 / $TOTAL }")

echo "Matched:   $MATCHED_COUNT ($PCT%)"
echo "Unmatched: $UNMATCHED_COUNT"
echo "Total:     $TOTAL"
echo ""

echo "=== Unmatched models by provider ==="
echo "$UNMATCHED" | jq -r '
  group_by(.provider) | .[] | 
  "\(.[0].provider): \(length) unmatched" as $header |
  ($header, 
   (.[] | "  - \(.model): \(if .input_price_per_million then "price=\(.input_price_per_million)/\(.output_price_per_million)" else "no-pricing" end)"),
   ""
  )'
echo ""

echo "=== Potential AA matches (requires 2+ shared tokens) ==="
echo ""

echo "$UNMATCHED" | jq -r '.[].model' | while IFS= read -r model; do
  base=$(echo "$model" | sed 's/.*\///' | sed 's/:[^:]*$//')
  normalized=$(echo "$base" | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/\n/g' | sed '/^$/d' | awk 'length($0) >= 3' | sort -u)

  # Build array of tokens
  TOKENS=()
  while IFS= read -r t; do
    TOKENS+=("$t")
  done <<< "$normalized"
  TOKEN_COUNT=${#TOKENS[@]}

  [ "$TOKEN_COUNT" -lt 2 ] && continue

  # Build SQL WHERE clause pairing each token with every other
  CONDITIONS=""
  for i in $(seq 0 $((TOKEN_COUNT - 2))); do
    for j in $(seq $((i + 1)) $((TOKEN_COUNT - 1))); do
      [ -n "$CONDITIONS" ] && CONDITIONS="$CONDITIONS OR "
      CONDITIONS="$CONDITIONS(model_id LIKE '%${TOKENS[$i]}%' AND model_id LIKE '%${TOKENS[$j]}%')"
    done
  done

  RESULTS=$(sqlite3 -separator '|' "$STATE" "
    SELECT model_id, COALESCE(general_quality, -1) FROM benchmark_models
    WHERE snapshot_id = 11 AND ($CONDITIONS)
    ORDER BY general_quality DESC NULLS LAST
    LIMIT 3
  " 2>/dev/null)

  if [ -n "$RESULTS" ]; then
    echo "$model: potential matches ->"
    echo "$RESULTS" | while IFS='|' read -r aid qual; do
      echo "    $aid (G=$qual)"
    done
    echo ""
  fi
done

echo "=== Match quality by provider ==="
echo "$ALL" | jq -r '
  [.data[] | {provider, matched: (.quality != null)}] 
  | group_by(.provider) | .[] 
  | {provider: .[0].provider, 
     total: length, 
     matched: map(select(.matched)) | length, 
     unmatched: map(select(.matched | not)) | length}
  | "\(.provider): \(.matched)/\(.total) matched (\(.unmatched) unmatched)"
'
