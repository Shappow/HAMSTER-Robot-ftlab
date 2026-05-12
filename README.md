# HAMSTER — RunPod Deployment Fork
# HAMSTER — RunPod デプロイ対応フォーク

> **This is a modified version of [HAMSTER](https://github.com/liyi14/HAMSTER_beta) optimized for one-command deployment on RunPod GPU instances.**
>
> **これは [HAMSTER](https://github.com/liyi14/HAMSTER_beta) を RunPod GPU インスタンスへワンコマンドでデプロイできるよう改良したフォーク版です。**

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
| `deploy.sh` | One-command full setup script / ワンコマンド完全セットアップスクリプト |
| `startup.sh` | Lightweight on-start script for pod restarts / Pod 再起動用の軽量起動スクリプト |
| `activate.sh` | Quick conda environment activation / conda 環境の即時アクティベーション |
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

## Pod Restarts & Server Migration / Pod 再起動・サーバー移行への対応

RunPod may migrate your pod to a different physical server while keeping `/workspace` intact.
System packages (`git-lfs`, `screen`) and the conda PATH are lost on every restart — `startup.sh` restores them automatically.

RunPod はポッドを別の物理サーバーに移行することがありますが、`/workspace` の内容は保持されます。
システムパッケージ（`git-lfs`、`screen`）と conda の PATH は再起動のたびにリセットされますが、`startup.sh` が自動で復元します。

### Option 1 — Automatic (recommended) / 自動起動（推奨）

Set `startup.sh` as the **RunPod "On-Start Script"** in your pod settings.
It will run automatically on every pod start without any manual intervention.

ポッド設定の **RunPod "On-Start Script"** に `startup.sh` を設定してください。
以後、ポッド起動のたびに自動で実行されます。

```
bash /workspace/HAMSTER-Robot-ftlab/HAMSTER_beta/startup.sh
```

`startup.sh` will: / `startup.sh` が行うこと：
- Reinstall `git-lfs` and `screen`
- Restore conda to `PATH` and configure `~/.bashrc`
- Restart the HAMSTER server if it is not already running

`git-lfs` と `screen` の再インストール、conda の PATH 復元と `~/.bashrc` 設定、HAMSTER サーバーが停止していれば自動起動を行います。

### Option 2 — Manual / 手動起動

```bash
bash /workspace/HAMSTER-Robot-ftlab/HAMSTER_beta/startup.sh
```

---

## Activating the Environment / 環境のアクティベーション

To work interactively in the conda environment from any terminal:

任意のターミナルから conda 環境をアクティベートするには：

```bash
source /workspace/HAMSTER-Robot-ftlab/HAMSTER_beta/activate.sh
```

After activation: / アクティベーション後：
- `conda` and `python` point to the `vila` environment / `conda` と `python` が `vila` 環境を参照
- `PYTHONPATH` includes the VILA package / `PYTHONPATH` に VILA パッケージが含まれる
- Working directory is set to `HAMSTER_beta/` / カレントディレクトリが `HAMSTER_beta/` に設定される

> **Tip:** `startup.sh` automatically adds `alias activate='source .../activate.sh'` to `~/.bashrc`,
> so after the first startup you can simply type `activate`.
>
> **ヒント:** `startup.sh` は `~/.bashrc` に `alias activate='source .../activate.sh'` を自動追加します。
> 初回起動後は `activate` と入力するだけで環境をアクティベートできます。

---

## Using the Gradio Interface / Gradio インターフェースの使用

Once the server is running, open a second terminal and run:

サーバーが起動したら、別のターミナルで以下を実行：

```bash
source /workspace/HAMSTER-Robot-ftlab/HAMSTER_beta/activate.sh
python gradio_server_example.py
```

The Gradio UI will be available at the public URL printed in the terminal.

Gradio UI はターミナルに表示されるパブリック URL からアクセスできます。

---

## Project Structure / プロジェクト構成

```
HAMSTER_beta/
├── deploy.sh                  # Full setup script (first-time) / 完全セットアップ（初回用）
├── startup.sh                 # Lightweight on-start script / 軽量起動スクリプト（RunPod On-Start 用）
├── activate.sh                # Conda environment activation / conda 環境アクティベーション
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
