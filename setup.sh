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

# Automatically detect the conda installation path.
# condaのインストールパスを自動検出します。
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
    echo "Conda not found. Installing Miniconda... / Condaが見つかりません。Minicondaをインストールします..."
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
    bash /tmp/miniconda.sh -b -p "$HOME/miniconda3"
    rm /tmp/miniconda.sh
    CONDA_BASE="$HOME/miniconda3"
    export PATH="$CONDA_BASE/bin:$PATH"
    echo "✅ Miniconda installed / インストール完了: $CONDA_BASE"
else
    echo "✅ Conda detected at / 検出場所: $CONDA_BASE"
fi

export PATH="$CONDA_BASE/bin:$PATH"

# Load conda shell functions (required for conda activate in scripts)
# condaのシェル関数を読み込みます（スクリプト内のconda activateに必要）
source "$CONDA_BASE/etc/profile.d/conda.sh"

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

# ── 2. VILA + environment_setup.sh ──────────────────────────
echo ""
echo "[2/6] Installing VILA / VILAをインストール中..."

# Clone VILA at the exact commit required by HAMSTER.
# HAMSTERが必要とする正確なコミットでVILAをクローンします。
if [ ! -d "VILA/.git" ]; then
    rm -rf VILA
    git clone https://github.com/NVlabs/VILA.git
fi
cd VILA
git checkout a5a380d6d09762d6f3fd0443aac6b475fba84f7e

# Patch environment_setup.sh before running it.
# We remove two problematic lines:
#   1. flash_attn install: incompatible with new CUDA/PyTorch versions.
#      We replaced it with PyTorch native SDPA in flash_attention.py.
#   2. cuda-toolkit via conda: already installed in RunPod base image.
#
# 実行前にenvironment_setup.shをパッチします。
# 問題のある2行を削除します：
#   1. flash_attnのインストール：新しいCUDA/PyTorchバージョンと非互換。
#      flash_attention.pyでPyTorchネイティブSDPAに置き換え済み。
#   2. condaによるcuda-toolkit：RunPodのベースイメージに既にインストール済み。
cp environment_setup.sh environment_setup_patched.sh
sed -i '/flash.attn/d' environment_setup_patched.sh
sed -i '/cuda-toolkit/d' environment_setup_patched.sh

# Also skip the transformers_replace monkey-patches.
# They import flash_attn inside modeling_mistral.py etc, which would break imports.
# These patches are only needed for training (sequence parallelism), not inference.
#
# transformers_replaceモンキーパッチもスキップします。
# modeling_mistral.pyなどでflash_attnをインポートするためimportが壊れます。
# これらのパッチはトレーニング（シーケンス並列）にのみ必要で、推論には不要です。
sed -i '/transformers_replace/d' environment_setup_patched.sh

echo "Running VILA environment_setup.sh vila (patched)..."
echo "VILA environment_setup.sh vila（パッチ済み）を実行中..."
bash environment_setup_patched.sh vila

# Activate the newly created environment
# 新しく作成した環境を有効化します
source "$CONDA_BASE/bin/activate" vila
echo "✅ VILA OK — $(python --version)"
cd "$SCRIPT_DIR"

# ── 3. PyTorch (GPU-aware) ───────────────────────────────────
echo ""
echo "[3/6] Installing correct PyTorch / 正しいPyTorchをインストール中..."

# Detect GPU compute capability to choose the right PyTorch build:
#   sm_120+ (Blackwell, RTX 50xx) → nightly + CUDA 12.8
#   sm_89 and below               → stable + CUDA 12.1
# GPU計算能力を検出して適切なPyTorchビルドを選択します。
GPU_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.')
if [ -n "$GPU_CAP" ] && [ "$GPU_CAP" -ge 120 ] 2>/dev/null; then
    echo "Blackwell GPU (sm_$GPU_CAP): installing PyTorch nightly + CUDA 12.8..."
    echo "Blackwell GPU（sm_$GPU_CAP）: PyTorch nightly + CUDA 12.8をインストール中..."
    pip install --pre torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/nightly/cu128 --quiet
else
    echo "Installing PyTorch stable (CUDA 12.1)... / PyTorch stable（CUDA 12.1）をインストール中..."
    pip install torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/cu121 --quiet
fi
echo "✅ PyTorch: $(python -c 'import torch; print(torch.__version__)')"

# ── 4. Compatibility fixes / 互換性修正 ─────────────────────
echo ""
echo "[4/6] Applying compatibility fixes / 互換性修正を適用中..."

# Fix pydantic: deepspeed 0.9.5 uses the old pydantic v1 API (field.required).
# pydantic v2 renamed it to field.is_required(), causing AttributeError at startup.
#
# pydanticの修正：deepspeed 0.9.5は古いpydantic v1 API（field.required）を使用します。
# pydantic v2ではfield.is_required()に改名され、スタートアップ時にAttributeErrorが発生します。
pip install "pydantic<2.0.0" --quiet

# Apply deepspeed monkey-patches from VILA
# VILAのdeepspeedモンキーパッチを適用します
SITE_PKG=$(python -c 'import site; print(site.getsitepackages()[0])')
cp -rv "$SCRIPT_DIR/VILA/llava/train/deepspeed_replace/"* "$SITE_PKG/deepspeed/" 2>/dev/null || true

echo "✅ Fixes applied / 修正を適用しました"

# ── 5. HAMSTER model / HAMSTERモデル ─────────────────────────
echo ""
echo "[5/6] Downloading HAMSTER model (~26GB) / HAMSTERモデルをダウンロード中（約26GB）..."
if [ ! -d "Hamster_dev" ]; then
    git clone https://huggingface.co/yili18/Hamster_dev
    echo "✅ Model downloaded / モデルをダウンロードしました"
else
    echo "✅ Model already present, skipping / モデルは既に存在します、スキップします"
fi

# ── 6. Local IP + GPU check ──────────────────────────────────
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
echo " To start the inference server / 推論サーバーを起動："
echo "   ./start_server.sh"
echo ""
echo " To start the Gradio interface / Gradioインターフェースを起動："
echo "   ./start_gradio.sh"
echo "========================================"