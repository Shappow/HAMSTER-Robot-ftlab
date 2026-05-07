#!/bin/bash
# ============================================================
# HAMSTER Beta - Start Inference Server
# HAMSTER Beta - 推論サーバーを起動
#
# Run this in Terminal 1 before starting the Gradio interface.
# Gradioインターフェースを起動する前に、ターミナル1でこれを実行してください。
# ============================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Activate the 'vila' conda environment only if not already active.
# If already in 'vila', skip to avoid resetting the environment.
# 'vila' conda環境が未アクティブの場合のみ有効化します。
# すでに 'vila' にいる場合はスキップして環境のリセットを防ぎます。
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

# Automatically find the model directory inside Hamster_dev/
# Hamster_dev/内のモデルディレクトリを自動検索します
MODEL_DIR=$(find Hamster_dev -mindepth 2 -maxdepth 2 -name "config.json" -exec dirname {} \; 2>/dev/null | head -1)

if [ -z "$MODEL_DIR" ]; then
    echo "❌ Model not found in Hamster_dev/ / モデルがHamster_dev/に見つかりません"
    echo "   Please run setup first: ./setup.sh"
    echo "   先にセットアップを実行してください: ./setup.sh"
    exit 1
fi

# Update the local IP address (needed for Gradio to connect)
# ローカルIPアドレスを更新します（GradioがサーバーにIPを読み込むため必要）
hostname -I | awk '{print $1}' > ip_eth0.txt

echo "========================================"
echo " HAMSTER Beta - Inference Server / 推論サーバー"
echo " Model / モデル: $MODEL_DIR"
echo " URL: http://$(cat ip_eth0.txt):8000"
echo "========================================"

# expandable_segments=True reduces VRAM fragmentation,
# which helps avoid out-of-memory errors during inference.
#
# expandable_segments=Trueは推論中のVRAMフラグメンテーションを減らし、
# メモリ不足エラーを防ぐのに役立ちます。
PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
python -W ignore server.py \
    --port 8000 \
    --model-path "$MODEL_DIR" \
    --conv-mode vicuna_v1