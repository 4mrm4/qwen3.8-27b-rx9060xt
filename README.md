# Qwen3.8 27B on an RX 9060 XT 16GB (llama.cpp, Vulkan)

Tuned `llama-server` settings for running Qwen3.8 27B (UD-IQ4_XS) fully on the GPU of a 16GB RX 9060 XT, with speculative decoding and a 36,864 token context. A launcher script starts the server, waits for it to be ready, and opens the [`pi`](TODO: link to pi) coding agent in your project folder.

These are the settings I settled on after testing a handful of options on one machine. They are not an exhaustive search, so treat them as a good starting point.

## Results

Test prompt: 8,251 tokens (a single-file voxel game plus a request to add a day/night cycle and return the full file), 1,024 tokens generated. Each config was run 3 times with `temperature: 0`, a fixed seed and prompt caching off. Generation figures for the speculative config use runs 2 and 3, because run 1 is slower while the n-gram cache warms up.

| Config | Prompt processing | Generation | Draft acceptance | VRAM (whole GPU) |
|---|---|---|---|---|
| Speculative decoding on (this repo's default) | ~488 t/s | ~26.6 t/s (23.0 to 27.4) | ~87% | ~16.0 GB |
| Speculative decoding off | ~540 t/s | ~17.8 t/s | n/a | ~15.1 GB |

- Speculative decoding gives about 1.5x faster generation. The cost is roughly 10% slower prompt processing and about 0.85 GB more VRAM.
- Speculation works best when the output repeats existing text, such as code edits. Free-form prose will gain less.
- VRAM figures are read from `/sys/class/drm/card*/device/mem_info_vram_used` and include everything on the GPU, such as the desktop.

## My setup

| | |
|---|---|
| GPU | AMD Radeon RX 9060 XT 16GB |
| Backend | Vulkan, Mesa RADV (TODO: Mesa version) |
| OS | Zorin OS |
| llama.cpp | build 74a7c897f (10820) |
| Model | [Qwen3.8-27B-UD-IQ4_XS.gguf](TODO: model link), 13.26 GiB, 4.25 bpw |

## Usage

```bash
git clone https://github.com/<your-username>/qwen3.8-27b-rx9060xt
cd qwen3.8-27b-rx9060xt
chmod +x start-qwen.sh
```

Edit `LLAMA_DIR` and `MODEL` at the top of `start-qwen.sh` to match your machine, then:

```bash
./start-qwen.sh ~/projects/my-app
```

- A project directory is required on purpose. Use `.` for the current folder.
- The script refuses a directory inside the llama.cpp folder, so the agent cannot modify your install.
- The server runs in your current terminal. When `/health` reports ready, a second terminal opens in your project directory with `LLAMA_BASE_URL` set and runs `pi`.
- Ctrl+C in the first terminal stops the server.

Requirements: llama.cpp built with Vulkan and recent enough to support the flags below (including MTP speculative decoding), the GGUF file, `pi` on your PATH, `curl`, and one of gnome-terminal, konsole, xfce4-terminal or x-terminal-emulator.

To save about 0.85 GB of VRAM, delete the two `--spec-*` lines from the script. You will lose the generation speedup.

## Settings explained

| Flag | Purpose |
|---|---|
| `--n-gpu-layers 99` | Offload every layer to the GPU |
| `--ctx-size 36864` | Largest context I got to fit in 16GB alongside the model |
| `--cache-type-k q8_0 --cache-type-v q8_0` | Quantized KV cache to save VRAM |
| `--flash-attn on` | Flash attention |
| `-b 2048 -ub 512` | Batch and micro-batch sizes |
| `--kv-unified` | Unified KV buffer, so one request can use the whole context |
| `--ctx-checkpoints 32` | Keeps up to 32 context checkpoints (about 150 MiB each) so follow-up turns in an agent session can reuse earlier context |
| `--jinja` | Use the model's own chat template, needed for tool calling |
| `--reasoning on --reasoning-budget -1` | Thinking enabled with no token cap |
| `--temp 1.0 --top-k 20 --top-p 0.95 --min-p 0 --repeat-penalty 1.0` | Sampling settings I use |
| `--spec-type draft-mtp,ngram-mod` | Speculative decoding from the model's MTP head plus n-gram drafting |
| `--spec-draft-n-max 5 --spec-draft-n-min 0 --spec-draft-p-min 0.75` | Draft up to 5 tokens, with a minimum draft probability of 0.75 |

## Gotchas

**Do not use `--parallel 1`.** With this model on Vulkan (RADV), adding `--parallel 1` cut prompt processing from about 540 t/s to about 160 t/s on the 8k prompt, and slowed generation too. Leaving it out lets llama.cpp pick its default slot count (4 here); with a unified KV cache a single request can still use the full context. I found this by starting from a minimal server and adding flags back until the speed dropped. I don't know the underlying cause.

**VRAM is tight.** At 36,864 context with speculative decoding the GPU sits at about 16.0 GB used. If you get out-of-memory errors, lower `--ctx-size` (for example to 32768), close GPU-heavy apps, or turn off speculative decoding.

**Harmless warning:** with speculative decoding off, llama.cpp logs "unused tensor blk.64..." lines. That is the MTP layer being ignored.

## Other things I measured

`llama-bench`, pp2048 at 8192 tokens of depth (higher is better):

| KV cache (K / V) | t/s |
|---|---|
| f16 / f16 | 518 |
| q8_0 / q8_0 | 514 |
| f16 / q8_0 | 495 |
| q8_0 / f16 | 497 |

q8_0 for both K and V costs about 1% speed versus f16 and saves VRAM. Avoid mixing types, which was slower than either matching pair.

Plain generation with `llama-bench` at zero depth (tg128, q8_0 KV, flash attention on) read about 13.7 t/s, and prompt processing about 460 to 560 t/s depending on prompt size.

I also tried `--ctx-checkpoints 1` and `--ctx-size 12288` while hunting the slowdown above. Neither changed prompt speed meaningfully, but those tests were run while `--parallel 1` was still set.

## Reproducing the numbers

1. Start the server by hand with the same flags as the script (no `pi`).
2. Put your prompt in `prompt.txt` and run `./bench-request.sh`. It sends the prompt three times with `cache_prompt: false` and prints `prompt_per_second`, `predicted_per_second` and the draft counts from the server's timings. Needs `jq` and `curl`.
3. Watch VRAM with `watch -n1 'for f in /sys/class/drm/card*/device/mem_info_vram_used; do echo "$f: $(( $(cat $f) / 1048576 )) MiB"; done'`.

Results will vary with your prompt. Code editing tasks that repeat existing text benefit most from speculative decoding.

## License

MIT
