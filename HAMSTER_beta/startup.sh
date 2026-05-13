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
# Step 0: Auto-update this repo from GitHub
# GitHub からリポジトリを自動更新
# ------------------------------------------------------------
REPO_DIR="$WORKSPACE/HAMSTER-Robot-ftlab"
if [ -d "$REPO_DIR/.git" ]; then
    echo "[0/4] Pulling latest scripts from GitHub..."
    BEFORE=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)
    git -C "$REPO_DIR" pull --ff-only 2>&1 | tail -2
    AFTER=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)
    if [ "$BEFORE" != "$AFTER" ]; then
        echo "      Scripts updated — restarting with new version..."
        echo "      スクリプトが更新されました。新バージョンで再起動します..."
        exec bash "$HAMSTER_DIR/startup.sh"
    fi
    echo "      Repo up to date."
fi

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

if ! "$CONDA_ENV_PATH/bin/python" -c "import encodings, urllib.parse, pathlib" 2>/dev/null; then
    echo "      Python stdlib corrupted, rebuilding env from scratch..."
    echo "      Python 標準ライブラリが破損しています。環境を再構築します..."
    conda deactivate 2>/dev/null || true
    conda env remove --prefix "$CONDA_ENV_PATH" -y 2>/dev/null || rm -rf "$CONDA_ENV_PATH"
    conda create --prefix "$CONDA_ENV_PATH" python=3.10 -y -q
    conda activate "$CONDA_ENV_PATH"
    pip install -q \
        torch==2.3.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
    pip install -q \
        transformers==4.37.2 accelerate deepspeed==0.9.5 \
        fastapi==0.125.0 "pydantic<2" "starlette==0.50.0" uvicorn \
        openai pillow gradio einops timm sentencepiece
    pip install -q flash-attn==2.5.8 --no-build-isolation
    echo "      Environment rebuilt."
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

    # Write server launch script to avoid screen quoting issues
    # screen のクォート問題を避けるため起動スクリプトをファイルに書き出す
    cat > /tmp/run_hamster_server.sh << SERVERSCRIPT
#!/bin/bash
export PYTHONPATH=$HAMSTER_DIR/VILA
cd $HAMSTER_DIR
$CONDA_ENV_PATH/bin/python -W ignore server.py \
    --port 8000 \
    --model-path "$MODEL_PATH_REL" \
    --conv-mode vicuna_v1 2>&1 | tee $WORKSPACE/server.log
SERVERSCRIPT
    chmod +x /tmp/run_hamster_server.sh

    screen -dmS hamster-server bash /tmp/run_hamster_server.sh
    echo "      Server starting in screen session 'hamster-server'."
    echo "      Monitor: tail -f $WORKSPACE/server.log"
fi

echo ""
echo "============================================================"
echo " Startup complete! / 起動完了！"
echo " To activate conda env: source $HAMSTER_DIR/activate.sh"
echo " To monitor server:     tail -f $WORKSPACE/server.log"
echo "============================================================"
