#!/usr/bin/env bash
# start-qwen.sh
# Usage: ./start-qwen.sh <project_directory>
# The project directory is where the agent (pi) will run and work.

LLAMA_DIR="/mnt/ssd2_data/llama_testing_moe/llama.cpp"
BIN_DIR="$LLAMA_DIR/build/bin"
MODEL="/mnt/ssd2_data/llama_testing_moe/Qwen3.8-27B-UD-IQ4_XS.gguf"
PORT=8080

# A directory argument is required
if [ -z "$1" ]; then
  echo "Error: please give a directory to run the agent in."
  echo "Usage: $0 <project_directory>"
  exit 1
fi

# Resolve the project directory BEFORE changing directory
WORK_DIR="$(realpath "$1" 2>/dev/null)"
if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ]; then
  echo "Error: directory not found: $1"
  exit 1
fi

# Never let the agent work inside the llama.cpp install
case "$WORK_DIR/" in
  "$LLAMA_DIR"/*)
    echo "Error: $WORK_DIR is inside the llama.cpp folder."
    echo "Pick a project directory outside it so the install can't be modified."
    exit 1
    ;;
esac

cd "$BIN_DIR" || { echo "Cannot cd to $BIN_DIR"; exit 1; }

echo ">>> pi will run in: $WORK_DIR"

# Background watcher: wait until the server is ready, then open pi in a new terminal
(
  until curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; do
    sleep 1
  done
  echo ">>> llama-server is ready on port ${PORT}, launching pi..."

  PI_CMD="cd $(printf '%q' "$WORK_DIR") && export LLAMA_BASE_URL=\"http://127.0.0.1:${PORT}/v1\" && pi; exec bash"

  if command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal -- bash -c "$PI_CMD"
  elif command -v konsole >/dev/null 2>&1; then
    konsole -e bash -c "$PI_CMD"
  elif command -v xfce4-terminal >/dev/null 2>&1; then
    xfce4-terminal -x bash -c "$PI_CMD"
  elif command -v x-terminal-emulator >/dev/null 2>&1; then
    x-terminal-emulator -e bash -c "$PI_CMD"
  else
    echo "No terminal emulator found. Run this manually in another terminal:"
    echo "  cd \"$WORK_DIR\" && export LLAMA_BASE_URL=\"http://127.0.0.1:${PORT}/v1\" && pi"
  fi
) &
WATCHER_PID=$!
trap 'kill $WATCHER_PID 2>/dev/null' EXIT

./llama-server \
  -m "$MODEL" \
  --jinja --alias qwen3.8-27b \
  --ctx-size 36864 --n-gpu-layers 99 -t 8 \
  -b 2048 -ub 512 --parallel 1 --kv-unified --ctx-checkpoints 32 \
  --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 \
  --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0 --repeat-penalty 1.0 \
  --reasoning on --reasoning-budget -1 \
  --spec-type draft-mtp,ngram-mod --spec-draft-n-max 5 --spec-draft-n-min 0 --spec-draft-p-min 0.75 \
  --port "$PORT"
