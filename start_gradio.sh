#!/bin/bash
# ============================================================
# HAMSTER Beta - Start Gradio Interface
# HAMSTER Beta - Gradioインターフェースを起動
#
# Run this in Terminal 2 AFTER start_server.sh is ready.
# start_server.shが起動した後、ターミナル2でこれを実行してください。
# Wait for "Uvicorn running on http://0.0.0.0:8000" before starting this.
# これを起動する前に "Uvicorn running on http://0.0.0.0:8000" を確認してください。
# ============================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Activate the 'vila' conda environment only if not already active.
# 'vila' conda環境が未アクティブの場合のみ有効化します。
if [ "$CONDA_DEFAULT_ENV" != "vila" ]; then
    if [ -n "$CONDA_EXE" ]; then
        CONDA_BASE=$(dirname $(dirname "$CONDA_EXE"))
    elif [ -d "/root/miniconda3" ]; then
        CONDA_BASE="/root/miniconda3"
    elif [ -d "$HOME/miniconda3" ]; then
        CONDA_BASE="$HOME/miniconda3"
    else
        CONDA_BASE="$HOME/anaconda3"
    fi
    export PATH="$CONDA_BASE/bin:$PATH"
    source "$CONDA_BASE/etc/profile.d/conda.sh"
    source "$CONDA_BASE/bin/activate" vila
    echo "✅ Activated conda environment: vila"
else
    echo "✅ Already in conda environment: vila"
fi

# Update the IP so Gradio connects to the correct server address
# GradioがサーバーのIPを読み込むため、IPアドレスを更新します
hostname -I | awk '{print $1}' > ip_eth0.txt

echo "========================================"
echo " HAMSTER Beta - Gradio Interface / Gradioインターフェース"
echo " Server expected at / サーバーのアドレス: http://$(cat ip_eth0.txt):8000"
echo " Gradio UI: http://localhost:7860"
echo "========================================"

PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
python gradio_server_example.py