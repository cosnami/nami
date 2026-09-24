# Nami

Nami 的公开发行仓库，提供安装入口与发布产物。

## Release 安装包

| 组件 | 产物 | 当前版本 |
| --- | --- | --- |
| `nami` | 内嵌 Web 的 Linux 静态二进制，x86_64 / ARM64 | [nami-v0.3.3](https://github.com/cosnami/nami/releases/tag/nami-v0.3.3) |
| `nami-server` | 纯服务端 Linux 静态二进制，x86_64 / ARM64 | [server-v0.3.3](https://github.com/cosnami/nami/releases/tag/server-v0.3.3) |
| `nami-web` | 与 CPU 架构无关的 Web 静态文件包 | [web-v0.3.3](https://github.com/cosnami/nami/releases/tag/web-v0.3.3) |
| `nami-agent` | Linux 静态二进制，x86_64 / ARM64 | [agent-v0.3.3](https://github.com/cosnami/nami/releases/tag/agent-v0.3.3) |

Server 和 Agent 需配套升级到 `0.3.3`：Agent 控制面已由 gRPC 改为 HTTP JSON，
旧版 Agent 与新版 Server 不兼容。入口网关保留 `/api/agent/runtime/*` 路径。

每个 Release 提供 ZIP、`SHA256SUMS` 和 `release-manifest.json`。清单记录来源镜像
的固定摘要、源码提交以及产物校验和；版本发布后不覆盖附件。

`nami-linux-<架构>.zip`、`nami-server-linux-<架构>.zip` 分别包含 `nami`、
`nami-server` 可执行文件和 `config.example.toml`。解压后复制示例为 `config.toml`，
填写 PostgreSQL、Redis 连接、唯一的 Accounts 密钥及管理员邮箱、密码，再启动：

```bash
./nami --config config.toml
# 或使用纯服务端：
./nami-server --config config.toml
```

系统需要可用的 CA 证书。程序启动会自动执行数据库迁移，连接已有数据库前先备份。
内嵌版本启动后访问配置的监听地址即可打开前端。

`nami-web-static.zip` 仅包含 `index.html`、JS、CSS、字体和公共资源，可交给静态
服务器托管，无需 Bun 或 Node。页面导航需要回退到 `index.html`，缺失的静态资源
返回 404；同源 `/api` 和 `/api/*` 转发到 Nami Server 并保留完整路径。
Agent HTTP API 继续使用服务端的 Agent 入口。

### 制作 Release 安装包

维护者使用 Docker / Buildx、Python 3.11+ 和 `file`，从已验证的公开镜像导出产物：

```bash
python3 scripts/package-release.py nami 0.3.3
python3 scripts/package-release.py nami-server 0.3.3
python3 scripts/package-release.py nami-web 0.3.3
python3 scripts/package-release.py nami-agent 0.3.3
```

脚本先将版本标签解析为固定镜像摘要，再提取并检查两个架构的产物。
Web 两种架构的静态文件必须完全一致，才会生成一个通用 ZIP。
结果写入 `releases/<组件标签>/`；已有目录会拒绝覆盖。

## Nami Docker 镜像（内嵌 Web）

[nami Packages](https://github.com/cosnami/nami/pkgs/container/nami)
提供内嵌前端的服务端镜像，支持 Linux AMD64 / ARM64，可以匿名拉取：

```bash
docker pull ghcr.io/cosnami/nami:0.3.3
```

单个 Rust 进程提供页面、静态资源、HTTP API 和 Agent HTTP API，共用 `4433` 端口。
前端以 SPA 方式运行，资源编入二进制。配置要求与下方的
[Server 镜像](#server-docker-镜像) 相同，使用 `/etc/nami/config.toml`。

下面假设 PostgreSQL、Redis 已在 Docker 网络 `nami` 中就绪，当前目录有已配置完成的
`config.toml`。程序启动会自动执行数据库迁移；连接已有数据库前先完成备份。

```bash
docker run -d --name nami --restart unless-stopped \
  --network nami \
  --read-only \
  --mount type=bind,source="$(pwd)/config.toml",target=/etc/nami/config.toml,readonly \
  -p 127.0.0.1:4433:4433 \
  ghcr.io/cosnami/nami:0.3.3
```

打开 `http://127.0.0.1:4433/` 访问前端，健康检查为 `/api/health`。
`0.3.3` 和 `latest` 当前指向同一镜像，包含 SBOM 和构建来源记录。
需要固定产物时使用完整摘要：

```text
ghcr.io/cosnami/nami@sha256:d0e0ddeab3063fcd0cbc315fda1cc78562e237844c089ff9ccaea4de8149b015
```

## Server Docker 镜像

[nami-server Packages](https://github.com/cosnami/nami/pkgs/container/nami-server)
提供纯服务端镜像，支持 Linux AMD64 / ARM64，可以匿名拉取：

```bash
docker pull ghcr.io/cosnami/nami-server:0.3.3
```

镜像提供 HTTP API 和 Agent HTTP API，共用 `4433` 端口，不包含前端。
运行前准备 `config.toml`：将 `server.listen` 设置为 `0.0.0.0:4433`，
将 `database`、`cache` 配置为容器可达的 PostgreSQL、Redis 地址及凭据，
设置唯一的 `accounts.secret_key`（32 字节 base64url 密钥）和管理员邮箱、密码。
配置文件需对容器用户 `65532:65532` 可读。

下面假设 PostgreSQL、Redis 已在 Docker 网络 `nami` 中就绪，配置文件位于当前目录。
程序启动会自动执行数据库迁移；连接已有数据库前先完成备份。

```bash
docker run -d --name nami-server --restart unless-stopped \
  --network nami \
  --read-only \
  --mount type=bind,source="$(pwd)/config.toml",target=/etc/nami/config.toml,readonly \
  -p 127.0.0.1:4433:4433 \
  ghcr.io/cosnami/nami-server:0.3.3

curl --fail http://127.0.0.1:4433/api/health
```

通过入口网关转发 HTTP API 和 Agent HTTP API；前端使用下方的独立 Web 镜像。
`0.3.3` 和 `latest` 当前指向同一镜像，包含 SBOM 和构建来源记录。
需要固定产物时使用完整摘要：

```text
ghcr.io/cosnami/nami-server@sha256:e4d2e06fa7cacdedcda1d4ea490cd597bef094e729f53b6a2a0874cbe91154f5
```

## Web Docker 镜像

[nami-web Packages](https://github.com/cosnami/nami/pkgs/container/nami-web)
提供独立前端镜像，支持 Linux AMD64 / ARM64，可以匿名拉取：

```bash
docker pull ghcr.io/cosnami/nami-web:0.3.3
docker run --rm --name nami-web -p 127.0.0.1:8080:8080 ghcr.io/cosnami/nami-web:0.3.3
```

前端容器监听 `8080`。部署时通过同源入口网关，将页面和静态资源转发到前端，
将 `/api` 和 `/api/*` 转发到 Nami Server，并保留完整请求路径。
Agent HTTP API 继续使用服务端的 Agent 入口。

`0.3.3` 和 `latest` 当前指向同一镜像，包含 SBOM 和构建来源记录。
需要固定产物时使用版本号或完整摘要：

```text
ghcr.io/cosnami/nami-web@sha256:6411fc16fc05137cb0901376e929c2e439241a09698f26d8fb7f680d2c62f323
```

## Agent Docker 镜像

[nami-agent Packages](https://github.com/cosnami/nami/pkgs/container/nami-agent)
提供 Agent 镜像，支持 Linux AMD64 / ARM64，可以匿名拉取：

```bash
docker pull ghcr.io/cosnami/nami-agent:0.3.3
```

在部署 Agent 的 Linux 主机准备 `/etc/nami-agent/nami.toml`：

```toml
version = 1
control_plane_url = "https://nami.example.com"
server_id = "8bd3eb25-11e0-4df8-ab25-772abe019590"

[agent_credential]
file = "/etc/nami-agent/credential"
```

替换控制平面地址和 Server UUID，将管理端签发的 Agent 凭据单独写入
`/etc/nami-agent/credential`。控制平面地址指向 Agent HTTP API 的 HTTPS 源地址；
仅回环地址允许使用 HTTP。配置目录和文件需对容器用户 `65532:65532` 可读，
凭据文件不要向其他用户开放。

```bash
docker run --rm --network none --read-only \
  --mount type=bind,source=/etc/nami-agent,target=/etc/nami-agent,readonly \
  ghcr.io/cosnami/nami-agent:0.3.3 check --config /etc/nami-agent/nami.toml

docker run -d --name nami-agent --restart unless-stopped \
  --network host \
  --read-only \
  --cap-drop ALL --cap-add NET_BIND_SERVICE \
  --ulimit nofile=1048576:1048576 \
  --mount type=bind,source=/etc/nami-agent,target=/etc/nami-agent,readonly \
  --mount type=volume,source=nami-agent-data,target=/var/lib/nami-agent \
  ghcr.io/cosnami/nami-agent:0.3.3
```

`check` 只校验配置结构，不读取凭据或连接控制平面。
Linux host 网络用于监听管理端下发的协议端口；ACME HTTP-01 还需要可用且公网可达的
`80/tcp`。Docker Desktop、Colima 的网络与系统指标以其 Linux 虚拟机环境为准。

`/var/lib/nami-agent` 保存流量待上传记录和证书状态，需要持久化。新命名卷继承镜像
中的 `65532:65532` 所有者和 `0700` 权限；已有卷或绑定目录应由该用户拥有并可读写。
使用 `docker logs -f nami-agent` 查看日志，`docker stop nami-agent` 正常退出。

`0.3.3` 和 `latest` 当前指向同一镜像，包含 SBOM 和构建来源记录。
需要固定产物时使用完整摘要：

```text
ghcr.io/cosnami/nami-agent@sha256:1929e3b0cbd7e80be01b1a1d72c72f4f413c94fc8ba0db04e05188a0b470bd03
```

## 安装 Agent

支持运行 systemd 的 Linux x86_64 / ARM64。以 root 身份执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/cosnami/nami/main/agent/install.sh)
```

首次安装会询问控制平面地址、Server UUID 和 Agent 凭据。凭据输入不会回显。
控制平面地址需要指向 Server 的 Agent HTTP API 入口。

安装脚本会下载并验证 SHA-256 校验和，创建专用用户，将 Agent 注册为 systemd
服务并设置开机启动。重复执行会升级二进制并保留现有配置、凭据和运行数据。

默认版本固定在安装脚本中，目前为 `agent-v0.3.3`，不会跟随其他组件的 Release。
也可以指定版本：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/cosnami/nami/main/agent/install.sh) --version agent-v0.3.3
```

无人值守安装可以预先配置 `/etc/nami-agent/nami.toml`，或者设置
`NAMI_CONTROL_PLANE_URL`、`NAMI_SERVER_ID`、`NAMI_AGENT_CREDENTIAL`。

```bash
systemctl status nami-agent
journalctl -u nami-agent -f
```

配置位于 `/etc/nami-agent/nami.toml`，凭据位于 `/etc/nami-agent/credential`，
运行数据位于 `/var/lib/nami-agent`。

## Agent 发布

[Releases](https://github.com/cosnami/nami/releases) 使用 `agent-vX.Y.Z` 标签。
每个 Agent Release 包含：

- `nami-agent-linux-x86_64.zip`
- `nami-agent-linux-arm64.zip`
- `SHA256SUMS`
- `release-manifest.json`

每个 ZIP 只包含静态链接的 `nami-agent` 可执行文件，供上方的 systemd 安装脚本使用。
Docker 部署使用 Packages 中的 `nami-agent` 镜像。

构建和发布新版本时，更新安装脚本的默认版本以及本文档中的版本号，并验证
两种架构的产物与校验和，再发布同名标签。正式发布后的产物不覆盖。

本地安装检查（需要 Docker，参数为待发布的 ZIP 和校验文件目录）：

```bash
bash agent/check.sh /path/to/releases/agent
```
