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
echo "[1/4] Installing system packages..."
apt-get update -qq
apt-get install -y git-lfs screen -qq
git lfs install --skip-repo 2>/dev/null || true
echo "      git-lfs and screen ready."

# ------------------------------------------------------------
# Step 2: Ensure miniconda3 is functional
# miniconda3 が正常に動作することを確認
# ------------------------------------------------------------
echo "[2/4] Checking conda installation..."

if [ ! -f "$CONDA_ROOT/etc/profile.d/conda.sh" ]; then
    echo "      Miniconda not found or incomplete, installing..."
    # Use a specific version pinned to Python 3.10 base
    # Python 3.10 ベースの特定バージョンを使用
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-py310_24.1.2-0-Linux-x86_64.sh \
        -O /tmp/miniconda.sh
    rm -rf "$CONDA_ROOT"
    bash /tmp/miniconda.sh -b -p "$CONDA_ROOT"
    rm /tmp/miniconda.sh
    echo "      Miniconda installed."
else
    echo "      Miniconda OK."
fi

source "$CONDA_ROOT/etc/profile.d/conda.sh"
echo "      Conda $(conda --version) ready."

# Add conda init to .bashrc if not already present
# まだ設定されていない場合は .bashrc に conda の初期化を追加
CONDA_INIT_LINE="source $CONDA_ROOT/etc/profile.d/conda.sh"
if ! grep -qF "$CONDA_INIT_LINE" ~/.bashrc 2>/dev/null; then
    echo "$CONDA_INIT_LINE" >> ~/.bashrc
    echo "alias activate='source $HAMSTER_DIR/activate.sh'" >> ~/.bashrc
fi

# ------------------------------------------------------------
# Step 3: Verify conda env Python stdlib is intact
# conda 環境の Python 標準ライブラリが正常であることを確認
# ------------------------------------------------------------
echo "[3/4] Verifying Python environment..."

conda activate "$CONDA_ENV_PATH"

if ! python -c "import encodings" 2>/dev/null; then
    echo "      Python stdlib corrupted, auto-repairing..."
    echo "      Python 標準ライブラリが破損しています。自動修復中..."
    conda install --prefix "$CONDA_ENV_PATH" python=3.10 --force-reinstall -y -q
    echo "      Python stdlib restored."
fi

python_version=$(python --version 2>&1)
echo "      $python_version OK."

# ------------------------------------------------------------
# Step 4: Start HAMSTER server if not already running
# HAMSTER サーバーが起動していない場合は起動する
# ------------------------------------------------------------
echo "[4/4] Checking HAMSTER server..."

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
