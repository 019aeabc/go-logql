#!/bin/sh
# Log simulator — pushes realistic JSON log lines to Loki every 2 seconds.
# Runs inside an Alpine container. Installs curl on first run.

set -e

LOKI_URL="http://loki:3100/loki/api/v1/push"
PAYLOAD_FILE="/tmp/payload.json"

# Install curl (alpine base image only has wget via busybox)
if ! command -v curl >/dev/null 2>&1; then
  echo "Installing curl..."
  apk add --no-cache curl >/dev/null 2>&1
fi

# Helpers ----------------------------------------------------------------

rand() {
  # Return a pseudo-random number between 0 and ($1 - 1)
  awk -v max="$1" 'BEGIN{srand(); printf "%d", rand()*max}'
}

pick() {
  shift_count=$(rand "$#")
  i=0
  for arg in "$@"; do
    if [ "$i" -eq "$shift_count" ]; then
      printf '%s' "$arg"
      return
    fi
    i=$((i + 1))
  done
  printf '%s' "$1"
}

ts_nano() {
  # Nanosecond timestamp: 10-digit seconds + 9-digit sub-second offset
  printf '%s%09d' "$(date +%s)" "$1"
}

# Build and send a single batch ------------------------------------------

send_batch() {
  api_level=$(pick info info info info info error error warn)
  api_status=$(pick 200 200 200 200 201 400 429 500 502 503)
  api_latency=$(( $(rand 500) + 1 ))
  api_msg=$(pick "request completed" "request completed" "request completed" "user login successful" "resource created" "cache hit" "health check ok" "internal server error" "database connection timeout" "bad gateway" "service unavailable" "rate limited" "invalid request body" "null pointer exception" "authentication failed" "permission denied" "upstream timeout" "payload too large")
  api_method=$(pick GET GET GET GET POST PUT DELETE PATCH)
  api_path=$(pick /api/v1/users /api/v1/orders /api/v1/products /api/v1/health /api/v1/auth/login /api/v1/search)
  api_instance=$(pick api-1 api-2)

  api2_level=$(pick info info info info error warn)
  api2_status=$(pick 200 200 200 201 500 429)
  api2_latency=$(( $(rand 300) + 1 ))
  api2_msg=$(pick "request completed" "request completed" "cache hit" "resource created" "rate limited" "internal server error")
  api2_method=$(pick GET GET POST PUT DELETE)
  api2_path=$(pick /api/v1/users /api/v1/orders /api/v1/products)
  api2_instance=$(pick api-1 api-2)

  web_level=$(pick info info info info error warn)
  web_status=$(pick 200 200 200 304 404 500)
  web_latency=$(( $(rand 200) + 1 ))
  web_msg=$(pick "page rendered" "page rendered" "static asset served" "not modified" "page not found" "template error" "session created" "redirect issued")

  auth_level=$(pick info info info error warn)
  auth_status=$(pick 200 200 200 401 403)
  auth_latency=$(( $(rand 100) + 1 ))
  auth_msg=$(pick "token issued" "token validated" "token refreshed" "invalid credentials" "token expired" "account locked" "mfa challenge sent")

  worker_level=$(pick info info info info error warn)
  worker_latency=$(( $(rand 2000) + 1 ))
  worker_msg=$(pick "job completed" "job completed" "job completed" "job started" "job failed" "job retrying" "queue empty" "sending email" "processing payment" "generating report")
  worker_queue=$(pick emails payments reports notifications)

  stg_latency=$(( api_latency + 50 ))

  # Write payload to file — avoids all shell pipe/escaping issues.
  # Inner JSON log lines must have \" escaped quotes to be valid JSON strings.
  cat > "$PAYLOAD_FILE" <<ENDPAYLOAD
{"streams":[{"stream":{"job":"api","env":"prod","instance":"${api_instance}"},"values":[["$(ts_nano 1)","{\"level\":\"${api_level}\",\"status\":${api_status},\"msg\":\"${api_msg}\",\"latency_ms\":${api_latency},\"method\":\"${api_method}\",\"path\":\"${api_path}\"}"],["$(ts_nano 2)","{\"level\":\"${api2_level}\",\"status\":${api2_status},\"msg\":\"${api2_msg}\",\"latency_ms\":${api2_latency},\"method\":\"${api2_method}\",\"path\":\"${api2_path}\"}"]]},{"stream":{"job":"api","env":"staging","instance":"api-staging-1"},"values":[["$(ts_nano 3)","{\"level\":\"${api_level}\",\"status\":${api_status},\"msg\":\"${api_msg}\",\"latency_ms\":${stg_latency},\"method\":\"${api_method}\",\"path\":\"${api_path}\"}"]]},{"stream":{"job":"web","env":"prod","instance":"web-1"},"values":[["$(ts_nano 4)","{\"level\":\"${web_level}\",\"status\":${web_status},\"msg\":\"${web_msg}\",\"latency_ms\":${web_latency}}"]]},{"stream":{"job":"auth","env":"prod","instance":"auth-1"},"values":[["$(ts_nano 5)","{\"level\":\"${auth_level}\",\"status\":${auth_status},\"msg\":\"${auth_msg}\",\"latency_ms\":${auth_latency}}"]]},{"stream":{"job":"worker","env":"prod","instance":"worker-1"},"values":[["$(ts_nano 6)","{\"level\":\"${worker_level}\",\"msg\":\"${worker_msg}\",\"latency_ms\":${worker_latency},\"queue\":\"${worker_queue}\"}"]]}]}
ENDPAYLOAD

  # POST via curl — reads from file, no shell escaping issues
  http_code=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST \
    -H "Content-Type: application/json" \
    --data-binary "@${PAYLOAD_FILE}" \
    "$LOKI_URL")

  if [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
    echo "[$(date '+%H:%M:%S')] Pushed batch (api, web, auth, worker) - HTTP ${http_code}"
  else
    echo "[$(date '+%H:%M:%S')] Failed to push batch - HTTP ${http_code}"
    # Show payload for debugging on first failure
    if [ -z "$_showed_debug" ]; then
      echo "  Payload sample (first 500 chars):"
      head -c 500 "$PAYLOAD_FILE"
      echo ""
      _showed_debug=1
    fi
  fi
}

# Main loop --------------------------------------------------------------

echo "=== go-logql Log Simulator ==="
echo "Pushing logs to Loki at ${LOKI_URL}"
echo "Services: api (prod+staging), web, auth, worker"
echo "Interval: every 2 seconds"
echo ""

# Push an initial larger batch so there is data immediately
for i in $(seq 1 10); do
  send_batch
done
echo ""
echo "Initial batch sent. Continuing..."
echo ""

# Continuous loop
while true; do
  send_batch
  sleep 2
done
