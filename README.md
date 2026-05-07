# HAMSTER Beta — RunPod Fork

Fork of [HAMSTER_beta](https://github.com/liyi14/HAMSTER_beta) and [VILA](https://github.com/NVlabs/VILA) with compatibility fixes for RunPod.

[HAMSTER_beta](https://github.com/liyi14/HAMSTER_beta) と [VILA](https://github.com/NVlabs/VILA) のRunPod互換性修正フォークです。

---

## Fixes applied / 適用された修正

| Problem / 問題 | Fix / 修正 |
|---|---|
| `flash_attn` incompatible with new CUDA/PyTorch / 新しいCUDA/PyTorchと非互換 | Replaced with PyTorch native SDPA / PyTorchネイティブSDPAに置き換え |
| `torch_dtype` missing in 4-bit mode / 4bitモードで欠落 | Fixed in `builder.py` |
| `deepspeed` crashes with pydantic v2 / pydantic v2でクラッシュ | Pinned to `pydantic<2.0.0` |
| Model name rejected with error 422 / モデル名が422エラーで拒否される | Relaxed validation in `server.py` |
| `ip_eth0.txt` empty (no eth0 interface) / eth0がなくファイルが空 | Uses `hostname -I` instead |
| VILA `transformers_replace` imports `flash_attn` / `flash_attn`をインポート | Skipped at install time (inference only) / インストール時にスキップ（推論のみ） |

---

## Quick start (RunPod) / クイックスタート（RunPod）

### Recommended setup / 推奨環境

| | |
|---|---|
| **GPU** | A40 (48 GB) or higher / A40（48GB）以上 |
| **RunPod image** | `runpod/pytorch:2.1.0-py3.10-cuda12.1.1-devel-ubuntu22.04` |
| **Disk** | 100 GB minimum (model is ~26 GB) / 最低100GB（モデル約26GB） |

### Steps / 手順

**1. Clone this repo / このリポジトリをクローン**
```bash
cd /workspace
git clone https://github.com/Shappow/HAMSTER-Robot-ftlab.git
cd HAMSTER-Robot-ftlab
chmod +x setup.sh start_server.sh start_gradio.sh
```

**2. Run the setup script / セットアップスクリプトを実行**
```bash
./setup.sh
```
This will automatically / 自動的に以下を実行します：
- Install Miniconda if needed / 必要に応じてMinicondaをインストール
- Create conda environment `vila` (Python 3.10) / conda環境`vila`を作成（Python 3.10）
- Clone VILA at the correct commit / 正しいコミットでVILAをクローン
- Install all dependencies / 全依存パッケージをインストール
- Auto-detect GPU and install the right PyTorch / GPUを自動検出して適切なPyTorchをインストール
  - Blackwell (RTX 50xx, sm_120+) → PyTorch nightly + CUDA 12.8
  - Other GPUs / その他のGPU → PyTorch stable + CUDA 12.1
- Download the HAMSTER model (~26 GB) / HAMSTERモデルをダウンロード（約26GB）

**3. Start the server (Terminal 1) / サーバーを起動（ターミナル1）**
```bash
conda activate vila
./start_server.sh
```
Wait for / 以下が表示されるまで待ちます：
```
Uvicorn running on http://0.0.0.0:8000
```

**4. Start the Gradio interface (Terminal 2) / Gradioインターフェースを起動（ターミナル2）**
```bash
conda activate vila
./start_gradio.sh
```
Then open / ブラウザで開きます：`http://localhost:7860`

---

## Quick test / クイックテスト

```bash
curl -X POST http://127.0.0.1:8000/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"HAMSTER_dev","messages":[{"role":"user","content":"Hello!"}]}'
```

---

## Project structure / プロジェクト構成

```
HAMSTER-Robot-ftlab/
├── setup.sh                    # Full install script / 完全インストールスクリプト
├── start_server.sh             # Start inference server / 推論サーバー起動
├── start_gradio.sh             # Start Gradio UI / Gradio UI起動
├── server.py                   # FastAPI server (patched) / FastAPIサーバー（パッチ済み）
├── gradio_server_example.py    # Gradio interface / Gradioインターフェース
├── examples/                   # Example images / サンプル画像
└── VILA/                       # VILA submodule (commit a5a380d)
    └── llava/
        └── model/
            ├── builder.py                          # Patched / パッチ済み
            └── multimodal_encoder/intern/
                └── flash_attention.py              # Replaced with SDPA / SDPAに置き換え
```

---

## Credits / クレジット

- Original HAMSTER: [liyi14/HAMSTER_beta](https://github.com/liyi14/HAMSTER_beta)
- VILA: [NVlabs/VILA](https://github.com/NVlabs/VILA)
- This fork / このフォーク: [Shappow/HAMSTER-Robot-ftlab](https://github.com/Shappow/HAMSTER-Robot-ftlab)