# HAMSTER — RunPod Deployment Fork
# HAMSTER — RunPod デプロイ対応フォーク

> **This is a modified version of [HAMSTER](https://github.com/liyi14/hamster) optimized for one-command deployment on RunPod GPU instances.**
>
> **これは [HAMSTER](https://github.com/liyi14/hamster) を RunPod GPU インスタンスへワンコマンドでデプロイできるよう改良したフォーク版です。**

---

## What is HAMSTER? / HAMSTER とは？

HAMSTER (**H**ierarchical **A**ction **M**odels for Open-World Robo**t** Manipulation with **E**mbodied **R**easoning) is a vision-language model system for open-world robot manipulation.

HAMSTER は、オープンワールドのロボット操作のためのビジョン言語モデルシステムです。

---

## What changed in this fork? / このフォークの変更点

This fork patches the original code to run reliably on a fresh RunPod instance:

このフォークは、新しい RunPod インスタンス上で確実に動作するよう、元のコードにパッチを適用しています：

| Fix / 修正 | Description / 説明 |
|---|---|
| `deploy.sh` | One-command setup script / ワンコマンドセットアップスクリプト |
| `flash_attn` | Installed via pre-built wheel (no 30-min compilation) / ビルド済みホイールでインストール（30分のコンパイル不要） |
| `VILA` environment | Follows official `environment_setup.sh` procedure / 公式手順に従った環境構築 |
| `globals.py` | `deepspeed` import made optional for inference / 推論時に `deepspeed` のインポートをオプション化 |
| `server.py` | Model name forced to `HAMSTER_dev` to match API / モデル名を API に合わせて `HAMSTER_dev` に固定 |
| `gradio_server_example.py` | Model name case fixed (`Hamster_dev` → `HAMSTER_dev`) / モデル名の大文字小文字を修正 |

---

## Requirements / 動作要件

- RunPod instance with **NVIDIA A40** (or equivalent, 40+ GB VRAM)
- CUDA 12.x
- At least **100 GB** of disk space on `/workspace`

---

## Quick Start / クイックスタート

Clone the repository and run the deploy script. Everything else is automatic.

リポジトリをクローンして、デプロイスクリプトを実行するだけです。あとはすべて自動です。

```bash
git clone https://github.com/Shappow/HAMSTER-Robot-ftlab.git
cd HAMSTER-Robot-ftlab/HAMSTER_beta
bash deploy.sh
```

The script will automatically: / スクリプトが自動で行うこと：

1. Install `git-lfs` and `screen`
2. Install **Miniconda** → `/workspace/miniconda3` *(persisted / 永続化)*
3. Create conda environment `vila` → `/workspace/conda-envs/vila` *(persisted / 永続化)*
4. Clone **VILA** at the required commit
5. Install `flash_attn` via **pre-built wheel** *(no compilation / コンパイル不要)*
6. Install VILA + all dependencies following the official procedure
7. Download model weights from HuggingFace (~50 GB) *(skipped if already present / 既存の場合スキップ)*
8. Apply all patches and start the **server on port 8000**

> **Note:** Everything installed under `/workspace` persists across pod restarts.
> `/workspace` 以下にインストールされたものはすべて Pod 再起動後も保持されます。

### Setup only (no server start) / セットアップのみ（サーバー起動なし）

```bash
bash deploy.sh --setup-only
```

---

## Using the Gradio Interface / Gradio インターフェースの使用

Once the server is running, open a second terminal and run:

サーバーが起動したら、別のターミナルで以下を実行：

```bash
source /workspace/miniconda3/etc/profile.d/conda.sh
conda activate /workspace/conda-envs/vila
cd /workspace/HAMSTER-Robot-ftlab/HAMSTER_beta
python gradio_server_example.py
```

The Gradio UI will be available at the public URL printed in the terminal.

Gradio UI はターミナルに表示されるパブリック URL からアクセスできます。

---

## Restarting after a pod reboot / Pod 再起動後の再起動方法

The conda environment and model weights are persisted in `/workspace`. On a fresh pod, only system packages need to be reinstalled — `deploy.sh` handles this automatically:

conda 環境とモデルの重みは `/workspace` に保存されています。新しい Pod では、システムパッケージのみ再インストールが必要です — `deploy.sh` が自動で処理します：

```bash
cd /workspace/HAMSTER-Robot-ftlab/HAMSTER_beta
bash deploy.sh
```

---

## Project Structure / プロジェクト構成

```
HAMSTER_beta/
├── deploy.sh                  # Main deployment script / メインデプロイスクリプト
├── server.py                  # FastAPI inference server / FastAPI 推論サーバー
├── gradio_server_example.py   # Gradio web interface / Gradio ウェブインターフェース
├── setup_server.sh            # Legacy server start script / レガシーサーバー起動スクリプト
├── requirements.txt           # Python dependencies / Python 依存関係
├── examples/                  # Example images / サンプル画像
└── VILA/                      # Cloned by deploy.sh / deploy.sh によりクローン (not in git)
```

---

## Acknowledgments / 謝辞

- Original HAMSTER: [liyi14/hamster](https://github.com/liyi14/hamster)
- VILA: [NVlabs/VILA](https://github.com/NVlabs/VILA) (commit `a5a380d`)
- Model weights: [yili18/Hamster_dev](https://huggingface.co/yili18/Hamster_dev)
