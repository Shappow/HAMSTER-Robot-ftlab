#!/bin/bash
# =============================================================================
# HAMSTER Deployment Script for RunPod (NVIDIA A40 / CUDA 12.x)
# RunPod (NVIDIA A40 / CUDA 12.x) 用 HAMSTER デプロイスクリプト
#
# Usage / 使い方:
#   bash deploy.sh            # Full setup + start server / フルセットアップ + サーバー起動
#   bash deploy.sh --setup-only  # Setup only, don't start server / セットアップのみ
#
# Everything is stored under /workspace so it persists across pod restarts.
# /workspace 以下にすべて保存されるため、Pod の再起動後も維持されます。
# =============================================================================

set -eo pipefail
# Note: -u (treat unbound vars as errors) is intentionally omitted.
# conda activate/install sources third-party scripts (cuda-toolkit, etc.)
# that reference variables like CUDAARCHS_BACKUP and NVCC_PREPEND_FLAGS
# which may be unset in a fresh shell — -u would abort on those.

# ============================================================
# Configuration / 設定
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="/workspace"
HAMSTER_DIR="$SCRIPT_DIR"
VILA_DIR="$HAMSTER_DIR/VILA"
MODEL_REPO_DIR="$HAMSTER_DIR/Hamster_dev"
CONDA_ROOT="$WORKSPACE/miniconda3"
CONDA_ENV_NAME="vila"
CONDA_ENV_PATH="$WORKSPACE/conda-envs/$CONDA_ENV_NAME"
LOG="$WORKSPACE/deploy.log"

# VILA repository commit (pinned for compatibility / 互換性のため固定)
VILA_COMMIT="a5a380d6d09762d6f3fd0443aac6b475fba84f7e"

# flash_attn pre-built wheel — avoids 30-min compilation
# flash_attn ビルド済みホイール — 30分のコンパイルを回避
FLASH_ATTN_WHEEL="https://github.com/Dao-AILab/flash-attention/releases/download/v2.5.8/flash_attn-2.5.8+cu122torch2.3cxx11abiFALSE-cp310-cp310-linux_x86_64.whl"

START_SERVER=true
if [[ "${1:-}" == "--setup-only" ]]; then
    START_SERVER=false
fi

# ============================================================
# Logging / ログ設定
# ============================================================
exec > >(tee -a "$LOG") 2>&1
echo ""
echo "============================================================"
echo " HAMSTER Deploy — $(date)"
echo "============================================================"

# ============================================================
# Step 1: System packages / システムパッケージ
# git-lfs and screen are not persisted — reinstall each boot.
# git-lfs と screen は永続化されないため、起動のたびに再インストール。
# ============================================================
echo "[1/8] Installing system packages (git-lfs, screen)..."
apt-get update -qq
apt-get install -y git-lfs screen -qq
git lfs install --skip-repo 2>/dev/null || git lfs install
echo "      System packages OK."

# ============================================================
# Step 2: Miniconda / Miniconda インストール
# Stored in /workspace so it survives pod restarts.
# /workspace に保存し、Pod 再起動後も維持。
# ============================================================
echo "[2/8] Checking Miniconda..."
if [ ! -f "$CONDA_ROOT/bin/conda" ]; then
    echo "      Installing Miniconda to $CONDA_ROOT..."
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
    bash /tmp/miniconda.sh -b -u -p "$CONDA_ROOT"
    rm /tmp/miniconda.sh
    echo "      Miniconda installed."
else
    echo "      Miniconda already present, skipping."
fi

export PATH="$CONDA_ROOT/bin:$PATH"
eval "$("$CONDA_ROOT/bin/conda" shell.bash hook)"

# Accept Anaconda ToS (required since 2024 / 2024年より必須)
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main 2>/dev/null || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r 2>/dev/null || true

# Store conda envs in /workspace for persistence / 永続化のため /workspace に保存
conda config --add envs_dirs "$WORKSPACE/conda-envs" 2>/dev/null || true

# ============================================================
# Step 3: Conda environment / Conda 環境
# ============================================================
echo "[3/8] Checking conda environment '$CONDA_ENV_NAME'..."
if [ ! -f "$CONDA_ENV_PATH/bin/python3.10" ]; then
    echo "      Creating conda env at $CONDA_ENV_PATH (Python 3.10)..."
    conda create --prefix "$CONDA_ENV_PATH" python=3.10 -y
    echo "      Conda env created."
else
    echo "      Conda env already present, skipping."
fi
conda activate "$CONDA_ENV_PATH"
echo "      Python: $(python --version)"

# ============================================================
# Step 4: VILA repository / VILA リポジトリ
# Clone at the pinned commit required by HAMSTER.
# HAMSTER が要求する固定コミットでクローン。
# ============================================================
echo "[4/8] Checking VILA repository..."
if [ ! -d "$VILA_DIR/.git" ]; then
    echo "      Cloning VILA..."
    cd "$HAMSTER_DIR"
    rm -rf VILA
    git clone https://github.com/NVlabs/VILA.git
    cd VILA
    git checkout "$VILA_COMMIT"
    echo "      VILA cloned at commit $VILA_COMMIT."
else
    echo "      VILA already cloned, skipping."
fi

# ============================================================
# Step 5: Python dependencies / Python 依存関係
# Follow the official VILA environment_setup.sh procedure.
# 公式 VILA environment_setup.sh の手順に従う。
# ============================================================
echo "[5/8] Installing Python dependencies..."
pip install --upgrade pip -q

# CUDA toolkit via conda (needed for some VILA ops / 一部の VILA 操作に必要)
if ! conda list -p "$CONDA_ENV_PATH" | grep -q "^cuda-toolkit"; then
    echo "      Installing cuda-toolkit via conda..."
    conda install -p "$CONDA_ENV_PATH" -c nvidia cuda-toolkit -y -q
fi

# flash_attn: pre-built wheel, no compilation required
# flash_attn: ビルド済みホイール、コンパイル不要
if ! python -c "import flash_attn" 2>/dev/null; then
    echo "      Installing flash_attn (pre-built wheel, no compilation)..."
    pip install "$FLASH_ATTN_WHEEL" -q
    echo "      flash_attn installed."
else
    echo "      flash_attn already installed, skipping."
fi

# VILA packages (official order / 公式の順序)
cd "$VILA_DIR"
if ! python -c "import llava" 2>/dev/null; then
    echo "      Installing VILA (pip install -e .)..."
    pip install -e . -q 2>&1 | tail -2
    pip install -e ".[train]" -q 2>&1 | tail -2
    pip install -e ".[eval]" -q 2>&1 | tail -2

    # Pin transformers to the version required by VILA
    # VILA が要求するバージョンの transformers をインストール
    echo "      Installing transformers@v4.37.2..."
    pip install "git+https://github.com/huggingface/transformers@v4.37.2" -q 2>&1 | tail -2

    # Apply VILA patches to transformers and deepspeed
    # transformers と deepspeed に VILA パッチを適用
    SITE_PKG="$(python -c 'import site; print(site.getsitepackages()[0])')"
    cp -r "$VILA_DIR/llava/train/transformers_replace/"* "$SITE_PKG/transformers/"
    cp -r "$VILA_DIR/llava/train/deepspeed_replace/"* "$SITE_PKG/deepspeed/" 2>/dev/null || true
    echo "      VILA installed."
else
    echo "      VILA already installed, skipping."
fi

# Extra packages for the server and Gradio interface
# サーバーと Gradio インターフェース用の追加パッケージ
pip install fastapi uvicorn opencv-python matplotlib python-multipart pillow requests -q 2>&1 | tail -1

# ============================================================
# Step 6: Code patches / コードパッチ
# Fix known incompatibilities between VILA and inference mode.
# VILA と推論モードの既知の非互換性を修正。
# ============================================================
echo "[6/8] Applying code patches..."

# Patch 1: Make deepspeed import optional in sequence_parallel/globals.py
# deepspeed のインポートを sequence_parallel/globals.py でオプションにする
GLOBALS_PY="$VILA_DIR/llava/train/sequence_parallel/globals.py"
if grep -q "^import deepspeed.comm as dist" "$GLOBALS_PY"; then
    sed -i 's/^import deepspeed.comm as dist$/try:\n    import deepspeed.comm as dist\nexcept Exception:\n    import torch.distributed as dist/' "$GLOBALS_PY"
    echo "      Patched globals.py (deepspeed optional import)."
fi


# Patch 3: Fix model name in gradio_server_example.py (case mismatch)
# gradio_server_example.py のモデル名を修正（大文字小文字の不一致）
GRADIO_PY="$HAMSTER_DIR/gradio_server_example.py"
if grep -q 'MODEL = "Hamster_dev"' "$GRADIO_PY"; then
    sed -i 's/MODEL = "Hamster_dev"/MODEL = "HAMSTER_dev"/' "$GRADIO_PY"
    echo "      Patched gradio_server_example.py (MODEL name corrected)."
fi

echo "      All patches applied."

# Check example images for Gradio UI (optional but shown in the interface)
# Gradio UI 用のサンプル画像を確認（オプションだがインターフェースに表示）
EXAMPLES_DIR="$HAMSTER_DIR/examples"
MISSING=0
for img in ocr_reasoning.jpg non_prehensile.jpg spatial_world_knowledge.jpg; do
    [ ! -f "$EXAMPLES_DIR/$img" ] && MISSING=1 && break
done
if [ "$MISSING" -eq 1 ]; then
    echo "      ⚠️  Warning: examples/ images missing — Gradio will launch without demo images."
    echo "      Copy ocr_reasoning.jpg, non_prehensile.jpg, spatial_world_knowledge.jpg into $EXAMPLES_DIR"
else
    echo "      Example images OK."
fi

# ============================================================
# Step 7: Model download / モデルのダウンロード
# The model is large (~50 GB). Skip if already present.
# モデルは大容量（約50GB）。既にある場合はスキップ。
# ============================================================
echo "[7/8] Checking model..."
if [ ! -d "$MODEL_REPO_DIR/.git" ]; then
    echo "      Downloading model from HuggingFace (yili18/Hamster_dev, ~50 GB)..."
    cd "$HAMSTER_DIR"
    GIT_LFS_SKIP_SMUDGE=1 git clone https://huggingface.co/yili18/Hamster_dev
    cd Hamster_dev
    git lfs pull
    echo "      Model downloaded."
else
    echo "      Model already present ($(du -sh "$MODEL_REPO_DIR" 2>/dev/null | cut -f1))."
fi

# Find the model checkpoint directory (contains config.json)
# config.json を含むモデルチェックポイントディレクトリを検索
MODEL_PATH=$(find "$MODEL_REPO_DIR" -name "config.json" -not -path "*/.git/*" | head -1 | xargs dirname)
if [ -z "$MODEL_PATH" ]; then
    echo "ERROR: Could not find model config.json inside $MODEL_REPO_DIR"
    exit 1
fi
# Make path relative to HAMSTER_DIR for portability
# 移植性のため HAMSTER_DIR からの相対パスに変換
MODEL_PATH_REL="${MODEL_PATH#$HAMSTER_DIR/}"
echo "      Model path: $MODEL_PATH_REL"

# Save IP address / IP アドレスを保存
ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 > "$HAMSTER_DIR/ip_eth0.txt" || \
    hostname -I | awk '{print $1}' > "$HAMSTER_DIR/ip_eth0.txt" || true
echo "      Server IP: $(cat "$HAMSTER_DIR/ip_eth0.txt" 2>/dev/null || echo 'unknown')"

# ============================================================
# Step 8: Start server / サーバー起動
# ============================================================
if [ "$START_SERVER" = false ]; then
    echo "[8/8] --setup-only flag set, skipping server start."
    echo ""
    echo "Setup complete! To start the server manually:"
    echo "セットアップ完了！サーバーを手動で起動するには:"
    echo ""
    echo "  source $CONDA_ROOT/etc/profile.d/conda.sh"
    echo "  conda activate $CONDA_ENV_PATH"
    echo "  export PYTHONPATH=$VILA_DIR:\$PYTHONPATH"
    echo "  cd $HAMSTER_DIR"
    echo "  python -W ignore server.py --port 8000 --model-path \"$MODEL_PATH_REL\" --conv-mode vicuna_v1"
    exit 0
fi

echo "[8/8] Starting HAMSTER server on port 8000..."
export PYTHONPATH="$VILA_DIR:${PYTHONPATH:-}"

cd "$HAMSTER_DIR"
echo "      Model: $MODEL_PATH_REL"
echo "      Logs:  /workspace/server.log"
echo ""
echo "============================================================"
echo " Server starting. To monitor: tail -f /workspace/server.log"
echo " サーバー起動中。監視: tail -f /workspace/server.log"
echo ""
echo " To use Gradio UI (in another terminal):"
echo " Gradio UI の起動（別ターミナルで）:"
echo "   conda activate $CONDA_ENV_PATH"
echo "   cd $HAMSTER_DIR && python gradio_server_example.py"
echo "============================================================"

python -W ignore server.py \
    --port 8000 \
    --model-path "$MODEL_PATH_REL" \
    --conv-mode vicuna_v1
