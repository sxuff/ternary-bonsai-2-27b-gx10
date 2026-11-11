#!/usr/bin/env bash
# run.sh - one-command setup and launch for this recipe on one NVIDIA GB10.
#
#   git clone https://github.com/sxuff/ternary-bonsai-2-27b-gx10 && cd ternary-bonsai-2-27b-gx10 && ./run.sh
#
# Every pin and flag below is copied from this repo's README, manifests or
# receipts; the comment next to each value names its source. Nothing here
# tunes, "improves" or changes a measured setting.
set -euo pipefail
cd "$(dirname "$0")"
REPO_DIR="$(pwd)"

# ===================== recipe config (per repo) =============================
RECIPE_NAME="ternary-bonsai-2-27b-gx10"
PORT="${PORT:-8080}"                             # source: README.md:62 (--port 8080)
MODELS_DIR="${MODELS_DIR:-$HOME/models}"         # same layout as scripts/download.sh:5-12
SRC_DIR="${SRC_DIR:-$HOME/src}"
STATE_DIR="${STATE_DIR:-$HOME/.local/state/ternary-bonsai-2-27b-gx10}"
NEEDS_TOOLS="git curl sha256sum cmake make"      # cmake/make: README.md:73 build (Unix Makefiles)
NEED_MEM_BYTES=0                                 # the repo states no memory guard; README.md:68 only notes the 5.53 GiB model leaves ~122 GB free
ENGINE_DISK_BYTES=0                              # no build-tree size is stated anywhere in the repo
ENGINE_KIND=process                              # README.md:59 runs llama-server directly, no container
CONTAINER_NAME=""                                # docker only
READY_URL="http://127.0.0.1:${PORT}/health"      # llama-server health endpoint
READY_TIMEOUT=1200                               # seconds; no start-up time is stated in the repo (template default)
EXPECTED_LINE="34.21 tok/s (llama-bench tg128, 5 reps, full offload, flash attn)"  # README.md:13,21; manifests/ptq1_0.json benchmark.tg128
RECEIPT_PATH="manifests/ptq1_0.json"

# One line per file:  <sha256> <bytes> <hf_repo> <revision> <path-in-repo> <dest-relative-to-MODELS_DIR>
# sha256: manifests/ptq1_0.json:8 (same value in README.md:79).
# revision + bytes: the repo pins no HF revision (scripts/download.sh:10 downloads the live head).
#   6ed5e12bf84b7a63069882c91dd9e9218647d17b is the prism-ml/Ternary-Bonsai-2-27B-gguf commit live
#   when the recipe was published (2026-09-17); the revision was chosen by checksum match: its
#   Ternary-Bonsai-2-27B-PTQ1_0.gguf (5,946,648,928 bytes) has exactly the manifest's SHA-256
#   (Hub check 2026-11-11).
# Only PTQ1_0 (the headline profile) is downloaded; PQ2_0 has no checksum in this repo.
WEIGHTS="
53107f530aa52eb00912263ab1ee29bd199261c87cd7b4ad4ca1318c1fe33ee3 5946648928 prism-ml/Ternary-Bonsai-2-27B-gguf 6ed5e12bf84b7a63069882c91dd9e9218647d17b Ternary-Bonsai-2-27B-PTQ1_0.gguf Ternary-Bonsai-2-27B-PTQ1_0/Ternary-Bonsai-2-27B-PTQ1_0.gguf
"

# The repo's own downloader (scripts/download.sh) pins no revision and hardcodes /home/sxuf,
# so the shared pinned-revision + SHA-256 weights step below is used instead.

# Engine: PrismML-Eng/llama.cpp, branch prism, commit 1a07bfa5... (README.md:72).
ENGINE_URL="https://github.com/PrismML-Eng/llama.cpp"
ENGINE_SHA="1a07bfa5f4144274c8f1c9963821dd9d9a51854b"   # README.md:72
ENGINE_SRC="$SRC_DIR/llama.cpp-prism"
ENGINE_BIN="$ENGINE_SRC/build-gb10/bin/llama-server"    # build dir name: README.md:73 (-B build-gb10)

engine_step() {   # build or pull the pinned engine; must skip work already done
  git_pin "$ENGINE_URL" "$ENGINE_SHA" "$ENGINE_SRC"
  if [ -x "$ENGINE_BIN" ]; then ok "built: $ENGINE_BIN"; return; fi
  if [ "$CHECK" = 1 ]; then plan "cmake-configure and build llama-server in $ENGINE_SRC/build-gb10"; return; fi
  # README.md:74: CUDA is /usr/local/cuda/bin/nvcc, toolkit 13.0 (nvcc may not be on PATH).
  [ -x /usr/local/cuda/bin/nvcc ] || die "nvcc not found at /usr/local/cuda/bin/nvcc (README.md:74)"
  export PATH="/usr/local/cuda/bin:$PATH"
  # Configure exactly as README.md:73.
  (cd "$ENGINE_SRC" && cmake -B build-gb10 -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=121)
  # The README gives no build line; this build-target line is the only addition to its commands.
  (cd "$ENGINE_SRC" && cmake --build build-gb10 -j --target llama-server)
  [ -x "$ENGINE_BIN" ] || die "build finished but $ENGINE_BIN is missing"
  ok "built: $ENGINE_BIN"
}

serve_step() {    # start the server in the background (pid file or detached container)
  # Flags verbatim from README.md:58-63, "Best launch command (PTQ1_0, single slot)".
  # Only the model path (MODELS_DIR layout, as scripts/download.sh) and --port (PORT
  # override) are parameterized; every flag value is unchanged.
  local cmd=("$ENGINE_BIN"
    -m "$MODELS_DIR/Ternary-Bonsai-2-27B-PTQ1_0/Ternary-Bonsai-2-27B-PTQ1_0.gguf"
    -ngl 99 -fa on -c 16384 -np 1
    --host 127.0.0.1 --port "$PORT" --metrics --slots
    --cache-prompt)
  if [ "$CHECK" = 1 ]; then plan "start: ${cmd[*]}"; return; fi
  nohup "${cmd[@]}" >"$LOGFILE" 2>&1 & echo $! >"$PIDFILE"
  ok "started (pid $(cat "$PIDFILE"))"
}

curl_test() {     # printed after start-up
  # The repo's own smoke request (tests/quality.sh:8-12), without its "model" field:
  # the README launch command sets no -a alias, so the request names no model.
  cat <<EOF
curl -s http://127.0.0.1:${PORT}/v1/chat/completions -H "Content-Type: application/json" \\
  -d '{"messages":[{"role":"user","content":"What is 17 x 24? Show your work."}],"max_tokens":512}'
EOF
}
# ===================== end of recipe config =================================

# ---------------------------------------------------------------------------
# Shared machinery (identical in every sxuff recipe repo).
# ---------------------------------------------------------------------------
CHECK=0; ACTION=run
usage() {
  cat <<EOF
Usage: ./run.sh [--check] [--stop] [--help]

Sets up and launches ${RECIPE_NAME} on one NVIDIA GB10 (SM121).

  (no flag)  check the machine, build or pull the pinned engine, download the
             pinned weights, verify SHA-256, start the server, print a test.
             Safe to re-run: finished steps are skipped.
  --check    print what would happen; change nothing.
  --stop     stop the server this script started.
  --help     show this text.

Environment:
  HF_TOKEN     Hugging Face token, read from the environment only, never saved.
  MODELS_DIR   weights        (default: ${MODELS_DIR})
  SRC_DIR      engine source  (default: ${SRC_DIR})
  STATE_DIR    pid and log    (default: ${STATE_DIR})
  PORT         server port    (default: ${PORT})

Expected: ${EXPECTED_LINE}
Receipt:  ${RECEIPT_PATH}
EOF
}
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    --stop)  ACTION=stop ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $a (see ./run.sh --help)" >&2; exit 2 ;;
  esac
done

say()  { printf '\n==> %s\n' "$*"; }
ok()   { printf '    ok    %s\n' "$*"; }
plan() { printf '    would %s\n' "$*"; }
die()  { printf '\nerror: %s\n' "$*" >&2; exit 1; }
CHECK_FAILED=0   # under --check, a failed pre-flight check is reported and the plan continues
fail() { if [ "$CHECK" = 1 ]; then printf '    FAIL  %s\n' "$*"; CHECK_FAILED=1; else die "$*"; fi; }
human(){ numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1 B"; }
doit() { if [ "$CHECK" = 1 ]; then plan "$*"; else "$@"; fi; }   # mutate, or describe under --check

PIDFILE="${STATE_DIR}/server.pid"
LOGFILE="${STATE_DIR}/server.log"
STOP_CMD="cd ${REPO_DIR} && ./run.sh --stop"

server_running() {
  if [ "$ENGINE_KIND" = docker ]; then
    [ -n "$(docker ps -q --filter "name=^${CONTAINER_NAME}\$" 2>/dev/null)" ]
  else
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
  fi
}

stop_step() {   # may be overridden in the config block (e.g. to call scripts/stop.sh)
  if ! server_running; then ok "nothing started by this script is running"; return; fi
  if [ "$ENGINE_KIND" = docker ]; then doit docker stop "$CONTAINER_NAME"
  else
    local pid; pid="$(cat "$PIDFILE")"; doit kill "$pid"
    if [ "$CHECK" = 0 ]; then
      for _ in $(seq 1 60); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid"; rm -f "$PIDFILE"
    fi
  fi
  ok "stopped"
}
declare -f stop_override >/dev/null && stop_step() { stop_override; }

if [ "$ACTION" = stop ]; then say "Stopping ${RECIPE_NAME}"; stop_step; exit 0; fi
[ "$CHECK" = 1 ] && say "--check: nothing will be changed"

# git checkout of an exact commit, idempotent. Usage: git_pin <url> <sha> <dir>
git_pin() {
  local url="$1" sha="$2" dir="$3"
  if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD)" = "$sha" ]; then ok "source at ${sha:0:12}: $dir"; return; fi
  if [ ! -d "$dir/.git" ]; then doit git clone --quiet "$url" "$dir"; fi
  if [ "$CHECK" = 1 ]; then plan "check out $sha in $dir"; return; fi
  [ -z "$(git -C "$dir" status --porcelain)" ] || die "$dir has local changes; refusing to move it to $sha"
  git -C "$dir" fetch --quiet origin "$sha" 2>/dev/null || git -C "$dir" fetch --quiet origin
  git -C "$dir" checkout --quiet --detach "$sha"
  [ "$(git -C "$dir" rev-parse HEAD)" = "$sha" ] || die "could not check out $sha in $dir"
  ok "source at ${sha:0:12}: $dir"
}

# docker image by digest, idempotent. Usage: image_pin <repo@sha256:...>
image_pin() {
  if docker image inspect "$1" >/dev/null 2>&1; then ok "image present: $1"; else doit docker pull "$1"; fi
}

# --- 1. machine ------------------------------------------------------------
say "Machine"
[ "$(uname -m)" = aarch64 ] || die "expected aarch64 (GB10), got $(uname -m)"
command -v nvidia-smi >/dev/null || die "nvidia-smi not found"
GPU="$(nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader | head -1)"
case "$GPU" in *GB10*", 12.1") ok "GPU: $GPU" ;; *) die "measured on an NVIDIA GB10 (SM121); found: ${GPU:-none}" ;; esac
for t in $NEEDS_TOOLS; do command -v "$t" >/dev/null || die "missing tool: $t"; done
ok "tools: $NEEDS_TOOLS"
ALREADY=0; server_running && ALREADY=1
MEM_AVAIL=$(( $(awk '/MemAvailable/ {print $2}' /proc/meminfo) * 1024 ))
if [ "$ALREADY" = 1 ]; then ok "server already running; memory check skipped"
elif [ "$MEM_AVAIL" -lt "$NEED_MEM_BYTES" ]; then
  fail "need $(human "$NEED_MEM_BYTES") available memory, have $(human "$MEM_AVAIL"). Stop other models first (nvidia-smi, docker ps)."
else ok "memory: $(human "$MEM_AVAIL") available, need $(human "$NEED_MEM_BYTES")"; fi
if [ "$ALREADY" = 1 ]; then ok "port ${PORT}: served by this recipe"
else
  # The server binds 127.0.0.1 (or the host network). A listener on 127.0.0.1, a wildcard or ::1
  # blocks it; one bound to another interface address does not, and is only reported.
  PORT_ALL="$(ss -ltnH "sport = :${PORT}" 2>/dev/null || true)"
  PORT_CLASH="$(printf '%s\n' "$PORT_ALL" | awk '{print $4}' | grep -E '^(127\.0\.0\.1|0\.0\.0\.0|\*|\[::\]|\[::1\]|\[::ffff:127\.0\.0\.1\]):' || true)"
  PORT_DOCKER="$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -E "(127\.0\.0\.1|0\.0\.0\.0|\[::\]|:::?):${PORT}->" || true)"
  if [ -n "$PORT_CLASH$PORT_DOCKER" ]; then
    printf '    port %s is taken:\n%s\n%s\n' "$PORT" "$PORT_CLASH" "$PORT_DOCKER"
    fail "free port ${PORT} or run: PORT=<other> ./run.sh"
  elif [ -n "$PORT_ALL" ]; then
    ok "port ${PORT}: free on 127.0.0.1 (also bound elsewhere: $(printf '%s' "$PORT_ALL" | awk '{print $4}' | tr '\n' ' '))"
  else ok "port ${PORT}: free"; fi
fi

# --- 2. disk ---------------------------------------------------------------
say "Disk"
nearest_dir() { local d="$1"; while [ ! -d "$d" ]; do d="$(dirname "$d")"; done; echo "$d"; }
NEED_DISK=$ENGINE_DISK_BYTES
while read -r sha size repo rev rpath dest; do
  [ -z "${sha:-}" ] && continue
  have=0; [ -f "$MODELS_DIR/$dest" ] && have=$(stat -c %s "$MODELS_DIR/$dest")
  [ "$have" -lt "$size" ] && NEED_DISK=$(( NEED_DISK + size - have ))
done <<< "$WEIGHTS"
FREE_DISK=$(df -B1 --output=avail "$(nearest_dir "$MODELS_DIR")" | tail -1 | tr -d ' ')
if [ "$FREE_DISK" -ge "$NEED_DISK" ]; then ok "need $(human "$NEED_DISK") more, have $(human "$FREE_DISK")"
else fail "need $(human "$NEED_DISK") more disk under $MODELS_DIR, have $(human "$FREE_DISK"). Nothing was deleted."; fi

# --- 3. engine -------------------------------------------------------------
say "Engine"
engine_step

# --- 4. weights: pinned revision + SHA-256 -----------------------------------
hf_fetch() {   # repo rev path dest. The token reaches curl on stdin: never in argv or a file.
  { [ -n "${HF_TOKEN:-}" ] && printf 'header = "Authorization: Bearer %s"\n' "$HF_TOKEN"; true; } |
    curl --fail --location --retry 5 --retry-delay 5 --continue-at - --config - \
         --output "$4.part" "https://huggingface.co/$1/resolve/$2/$3"
  mv "$4.part" "$4"
}
default_weights_step() {
  while read -r sha size repo rev rpath dest; do
    [ -z "${sha:-}" ] && continue
    local f="$MODELS_DIR/$dest" mark="$MODELS_DIR/$dest.sha256-ok"
    if [ -f "$mark" ] && [ "$(cat "$mark")" = "$sha $size" ] && [ "$(stat -c %s "$f" 2>/dev/null)" = "$size" ]; then
      ok "verified earlier: $dest"; continue
    fi
    if [ "$(stat -c %s "$f" 2>/dev/null || echo 0)" != "$size" ]; then
      if [ "$CHECK" = 1 ]; then plan "download $repo@${rev:0:12} $rpath ($(human "$size"))"; continue; fi
      mkdir -p "$(dirname "$f")"; printf '    get   %s (%s)\n' "$rpath" "$(human "$size")"
      hf_fetch "$repo" "$rev" "$rpath" "$f"
    elif [ "$CHECK" = 1 ]; then plan "verify SHA-256 of $dest"; continue; fi
    local got; got="$(sha256sum "$f" | cut -d' ' -f1)"
    if [ "$got" != "$sha" ]; then mv "$f" "$f.sha256-mismatch"; die "SHA-256 mismatch for $dest: expected $sha, got $got (kept as $f.sha256-mismatch)"; fi
    echo "$sha $size" > "$mark"; ok "sha256 ok: $dest"
  done <<< "$WEIGHTS"
}
declare -f weights_step >/dev/null || weights_step() { default_weights_step; }
say "Weights"
weights_step

# --- 5. serve --------------------------------------------------------------
say "Server"
if [ "$ALREADY" = 1 ]; then ok "already running"
elif [ "$CHECK" = 1 ]; then serve_step
else
  mkdir -p "$STATE_DIR"; serve_step
  printf '    wait  for %s (up to %ss; log: %s)\n' "$READY_URL" "$READY_TIMEOUT" "$LOGFILE"
  t=0
  until curl -fsS -o /dev/null "$READY_URL" 2>/dev/null; do
    server_running || die "server exited during start-up; see $LOGFILE"
    [ "$t" -ge "$READY_TIMEOUT" ] && die "not ready after ${READY_TIMEOUT}s; see $LOGFILE"
    sleep 5; t=$((t + 5))
  done
  ok "ready after ${t}s"
fi

# --- 6. done ---------------------------------------------------------------
if [ "$CHECK" = 1 ]; then
  if [ "$CHECK_FAILED" = 1 ]; then say "Check finished with FAIL lines above; nothing was changed. ./run.sh would stop at the first one."; exit 1; fi
  say "Check finished; nothing was changed. Run ./run.sh to do it."; exit 0
fi
say "Test it"
curl_test
say "Stop it"
echo "$STOP_CMD"
echo
echo "Expected: ${EXPECTED_LINE} - receipt: ${RECEIPT_PATH}"
