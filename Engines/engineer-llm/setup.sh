#!/bin/bash
set -e
cd "$(dirname "$0")"
[ -x .venv/bin/python ] || uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python "mlx-lm==0.31.3" "mlx==0.32.0"
.venv/bin/python -c "import mlx_lm, mlx.core as mx; print('mlx_lm', mlx_lm.__version__, 'mlx', mx.__version__)"
