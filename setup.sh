#!/bin/bash
# ============================================================
# HAMSTER Beta - Installation Script for RunPod
# HAMSTER Beta - RunPod用インストールスクリプト
#
# Recommended GPU / 推奨GPU: A40 (48GB) or higher / 以上
# RunPod Image / RunPodイメージ:
#   runpod/pytorch:2.1.0-py3.10-cuda12.1.1-devel-ubuntu22.04
# ============================================================
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "========================================"
echo " HAMSTER Beta - Installation"
echo "========================================"

# ── 0. Miniconda ─────────────────────────────────────────────
echo ""
echo "[0/6] Checking Conda / Conda確認..."

# Detect conda path / condaのパスを検出
if [ -n "$CONDA_EXE" ]; then
    CONDA_BASE=$(dirname $(dirname "$CONDA_EXE"))
elif [ -d "/root/miniconda3" ]; then
    CONDA_BASE="/root/miniconda3"
elif [ -d "$HOME/miniconda3" ]; then
    CONDA_BASE="$HOME/miniconda3"
elif [ -d "$HOME/anaconda3" ]; then
    CONDA_BASE="$HOME/anaconda3"
else
    CONDA_BASE=""
fi

if [ -z "$CONDA_BASE" ]; then
    echo "Installing Miniconda... / Minicondaをインストール中..."
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
    bash /tmp/miniconda.sh -b -p /root/miniconda3
    rm /tmp/miniconda.sh
    CONDA_BASE="/root/miniconda3"
    echo "✅ Miniconda installed / インストール完了"
else
    echo "✅ Conda detected at / 検出場所: $CONDA_BASE"
fi

export PATH="$CONDA_BASE/bin:$PATH"

# Accept Anaconda Terms of Service (required by newer Miniconda versions)
# 新しいMinicondaバージョンで必要なAnaconda利用規約に同意します
"$CONDA_BASE/bin/conda" tos accept --override-channels \
    --channel https://repo.anaconda.com/pkgs/main 2>/dev/null || true
"$CONDA_BASE/bin/conda" tos accept --override-channels \
    --channel https://repo.anaconda.com/pkgs/r 2>/dev/null || true

# Load conda shell functions
# condaのシェル関数を読み込みます
source "$CONDA_BASE/etc/profile.d/conda.sh"

# Create or fix 'vila' conda environment with Python 3.10
# Python 3.10で'vila' conda環境を作成または修正します
VILA_PYTHON=$(conda run -n vila python --version 2>/dev/null | grep -o "3\.[0-9]*" | head -1)
if ! conda env list | grep -q "^vila "; then
    echo "Creating conda environment 'vila' (Python 3.10)..."
    echo "conda環境'vila'を作成中（Python 3.10）..."
    conda create -n vila python=3.10 -y
    echo "✅ Environment created / 環境を作成しました"
elif [ "$VILA_PYTHON" != "3.10" ]; then
    echo "Wrong Python ($VILA_PYTHON), recreating with 3.10..."
    echo "Pythonバージョンが異なります（$VILA_PYTHON）、3.10で再作成中..."
    conda env remove -n vila -y
    conda create -n vila python=3.10 -y
    echo "✅ Environment recreated / 環境を再作成しました"
else
    echo "✅ Environment 'vila' OK (Python 3.10)"
fi

# Activate environment
# 環境を有効化します
source "$CONDA_BASE/bin/activate" vila
echo "✅ Activated: $(python --version)"

# ── 1. Git LFS ──────────────────────────────────────────────
echo ""
echo "[1/6] Installing git-lfs / git-lfsをインストール中..."
if ! command -v git-lfs &> /dev/null; then
    apt-get update -qq
    curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash
    apt-get install -y git-lfs
fi
git lfs install
echo "✅ git-lfs OK"

# ── 2. PyTorch (before VILA to avoid torch==2.3.0 conflict) ──
echo ""
echo "[2/6] Installing PyTorch / PyTorchをインストール中..."
# Install PyTorch BEFORE VILA to avoid the torch==2.3.0 conflict.
# VILA's pyproject.toml pins torch==2.3.0 which no longer exists on PyPI.
# By installing PyTorch first and using --no-deps for VILA, we avoid this.
#
# torch==2.3.0の競合を避けるため、VILAより先にPyTorchをインストールします。
# VILAのpyproject.tomlはtorch==2.3.0を指定しますが、PyPIに存在しません。
# 先にインストールし、VILAは--no-depsを使うことで回避します。
GPU_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.')
if [ -n "$GPU_CAP" ] && [ "$GPU_CAP" -ge 120 ] 2>/dev/null; then
    echo "Blackwell GPU (sm_$GPU_CAP): PyTorch nightly + CUDA 12.8..."
    pip install --pre torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/nightly/cu128 --quiet
else
    echo "Standard GPU: PyTorch stable + CUDA 12.1..."
    echo "標準GPU: PyTorch stable + CUDA 12.1..."
    pip install torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu121 --quiet
fi
echo "✅ PyTorch: $(python -c 'import torch; print(torch.__version__)')"

# ── 3. VILA ──────────────────────────────────────────────────
echo ""
echo "[3/6] Installing VILA / VILAをインストール中..."

if [ ! -d "VILA/.git" ]; then
    rm -rf VILA
    git clone https://github.com/NVlabs/VILA.git
fi
cd VILA
git checkout a5a380d6d09762d6f3fd0443aac6b475fba84f7e

# Install VILA with --no-deps to skip the torch==2.3.0 pin.
# --no-depsでtorch==2.3.0のpinをスキップしてVILAをインストールします。
pip install --upgrade pip --quiet
pip install -e .          --no-deps --quiet
pip install -e ".[train]" --no-deps --quiet
pip install -e ".[eval]"  --no-deps --quiet

# Install transformers at the exact version VILA needs (from GitHub).
# VILAが必要とする正確なバージョンのtransformersをGitHubからインストールします。
pip install "git+https://github.com/huggingface/transformers@v4.37.2" --quiet

cd "$SCRIPT_DIR"
echo "✅ VILA OK"

# ── 4. All remaining dependencies / 残りの依存パッケージ ─────
echo ""
echo "[4/6] Installing dependencies / 依存パッケージをインストール中..."

# pydantic must be v1: deepspeed 0.9.5 uses field.required (v1 API).
# pydantic v2 renamed it to field.is_required(), causing AttributeError.
# pydanticはv1必須：deepspeed 0.9.5はfield.required（v1 API）を使用します。
# pydantic v2ではfield.is_required()に改名され、AttributeErrorが発生します。
pip install \
    "pydantic<2.0.0" \
    "deepspeed==0.9.5" \
    "bitsandbytes>=0.41.0" \
    "accelerate>=0.21.0" \
    "sentencepiece==0.1.99" \
    "tokenizers>=0.15.2" \
    "shortuuid" \
    "einops==0.6.1" \
    "numpy==1.26.0" \
    "timm==0.9.12" \
    "datasets==2.16.1" \
    "fastapi>=0.68.0" \
    "uvicorn>=0.15.0" \
    "gradio>=3.50.0" \
    "python-multipart>=0.0.5" \
    "pillow>=8.0.0" \
    "huggingface-hub>=0.16.0" \
    "opencv-python" \
    "matplotlib" \
    "openai" \
    --quiet

# s2wrapper: required by VILA vision encoder, not on PyPI
# s2wrapper: VILAのビジョンエンコーダーに必要、PyPIにはありません
pip install "git+https://github.com/bfshi/scaling_on_scales" --quiet

# Apply deepspeed monkey-patches from VILA (fixes ZeRO runtime for inference)
# VILAのdeepspeedモンキーパッチを適用します（推論用ZeROランタイムの修正）
SITE_PKG=$(python -c 'import site; print(site.getsitepackages()[0])')
cp -rv "$SCRIPT_DIR/VILA/llava/train/deepspeed_replace/"* "$SITE_PKG/deepspeed/" 2>/dev/null || true

echo "✅ Dependencies installed / 依存パッケージをインストールしました"

# ── 5. HAMSTER model / HAMSTERモデル ─────────────────────────
echo ""
echo "[5/6] Downloading HAMSTER model (~26GB) / HAMSTERモデルをダウンロード中（約26GB）..."
echo "This may take 10-20 minutes / 10〜20分かかる場合があります..."
if [ ! -d "Hamster_dev" ]; then
    git clone https://huggingface.co/yili18/Hamster_dev
    echo "✅ Model downloaded / モデルをダウンロードしました"
else
    # Resume incomplete download if needed / 不完全なダウンロードを再開します
    cd Hamster_dev && git lfs pull && cd "$SCRIPT_DIR"
    echo "✅ Model ready / モデル準備完了"
fi

# ── 6. Final checks / 最終確認 ───────────────────────────────
echo ""
echo "[6/6] Final checks / 最終確認..."
hostname -I | awk '{print $1}' > ip_eth0.txt
echo "IP: $(cat ip_eth0.txt)"

python -c "
import torch
if torch.cuda.is_available():
    name = torch.cuda.get_device_name(0)
    vram = torch.cuda.get_device_properties(0).total_memory / 1024**3
    cap = torch.cuda.get_device_capability()
    print(f'✅ GPU: {name} ({vram:.1f} GB VRAM, sm_{cap[0]}{cap[1]})')
else:
    print('⚠️  No CUDA GPU detected / CUDA GPUが検出されませんでした')
"

echo ""
echo "========================================"
echo " Installation complete! / インストール完了！"
echo ""
echo " IMPORTANT / 重要:"
echo " Activate the environment before each session:"
echo " セッションごとに環境を有効化してください："
echo "   conda activate vila"
echo ""
echo " Start server (Terminal 1) / サーバー起動（ターミナル1）："
echo "   ./start_server.sh"
echo ""
echo " Start Gradio (Terminal 2) / Gradio起動（ターミナル2）："
echo "   ./start_gradio.sh"
echo "========================================"