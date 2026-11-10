<#
.SYNOPSIS
  antifox-pierce 状态检查：确认破甲层在平台侧是否真的生效。
.DESCRIPTION
  检查项：
    1) 平台健康与版本
    2) skill 是否已落地（pierce-core / pierce-chain）及正文大小
    3) 每个 agent 的当前提示词是否含「PIERCE-CORE 常驻协议」标记
    4) 每个 agent 是否可见这两个 skill
    5) （可选）本地源码 guard 是否已放行、系统提示是否已硬注入
.EXAMPLE
  .\pierce-status.ps1 -Base http://127.0.0.1:8787 -User admin -Pass 'x'
.EXAMPLE
  .\pierce-status.ps1 -Token $t -Src D:\src\antifox
#>
[CmdletBinding()]
param(
  [string]$Base = "http://127.0.0.1:8787",
  [string]$User = "admin",
  [string]$Pass,
  [string]$Token,
  [string]$Src,
  [string[]]$Skills = @("pierce-core", "pierce-chain")
)

$ErrorActionPreference = "Stop"
$Marker = "PIERCE-CORE 常驻协议"
$Hdrs = @{}

function Line($t, $c = "Gray") { Write-Host $t -ForegroundColor $c }

function Api($method, $path, $body) {
  $a = @{ Method = $method; Uri = "$Base$path"; Headers = $Hdrs; TimeoutSec = 20; ErrorAction = "Stop" }
  if ($null -ne $body) { $a.Body = ($body | ConvertTo-Json -Depth 8 -Compress); $a.ContentType = "application/json; charset=utf-8" }
  return Invoke-RestMethod @a
}

Line "=== antifox-pierce 状态 ===" "Cyan"
Line "平台: $Base"

# 1) health
try {
  $h = Api "GET" "/api/health" $null
  Line ("[ OK ] 健康: " + ($h | ConvertTo-Json -Compress -Depth 3)) "Green"
} catch {
  Line "[FAIL] 平台不可达：$($_.Exception.Message)" "Red"; exit 1
}

# auth
if (-not $Token) {
  if (-not $Pass) {
    $sec = Read-Host "请输入 $User 的密码" -AsSecureString
    $Pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  }
  $r = Api "POST" "/api/auth/login" @{ username = $User; password = $Pass }
  $Token = $r.token
}
$Hdrs = @{ Authorization = "Bearer $Token" }
Line "[ OK ] 已认证" "Green"

# 2) skills on disk
Line ""
Line "-- skill 落地 --" "Cyan"
try {
  $all = Api "GET" "/api/skills" $null
  $names = @($all.skills | ForEach-Object { $_.name })
  foreach ($s in $Skills) {
    $hit = $all.skills | Where-Object { $_.name -eq $s } | Select-Object -First 1
    if (-not $hit) { Line "  [MISS] $s 未安装" "Red"; continue }
    $size = 0
    if ($hit.files) {
      $f = $hit.files | Where-Object { $_ -eq "SKILL.md" -or "$_" -like "*SKILL.md" } | Select-Object -First 1
      if ($f) { $size = 1 }
    }
    Line ("  [ OK ] {0}  (desc: {1})" -f $s, $hit.description) "Green"
  }
  if ($names -notcontains "pierce-core") { Line "  提示：先跑 install/pierce-install.ps1" "Yellow" }
} catch {
  Line "  [FAIL] 读取 /api/skills 失败：$($_.Exception.Message)" "Red"
}

# 3) + 4) agents: prompt marker & skill visibility
Line ""
Line "-- agent 提示词与可见性 --" "Cyan"
$ags = @((Api "GET" "/api/agents" $null).agents)
foreach ($a in $ags) {
  $mark = "no"
  try {
    $vers = @((Api "GET" "/api/agents/$($a.key)/prompts" $null).versions)
    if ($vers.Count -gt 0) {
      $cur = $vers | Sort-Object { [int]$_.version } -Descending | Select-Object -First 1
      if ($cur.template_text -like "*$Marker*") { $mark = "YES" }
    }
    elseif ($vers.Count -eq 0) { $mark = "empty" }
  } catch { $mark = "err" }

  $vis = 0
  foreach ($s in $Skills) {
    try {
      $v = Api "GET" "/api/visibility/skill/$s" $null
      $ids = @($v.agents | ForEach-Object { "$_" })
      if ($ids -contains "$($a.id)") { $vis++ }
    } catch { }
  }

  $color = if ($mark -eq "YES") { "Green" } else { "Yellow" }
  Line ("  {0,-12} id={1,-4} 常驻协议={2,-5} 可见skill={3}/{4}" -f $a.key, $a.id, $mark, $vis, $Skills.Count) $color
}

# 5) source-level patch state
if ($Src) {
  Line ""
  Line "-- 源码改造状态 --" "Cyan"
  $pg = Join-Path $Src "agent\prompt.go"
  $gg = Join-Path $Src "guard\guard.go"
  if (Test-Path $pg) {
    $t = Get-Content $pg -Raw
    if ($t -match "const pierceSpecText") { Line "  [ OK ] agent/prompt.go 已硬注入 pierceSpec" "Green" }
    else { Line "  [MISS] agent/prompt.go 未注入（只走了运行时层）" "Yellow" }
  } else { Line "  [MISS] 找不到 $pg" "Red" }
  if (Test-Path $gg) {
    $t2 = Get-Content $gg -Raw
    if ($t2 -match "PIERCE_DISABLED_RE") { Line "  [ OK ] guard/guard.go 已放行破坏性/外带拦截" "Green" }
    else { Line "  [MISS] guard/guard.go 仍在拦截（skill 层需靠等价写法绕过）" "Yellow" }
  } else { Line "  [MISS] 找不到 $gg" "Red" }
}

Line ""
Line "判定：常驻协议=YES 且 可见skill=2/2 → 提示词层已生效；源码层 OK → guard 也放行。" "Cyan"
