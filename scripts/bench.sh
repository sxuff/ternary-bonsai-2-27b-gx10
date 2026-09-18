#!/bin/bash
# Run llama-bench on a single spark
set -euo pipefail

MODEL=$1
REPS=${2:-5}
echo "=== llama-bench: $MODEL ($REPS reps) ==="
/home/sxuf/src/llama-bonsai-prism/build-gb10/bin/llama-bench \
  -m "$MODEL" \
  -ngl 99 -fa on -r "$REPS"
