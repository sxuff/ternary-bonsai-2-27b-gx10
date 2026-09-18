#!/bin/bash
# Quick quality smoke test
set -euo pipefail

PORT=${1:-8080}
echo "=== Quality checks on port $PORT ==="

echo "Test 1: math"
curl -s http://127.0.0.1:$PORT/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"Ternary-Bonsai-2-PQ2_0\",\"messages\":[{\"role\":\"user\",\"content\":\"What is 17 x 24? Show your work.\"}],\"max_tokens\":512}" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[\"choices\"][0][\"message\"][\"content\"][:200])"

echo "Test 2: code"
curl -s http://127.0.0.1:$PORT/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"Ternary-Bonsai-2-PQ2_0\",\"messages\":[{\"role\":\"user\",\"content\":\"Write a Python fibonacci with memoization.\"}],\"max_tokens\":512}" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[\"choices\"][0][\"message\"][\"content\"][:200])"

echo "All tests passed."
