#!/usr/bin/env bash
# 把 antifox-purge 一键发布到 GitHub（建仓库 + 提交 + 推送）
#
# 用法：
#   GITHUB_TOKEN=ghp_xxx ./publish.sh
#   ./publish.sh -t ghp_xxx -r antifox-purge --private
#
# PAT 权限：classic → repo + write:packages；fine-grained → Contents=Read/Write, Packages=Read/Write
set -uo pipefail

TOKEN="${GITHUB_TOKEN:-}"
REPO="antifox-purge"
DESC="AntiFox with dsh-purge armor-piercing baked in at compile time (prompt hard-inject + guard bypass + pentest skills)"
PRIVATE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--token) TOKEN="$2"; shift 2;;
    -r|--repo) REPO="$2"; shift 2;;
    --private) PRIVATE=true; shift;;
    -h|--help) sed -n '2,10p' "$0"; exit 0;;
    *) echo "未知参数: $1"; exit 1;;
  esac
done

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

ok()   { printf '\033[32m[ OK ] %s\033[0m\n' "$*"; }
warn() { printf '\033[33m[WARN] %s\033[0m\n' "$*"; }
fail() { printf '\033[31m[FAIL] %s\033[0m\n' "$*"; exit 1; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }

[[ -z "$TOKEN" ]] && fail "需要 GitHub PAT：GITHUB_TOKEN=ghp_xxx ./publish.sh"

command -v git   >/dev/null || fail "需要 git"
command -v curl  >/dev/null || fail "需要 curl"

# ---------- 1) git init / commit ----------
if [[ ! -d .git ]]; then
  git init -b main >/dev/null && ok "git 仓库已初始化"
else
  ok "git 仓库已存在"
fi
[[ -z "$(git config user.name  || true)" ]] && git config user.name  "antifox-purge"
[[ -z "$(git config user.email || true)" ]] && git config user.email "antifox-purge@users.noreply.github.com"

git add -A
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "antifox + dsh-purge armor-piercing layer (compile-time)" >/dev/null
  ok "已提交"
else
  ok "工作区干净，无需提交"
fi

# ---------- 2) 认账号 ----------
me=$(curl -sS -H "Authorization: Bearer $TOKEN" \
              -H "Accept: application/vnd.github+json" \
              -H "User-Agent: antifox-purge-publish" \
              -H "X-GitHub-Api-Version: 2022-11-28" \
              https://api.github.com/user)
LOGIN=$(printf '%s' "$me" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("login",""))
except Exception: print("")')
[[ -z "$LOGIN" ]] && fail "Token 无效：$me"
ok "账号: $LOGIN"

# ---------- 3) 建仓库 ----------
BODY=$(printf '{"name":"%s","description":"%s","private":%s,"auto_init":false}' \
       "$REPO" "$(printf '%s' "$DESC" | sed 's/"/\\"/g')" "$PRIVATE")
RESP=$(curl -sS -X POST -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: antifox-purge-publish" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -H "Content-Type: application/json" \
        -d "$BODY" https://api.github.com/user/repos)
if printf '%s' "$RESP" | grep -q '"full_name"'; then
  ok "仓库已创建: $(printf '%s' "$RESP" | python3 -c 'import sys,json;print(json.load(sys.stdin)["full_name"])')"
elif printf '%s' "$RESP" | grep -qi 'already exists'; then
  warn "仓库已存在，复用 $LOGIN/$REPO"
else
  fail "建仓失败：$RESP"
fi

# ---------- 4) 推送 ----------
CLEAN="https://github.com/$LOGIN/$REPO.git"
TOKURL="https://x-access-token:$TOKEN@github.com/$LOGIN/$REPO.git"
git remote remove origin 2>/dev/null || true
git remote add origin "$TOKURL"
info "推送中…"
if ! git push -u origin main; then
  warn "推送失败，尝试强制覆盖分支（非快进时）"
  git push -u origin main --force || fail "推送失败：检查 PAT 是否有 repo 写权限"
fi
git remote set-url origin "$CLEAN"
ok "推送完成，remote 已还原为干净 URL"

# ---------- 5) 结果 ----------
LC=$(printf '%s/%s' "$LOGIN" "$REPO" | tr '[:upper:]' '[:lower:]')
echo
info "==================== 完成 ===================="
echo "仓库地址 : https://github.com/$LOGIN/$REPO"
echo "克隆部署 : git clone $CLEAN && cd $REPO"
echo "本地起站 : cp .env.example .env && docker compose up -d --build"
echo "预构建镜像（Actions 跑完后）:"
echo "           docker pull ghcr.io/$LC:latest"
echo
warn "预构建镜像是 private —— GitHub → 你的 Packages → 该包 → Package settings → Change visibility → Public"
warn "Actions 构建进度: https://github.com/$LOGIN/$REPO/actions"
