# syntax=docker/dockerfile:1
#
# antifox-purge —— 自带破甲能力的 Antifox 镜像（多阶段自编译）
#
# 与上游 Dockerfile 的区别：
#   上游是「预编译二进制」镜像（COPY dist/<arch>/antifox），必须先用 CI 编好；
#   本镜像在 build 阶段自己编前端 + Go，clone 下来一条 docker compose up --build 就能起
#   一个**已内置破甲层**的站点：
#     · skills/pierce-core、skills/pierce-chain 随 -tags embedui 内嵌进二进制
#     · agent/prompt.go 的 renderSystem 尾部硬注入 pierceSpec（网页改不掉）
#     · guard/guard.go 的破坏性/外带两条正则已放行
#     · 内置 agent 提示词里的「只在授权范围内操作」已清洗
#
# 构建：
#   docker build -t antifox-purge .
#   docker build -t antifox-purge --build-arg WITH_BROWSER=0 .   # 不要浏览器 MCP，快很多

# ───────────────────────── 1) 前端静态导出 ─────────────────────────
FROM node:22-bookworm AS web
WORKDIR /src/web
COPY web/package.json web/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY web/ ./
RUN npm run build:static

# ───────────────────────── 2) Go 编译（内嵌 UI + skills）─────────────────────────
FROM golang:1.26 AS build
WORKDIR /src
ENV CGO_ENABLED=0
COPY go.mod go.sum ./
RUN go mod download
COPY . .
COPY --from=web /src/web/out ./server/webui/dist
# 内嵌 skill 库（report-generation 由 Go 侧 SeedSkillFiles 生成，故排除）
RUN mkdir -p server/skillsdist \
 && cp -r skills/. server/skillsdist/ \
 && rm -rf server/skillsdist/report-generation \
 && go build -tags embedui -trimpath -ldflags "-s -w" -o /out/antifox ./cmd/antifox

# ───────────────────────── 3) 运行时 ─────────────────────────
FROM python:3.12-slim-bookworm
ARG TARGETARCH
ARG WITH_BROWSER=1

# 常用工具：ripgrep / curl / vim + 一批 recon 常备件（按需增删）
# Node 从 NodeSource 装 20.x：bookworm 自带 apt nodejs 是 18，Playwright 要求 >=20
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates ripgrep curl wget vim git jq unzip \
      dnsutils iputils-ping netcat-openbsd whois nmap \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# 预装 Playwright MCP/CLI + Chromium，让容器内 browser MCP 开箱即用
RUN if [ "$WITH_BROWSER" = "1" ]; then \
      apt-get update \
      && npm install -g @playwright/mcp@latest @playwright/cli@latest playwright@latest \
      && playwright-cli --help \
      && playwright install --with-deps chromium \
      && rm -rf /var/lib/apt/lists/*; \
    else \
      echo "skip playwright (WITH_BROWSER=0)"; \
    fi

# 报告生成依赖 python-docx（Go 侧渲染 .docx 时作为子进程调用 report_builder.py）
RUN pip install --no-cache-dir python-docx

WORKDIR /app

# 破甲版二进制（已内嵌破甲 skills + pierceSpec 硬注入）
COPY --from=build /out/antifox /app/antifox
RUN chmod +x /app/antifox
# 同时落一份 skill 目录：compose 把 ./skills 挂到 /app/skills（ANTIFOX_SKILL_DIR），
# 宿主目录缺失时用它兜底，保证 skill 库完整。
COPY skills/ /app/skills/

VOLUME ["/app/data"]
EXPOSE 8787 8788
ENTRYPOINT ["/app/antifox"]
CMD ["-addr", ":8787", "-proxy", ":8788"]
