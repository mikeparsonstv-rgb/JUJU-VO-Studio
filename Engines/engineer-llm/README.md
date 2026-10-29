# Engineer LLM (local)

The Engineer's language model runs as a loopback OpenAI-compatible server (`mlx_lm.server`) in its own pinned env.

- Env: `Engines/engineer-llm/.venv` (Python 3.12, `mlx-lm==0.31.3`, `mlx==0.32.0`) — created by `setup.sh`, not committed.
- Model: `mlx-community/Qwen3-Coder-Next-4bit` from the existing Hugging Face cache (already on disk; nothing downloaded).
  Chosen over `Qwen3.5-27B-4bit` (also on disk) on measured latency: ~2.5 s vs ~8 s for a 770-token prompt + 80-token reply.
- Served at `http://127.0.0.1:17860/v1` by the app while the Engineer is connected.
