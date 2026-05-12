#!/bin/bash
# =============================================================================
# HAMSTER Startup Script — RunPod On-Start Script
# HAMSTER 起動スクリプト — RunPod 自動起動用スクリプト
#
# Configure this script in RunPod pod settings → "On-Start Script"
# RunPod のポッド設定 → "On-Start Script" にこのスクリプトを設定してください
#
# This script runs on every pod start (even after server migration).
# It assumes /workspace is already set up by deploy.sh.
# このスクリプトはポッド起動のたびに実行されます（サーバー移行後も含む）。
# /workspace は deploy.sh によってセットアップ済みであることを前提とします。
# =============================================================================

WORKSPACE="/workspace"
HAMSTER_DIR="$WORKSPACE/HAMSTER-Robot-ftlab/HAMSTER_beta"
CONDA_ROOT="$WORKSPACE/miniconda3"
CONDA_ENV_PATH="$WORKSPACE/conda-envs/vila"
LOG="$WORKSPACE/startup.log"

exec > >(tee -a "$LOG") 2>&1
echo ""
echo "============================================================"
echo " HAMSTER Startup — $(date)"
echo "============================================================"

# ------------------------------------------------------------
# Step 1: System packages (lost on every pod restart)
# システムパッケージ（ポッド再起動のたびに消える）
# ------------------------------------------------------------
echo "[1/3] Installing system packages..."
apt-get update -qq
apt-get install -y git-lfs screen -qq
git lfs install --skip-repo 2>/dev/null || true
echo "      git-lfs and screen ready."

# ------------------------------------------------------------
# Step 2: Configure PATH and .bashrc for interactive sessions
# インタラクティブセッション用に PATH と .bashrc を設定
# ------------------------------------------------------------
echo "[2/3] Configuring conda PATH..."

# Add conda init to .bashrc if not already present
# まだ設定されていない場合は .bashrc に conda の初期化を追加
CONDA_INIT_LINE="source $CONDA_ROOT/etc/profile.d/conda.sh"
if ! grep -qF "$CONDA_INIT_LINE" ~/.bashrc 2>/dev/null; then
    echo "$CONDA_INIT_LINE" >> ~/.bashrc
    echo "alias activate='source $HAMSTER_DIR/activate.sh'" >> ~/.bashrc
    echo "      Added conda init to ~/.bashrc."
else
    echo "      ~/.bashrc already configured."
fi

# Source for the current session
source "$CONDA_ROOT/etc/profile.d/conda.sh"
echo "      Conda $(conda --version) available."

# ------------------------------------------------------------
# Step 3: Start HAMSTER server if not already running
# HAMSTER サーバーが起動していない場合は起動する
# ------------------------------------------------------------
echo "[3/3] Checking HAMSTER server..."

if pgrep -f "server.py" > /dev/null; then
    echo "      Server already running (PID: $(pgrep -f server.py))."
else
    echo "      Server not running, starting..."

    # Find model checkpoint directory dynamically
    # モデルチェックポイントディレクトリを動的に検索
    MODEL_PATH=$(find "$HAMSTER_DIR/Hamster_dev" -name "config.json" \
        -not -path "*/.git/*" 2>/dev/null | head -1 | xargs dirname)

    if [ -z "$MODEL_PATH" ]; then
        echo "ERROR: Model not found. Run deploy.sh first."
        echo "エラー: モデルが見つかりません。先に deploy.sh を実行してください。"
        exit 1
    fi

    MODEL_PATH_REL="${MODEL_PATH#$HAMSTER_DIR/}"
    echo "      Model: $MODEL_PATH_REL"

    conda activate "$CONDA_ENV_PATH"
    export PYTHONPATH="$HAMSTER_DIR/VILA:${PYTHONPATH:-}"

    screen -dmS hamster-server bash -c "
        source $CONDA_ROOT/etc/profile.d/conda.sh
        conda activate $CONDA_ENV_PATH
        export PYTHONPATH=$HAMSTER_DIR/VILA:\$PYTHONPATH
        cd $HAMSTER_DIR
        python -W ignore server.py \
            --port 8000 \
            --model-path \"$MODEL_PATH_REL\" \
            --conv-mode vicuna_v1 2>&1 | tee $WORKSPACE/server.log
    "
    echo "      Server starting in screen session 'hamster-server'."
    echo "      Monitor: tail -f $WORKSPACE/server.log"
fi

echo ""
echo "============================================================"
echo " Startup complete! / 起動完了！"
echo " To activate conda env: source $HAMSTER_DIR/activate.sh"
echo " To monitor server:     tail -f $WORKSPACE/server.log"
echo "============================================================"
