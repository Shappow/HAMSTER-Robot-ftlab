#!/bin/bash
# ============================================================
# Push HAMSTER Beta fork to GitHub
# HAMSTER BetaフォークをGitHubにプッシュします
# ============================================================

REPO_URL="https://github.com/Shappow/HAMSTER-Robot-ftlab.git"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "========================================"
echo " Pushing to / プッシュ先: $REPO_URL"
echo "========================================"

# Initialize git if not already done
# まだ初期化されていない場合はgitを初期化します
if [ ! -d ".git" ]; then
    git init
    echo "✅ Git initialized / Git初期化完了"
fi

# Set remote origin
# リモートoriginを設定します
if git remote get-url origin &>/dev/null; then
    git remote set-url origin "$REPO_URL"
    echo "✅ Remote updated / リモートを更新しました"
else
    git remote add origin "$REPO_URL"
    echo "✅ Remote added / リモートを追加しました"
fi

# Create .gitignore to exclude large/unnecessary files
# 大きなファイルや不要なファイルを除外する.gitignoreを作成します
cat > .gitignore << 'GITIGNORE'
# Model weights (too large for GitHub / GitHubには大きすぎます)
Hamster_dev/
*.safetensors
*.bin
*.pt
*.pth

# Python cache / Pythonキャッシュ
__pycache__/
*.pyc
*.pyo
*.egg-info/

# Conda / environment
*.sh.bak
environment_setup_patched.sh
Miniconda3-*.sh

# Misc
.DS_Store
*.log
ip_eth0.txt
GITIGNORE

echo "✅ .gitignore created / .gitignore作成完了"

# Stage all files
# 全ファイルをステージングします
git add .
git status --short

# Commit
# コミットします
git commit -m "HAMSTER Beta - patched for RunPod compatibility

Fixes applied / 適用された修正:
- flash_attn replaced with PyTorch native SDPA
- builder.py: torch_dtype always set in 4-bit mode
- builder.py: vision_tower CPU offload in 4-bit mode
- server.py: model name validation relaxed
- setup.sh: full automated install with conda + GPU detection
- start_server.sh / start_gradio.sh: conda env auto-detection" 2>/dev/null || echo "✅ Nothing new to commit / 新しいコミットはありません"

# Push to main branch
# mainブランチにプッシュします
echo ""
echo "Pushing to GitHub... / GitHubにプッシュ中..."
echo "(You may be asked for your GitHub credentials)"
echo "（GitHubの認証情報を求められる場合があります）"
echo ""
git push -u origin main 2>/dev/null || git push -u origin master

echo ""
echo "========================================"
echo " Done! / 完了！"
echo " https://github.com/Shappow/HAMSTER-Robot-ftlab"
echo "========================================"
