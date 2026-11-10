<#
.SYNOPSIS
  把 antifox-purge 一键发布到 GitHub（建仓库 + 提交 + 推送），并把 GHCR 镜像地址打出来。
.DESCRIPTION
  需要一枚 GitHub PAT（classic: 勾 repo + write:packages；fine-grained: Contents=Read/Write，
  Packages=Read/Write）。脚本做的事：
    1) 本地 git init / add / commit（没有 user.name/email 时给仓库级默认值）
    2) GET  /user                       → 认出你的账号名
    3) POST /user/repos                 → 建仓库（已存在就复用）
    4) git push -u origin main          → 推代码（推完把 remote 里的 token 换成干净 URL）
    5) 打印仓库地址 + GHCR 镜像地址 + 后续两步
.PARAMETER Token   GitHub PAT
.PARAMETER Repo    仓库名，默认 antifox-purge
.PARAMETER Private 建私有仓库
.EXAMPLE
  .\publish.ps1 -Token ghp_xxxxxxxxxxxx
.EXAMPLE
  $env:GITHUB_TOKEN='ghp_...'; .\publish.ps1
#>
[CmdletBinding()]
param(
  [string]$Token = $env:GITHUB_TOKEN,
  [string]$Repo = "antifox-purge",
  [string]$Description = "AntiFox with dsh-purge armor-piercing baked in at compile time (prompt hard-inject + guard bypass + pentest skills)",
  [switch]$Private
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot          # publish.ps1 就在仓库根
Set-Location $Root

function Ok($m)   { Write-Host "[ OK ] $m" -ForegroundColor Green }
function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Warn($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[FAIL] $m" -ForegroundColor Red; exit 1 }

if (-not $Token) { Die "需要 GitHub PAT：.\publish.ps1 -Token ghp_xxx（或设 `$env:GITHUB_TOKEN）" }
if ($Token -notmatch '^(ghp_|github_pat_|gho_)') { Warn "Token 前缀不像 GitHub PAT，继续尝试" }

# ---------- 1) git init / commit ----------
if (-not (Test-Path (Join-Path $Root ".git"))) {
  git init -b main | Out-Null
  Ok "git 仓库已初始化"
} else {
  Ok "git 仓库已存在"
}
if (-not (git config user.name))  { git config user.name  "antifox-purge" }
if (-not (git config user.email)) { git config user.email "antifox-purge@users.noreply.github.com" }

git add -A
$dirty = git status --porcelain
if ($dirty) {
  git commit -m "antifox + dsh-purge armor-piercing layer (compile-time)" | Out-Null
  Ok "已提交（$(($dirty -split "`n").Count) 个文件变更）"
} else {
  Ok "工作区干净，无需提交"
}

# ---------- 2) 认账号 ----------
$hdr = @{
  Authorization          = "Bearer $Token"
  Accept                 = "application/vnd.github+json"
  "User-Agent"           = "antifox-purge-publish"
  "X-GitHub-Api-Version" = "2022-11-28"
}
try {
  $me = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $hdr -TimeoutSec 30
} catch {
  Die "Token 无效或权限不足：$($_.Exception.Message)"
}
$login = $me.login
Ok "账号: $login"

# ---------- 3) 建仓库 ----------
$body = @{ name = $Repo; description = $Description; private = [bool]$Private; auto_init = $false } | ConvertTo-Json
$exists = $false
try {
  $r = Invoke-RestMethod -Uri "https://api.github.com/user/repos" -Method Post -Headers $hdr -Body $body -ContentType "application/json" -TimeoutSec 60
  Ok "仓库已创建: $($r.full_name)"
} catch {
  $msg = "$($_.Exception.Message)"
  $resp = $_.Exception.Response
  if ($resp) {
    $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $txt = $sr.ReadToEnd()
    if ($txt -match 'already exists') { $exists = $true; Warn "仓库已存在，复用 $login/$Repo" }
    else { Die "建仓失败：$txt" }
  } elseif ($msg -match 'already exists') { $exists = $true; Warn "仓库已存在，复用 $login/$Repo" }
  else { Die "建仓失败：$msg" }
}

# ---------- 4) 推送 ----------
$cleanUrl = "https://github.com/$login/$Repo.git"
$tokUrl   = "https://x-access-token:$Token@github.com/$login/$Repo.git"
git remote remove origin 2>$null
git remote add origin $tokUrl
Info "推送中（首次 push 会把 ~$( [math]::Round((Get-ChildItem $Root -Recurse -File -Force | Measure-Object Length -Sum).Sum / 1MB, 1) ) MB 传上去）…"
$push = git push -u origin main 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Host $push
  if ("$push" -match 'rejected|non-fast-forward') {
    Warn "远端已有内容 → 强制覆盖分支（这是全新破甲仓库，通常没问题）"
    git push -u origin main --force 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { Die "推送失败，检查 PAT 是否有 repo 写权限" }
  } else {
    Die "推送失败，见上面的 git 输出"
  }
}
# 把 token 从 .git/config 里换掉
git remote set-url origin $cleanUrl
Ok "推送完成，remote 已还原为干净 URL"

# ---------- 5) 结果 ----------
$lc = "$login/$Repo".ToLower()
Write-Host ""
Info "==================== 完成 ===================="
Write-Host "仓库地址 : https://github.com/$login/$Repo"
Write-Host "克隆部署 : git clone https://github.com/$login/$Repo.git && cd $Repo"
Write-Host "本地起站 : cp .env.example .env && docker compose up -d --build"
Write-Host "预构建镜像（Actions 跑完后可用）:"
Write-Host "           docker pull ghcr.io/$lc:latest"
Write-Host ""
Warn "预构建镜像首次推送后是 private —— 到 GitHub → 你的 Packages → 该包 → Package settings → Change visibility → Public"
Warn "Actions 构建进度: https://github.com/$login/$Repo/actions"
