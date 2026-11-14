#!/bin/bash
# Glint · GitHub SSH 一键配置与推送
# 双击运行，或在终端执行：./setup-github-ssh.command
set -euo pipefail
cd "$(dirname "$0")"

GH_USER="Chagan114514"
GH_REPO="glint"
REMOTE="git@github.com:${GH_USER}/${GH_REPO}.git"
SSH_DIR="$HOME/.ssh"
KEY="$SSH_DIR/id_ed25519"
PUB="$KEY.pub"
KNOWN_HOSTS="$SSH_DIR/known_hosts"
EXPECTED_FP="SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"

say()  { printf '\033[1;36m>> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$*"; exit 1; }

printf '\n\033[1mGlint · GitHub SSH 配置\033[0m\n'
printf '仓库: %s/%s\n\n' "$GH_USER" "$GH_REPO"

command -v ssh-keygen >/dev/null || die "找不到 ssh-keygen"
command -v git >/dev/null || die "找不到 git"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# 1. 确认 GitHub 主机指纹，避免连接到伪造服务器。
say "检查 GitHub SSH 主机指纹"
if ! ssh-keygen -F github.com >/dev/null 2>&1; then
    HOST_KEY="$(ssh-keyscan -t ed25519 github.com 2>/dev/null || true)"
    [ -n "$HOST_KEY" ] || die "无法获取 github.com 主机公钥，请检查网络"
    FP="$(printf '%s\n' "$HOST_KEY" | ssh-keygen -lf - | awk '{print $2}')"
    if [ "$FP" != "$EXPECTED_FP" ]; then
        printf '实际指纹: %s\n预期指纹: %s\n' "$FP" "$EXPECTED_FP"
        die "GitHub 主机指纹不匹配，已停止"
    fi
    printf '%s\n' "$HOST_KEY" >> "$KNOWN_HOSTS"
    chmod 644 "$KNOWN_HOSTS"
    ok "已写入 known_hosts（指纹校验通过）"
else
    ok "known_hosts 中已有 github.com"
fi

# 2. 如果当前已经能通过 SSH 认证，直接推送。
AUTH_OUTPUT="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -T git@github.com 2>&1 || true)"
if printf '%s' "$AUTH_OUTPUT" | grep -q "successfully authenticated"; then
    ok "SSH 已认证，无需重新添加公钥"
    git remote set-url origin "$REMOTE"
    say "推送到 GitHub"
    git push -u origin main --tags
    ok "已推送 main 和 tags"
    open "https://github.com/${GH_USER}/${GH_REPO}"
    exit 0
fi

# 3. 生成或复用 Ed25519 密钥。
if [ ! -f "$KEY" ]; then
    say "生成新的 Ed25519 SSH 密钥"
    ssh-keygen -t ed25519 -C "${GH_USER}@users.noreply.github.com" -f "$KEY" -N ""
    ok "密钥已生成: $KEY"
else
    ok "复用已有密钥: $KEY"
    [ -f "$PUB" ] || ssh-keygen -y -f "$KEY" > "$PUB"
fi
chmod 600 "$KEY"
chmod 644 "$PUB"

# 4. 加载到 ssh-agent，并写入 ~/.ssh/config 方便以后自动使用。
eval "$(ssh-agent -s)" >/dev/null
ssh-add --apple-use-keychain "$KEY" >/dev/null 2>&1 || ssh-add "$KEY"

if [ ! -f "$SSH_DIR/config" ]; then
    touch "$SSH_DIR/config"
    chmod 600 "$SSH_DIR/config"
fi
if ! grep -q '^Host github.com$' "$SSH_DIR/config"; then
    cat >> "$SSH_DIR/config" <<'SSHCONF'

Host github.com
  HostName github.com
  User git
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
SSHCONF
    chmod 600 "$SSH_DIR/config"
    ok "已添加 ~/.ssh/config 配置"
fi

# 5. 复制公钥并打开 GitHub 添加页面。
if command -v pbcopy >/dev/null; then
    pbcopy < "$PUB"
    ok "公钥已复制到剪贴板"
fi

printf '\n\033[1m你的公钥（可手动复制）：\033[0m\n'
cat "$PUB"
printf '\n'

# 如果安装了 GitHub CLI 且已登录，可自动添加公钥。
ADDED_BY_GH=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    say "检测到已登录的 GitHub CLI，尝试自动添加公钥"
    if gh ssh-key add "$PUB" --title "Glint on $(scutil --get ComputerName 2>/dev/null || hostname)" >/dev/null 2>&1; then
        ADDED_BY_GH=1
        ok "已通过 gh 添加公钥"
    else
        warn "gh 自动添加失败，请按下面的手动步骤操作"
    fi
fi

if [ "$ADDED_BY_GH" -eq 0 ]; then
    printf '\033[1m接下来：\033[0m\n'
    printf '  1. 浏览器会打开 GitHub 的 “New SSH key” 页面\n'
    printf '  2. Title 随便填，例如 “MacBook Pro”\n'
    printf '  3. Key 类型选 Authentication Key，粘贴剪贴板里的公钥\n'
    printf '  4. 点击 Add SSH key\n\n'
    open "https://github.com/settings/ssh/new" || true
    read -r -p "添加完成后，按回车继续..." _
fi

# 6. 验证 SSH，失败时给出提示。
say "验证 GitHub SSH 连接"
AUTH_OUTPUT="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -T git@github.com 2>&1 || true)"
if ! printf '%s' "$AUTH_OUTPUT" | grep -q "successfully authenticated"; then
    printf '%s\n\n' "$AUTH_OUTPUT"
    die "SSH 认证仍未成功。请确认公钥已添加到 GitHub，然后重新运行本脚本"
fi
ok "SSH 认证成功: $(printf '%s' "$AUTH_OUTPUT" | head -1)"

# 7. 切换 remote 并推送 main + tags。
git remote set-url origin "$REMOTE"
say "推送到 ${GH_USER}/${GH_REPO}"
git push -u origin main --tags
ok "推送完成"
printf '\n仓库: https://github.com/%s/%s\n' "$GH_USER" "$GH_REPO"
printf '下一步可创建 Release：\n'
printf '  gh release create v1.1.0 Glint-1.1.dmg Glint-1.1.zip \\\n'
printf '    --title "Glint 1.1.0 — 批注、OCR、滚动截图与麦克风" \\\n'
printf '    --notes-file RELEASE_NOTES_v1.1.0.md\n\n'
open "https://github.com/${GH_USER}/${GH_REPO}" || true
