#!/bin/bash
# =============================================================================
# HAMSTER Environment Activation
# HAMSTER 環境アクティベーション
#
# Usage / 使い方:
#   source activate.sh
#
# This script activates the conda environment and sets up the PYTHONPATH.
# conda 環境をアクティベートし、PYTHONPATH を設定します。
# =============================================================================

WORKSPACE="/workspace"
HAMSTER_DIR="$WORKSPACE/HAMSTER-Robot-ftlab/HAMSTER_beta"
CONDA_ROOT="$WORKSPACE/miniconda3"
CONDA_ENV_PATH="$WORKSPACE/conda-envs/vila"

# Initialize conda shell functions (always needed for conda activate)
# conda activate に必要なシェル関数を常に初期化
source "$CONDA_ROOT/etc/profile.d/conda.sh"

conda activate "$CONDA_ENV_PATH"
export PYTHONPATH="$HAMSTER_DIR/VILA:${PYTHONPATH:-}"
cd "$HAMSTER_DIR"

echo "HAMSTER environment activated / HAMSTER 環境がアクティブになりました"
echo "  Python:     $(python --version)"
echo "  Conda env:  $CONDA_ENV_PATH"
echo "  Directory:  $HAMSTER_DIR"
echo ""
echo "Start server:  python -W ignore server.py --port 8000 --model-path <path> --conv-mode vicuna_v1"
echo "Start Gradio:  python gradio_server_example.py"
