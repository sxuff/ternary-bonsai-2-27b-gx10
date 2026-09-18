#!/bin/bash
# Download models from HuggingFace
set -euo pipefail

mkdir -p /home/sxuf/models
cd /home/sxuf/models

if [ ! -f Ternary-Bonsai-2-27B-PTQ1_0/Ternary-Bonsai-2-27B-PTQ1_0.gguf ]; then
  echo "Downloading PTQ1_0..."
  huggingface-cli download prism-ml/Ternary-Bonsai-2-27B-gguf \
    Ternary-Bonsai-2-27B-PTQ1_0.gguf \
    --local-dir Ternary-Bonsai-2-27B-PTQ1_0
fi

if [ ! -f Ternary-Bonsai-2-27B-PQ2_0/Ternary-Bonsai-2-27B-PQ2_0.gguf ]; then
  echo "Downloading PQ2_0..."
  huggingface-cli download prism-ml/Ternary-Bonsai-2-27B-gguf \
    Ternary-Bonsai-2-27B-PQ2_0.gguf \
    --local-dir Ternary-Bonsai-2-27B-PQ2_0
fi
