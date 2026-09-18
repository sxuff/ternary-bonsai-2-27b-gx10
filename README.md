# Ternary-Bonsai-2-27B on one DGX Spark (GB10)

Verified recipe for serving `prism-ml/Ternary-Bonsai-2-27B-gguf` on one NVIDIA GB10 (128 GB unified memory) with the PrismML llama.cpp fork.

## Verified stack

- Hardware: NVIDIA GB10, 128 GB unified LPDDR5X, aarch64, CUDA 13.0, driver 580.159.03
- Model: `prism-ml/Ternary-Bonsai-2-27B-gguf`
- Base model: Qwen3.8-27B (hybrid attention, ~75% linear / ~25% full)
- Quality: 84.78 avg across 14 thinking benchmarks = **98.2% of FP16**
- Architecture: 27.36B params, 262K context, GGUF v3

## Measured llama-bench results (5 reps, full offload, flash attn, SM121)

| Format | Size | pp512 (t/s) | tg128 (t/s) | Quality |
|--------|------|-------------|-------------|---------|
| **PTQ1_0** (1.75 bpw ternary) | 5.53 GiB | 454.6 | **34.21** | Best quality/size |
| PQ2_0 (2.13 bpw ternary) | 6.70 GiB | 1025.2 | 29.56 | Fast prefill |
| Q2_0 (group 64) | 7.09 GiB | 1017.7 | 28.64 | Wider compatibility |

**Best tok/s: PTQ1_0 at 34.21 tok/s tg128** (single spark, no drafter).

## Served benchmark (PTQ1_0, single slot, 16K ctx, temperature 0)

### Short prompts
- Code generation (512 tokens): **~33 tok/s**
- Math reasoning: **~33 tok/s**
- Chat/conversational: **~33 tok/s**
- All short prompts: ~32.9 tok/s average

### Long prompts (4K-8K input)
- 4K code review: 30.00 tok/s
- 8K document summary: 30.56 tok/s
- 2K copy task: 32.49 tok/s
- 4K structured transform: 31.53 tok/s

### Concurrency scaling (PTQ1_0, 65K ctx, 4 slots)
| Concurrency | Aggregate tok/s | Per-request average |
|-------------|-----------------|---------------------|
| 1 | 33.0 | 33.0 |
| 2 | 31.8 | 19.2 |
| 4 | 50.5 | 16.8 |
| 8 | 52.4 | 15.4 |

Concurrency 4-8 gives ~50-52 tok/s aggregate throughput with 65K context.

## Quality checks (verified working)
- Math: 17 × 24 = 408 (correct, with reasoning chain)
- Code: Fibonacci with memoization (correct, clean Python)
- Thinking mode: enabled by default (reasoning_content stream)

## Limitation: no DSpark drafter

The Ternary-Bonsai-2 model does **not ship with a DSpark drafter**. The older Bonsai-27B (1-bit, Qwen3.6 base) had a drafter that reached **96 tok/s** (2.21x speedup) on GB10. Without a drafter, Ternary-Bonsai-2 is capped at baseline decode.

## Best launch command (PTQ1_0, single slot)

```bash
llama-server \
  -m models/Ternary-Bonsai-2-27B-PTQ1_0/Ternary-Bonsai-2-27B-PTQ1_0.gguf \
  -ngl 99 -fa on -c 16384 -np 1 \
  --host 127.0.0.1 --port 8080 --metrics --slots \
  --cache-prompt
```

## Verdict

**PTQ1_0 is the best tok/s recipe on a single spark at 34.21 tok/s tg128.** Quality is excellent (98.2% of FP16). The model fits in 5.53 GiB, leaving ~122 GB for KV cache and system. Without a DSpark drafter, this is the ceiling for this model family. A custom drafter would be needed to reach the 70-96 tok/s range that DSpark-enabled models achieve.

## Build & runtime

- Source: `PrismML-Eng/llama.cpp`, branch `prism`, commit `1a07bfa5f4144274c8f1c9963821dd9d9a51854b`
- Build: `cmake -B build-gb10 -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=121`
- CUDA: `/usr/local/cuda/bin/nvcc`, toolkit 13.0
- SM121: `-DCMAKE_CUDA_ARCHITECTURES=121`

## Files

- PTQ1_0 model SHA256: `53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3`
- Server binary SHA256: `acef43c5e34cb0073824f5a2ced4948d8c1c69996355662aeda309f9fe001638`
