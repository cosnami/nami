# Nami

Nami 的公开发行仓库，提供安装入口与发布产物。

## Nami Docker 镜像（内嵌 Web）

[nami Packages](https://github.com/cosnami/nami/pkgs/container/nami)
提供内嵌前端的服务端镜像，支持 Linux AMD64 / ARM64，可以匿名拉取：

```bash
docker pull ghcr.io/cosnami/nami:0.3.2
```

单个 Rust 进程提供页面、静态资源、HTTP API 和 Agent gRPC，共用 `4433` 端口。
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
  ghcr.io/cosnami/nami:0.3.2
```

打开 `http://127.0.0.1:4433/` 访问前端，健康检查为 `/api/health`。
`0.3.2` 和 `latest` 当前指向同一镜像，包含 SBOM 和构建来源记录。
需要固定产物时使用完整摘要：

```text
ghcr.io/cosnami/nami@sha256:0c93f3149e72e1b14a9b27743735c62e55b92b3971e3f0794b426379df415f09
```

## Server Docker 镜像

[nami-server Packages](https://github.com/cosnami/nami/pkgs/container/nami-server)
提供纯服务端镜像，支持 Linux AMD64 / ARM64，可以匿名拉取：

```bash
docker pull ghcr.io/cosnami/nami-server:0.3.2
```

镜像提供 HTTP API 和 Agent gRPC，共用 `4433` 端口，不包含前端。
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
  ghcr.io/cosnami/nami-server:0.3.2

curl --fail http://127.0.0.1:4433/api/health
```

通过入口网关转发 HTTP API 和 Agent gRPC；前端使用下方的独立 Web 镜像。
`0.3.2` 和 `latest` 当前指向同一镜像，包含 SBOM 和构建来源记录。
需要固定产物时使用完整摘要：

```text
ghcr.io/cosnami/nami-server@sha256:310281eee3f871e2cf4ee174b46fb633437067a746261c8fd981f78d2ca4babd
```

## Web Docker 镜像

[nami-web Packages](https://github.com/cosnami/nami/pkgs/container/nami-web)
提供独立前端镜像，支持 Linux AMD64 / ARM64，可以匿名拉取：

```bash
docker pull ghcr.io/cosnami/nami-web:0.3.2
docker run --rm --name nami-web -p 127.0.0.1:8080:8080 ghcr.io/cosnami/nami-web:0.3.2
```

前端容器监听 `8080`。部署时通过同源入口网关，将页面和静态资源转发到前端，
将 `/api` 和 `/api/*` 转发到 Nami Server，并保留完整请求路径。
Agent gRPC 继续使用服务端的 Agent 入口。

`0.3.2` 和 `latest` 当前指向同一镜像，包含 SBOM 和构建来源记录。
需要固定产物时使用版本号或完整摘要：

```text
ghcr.io/cosnami/nami-web@sha256:d739443ae9894756c6adbfa3dbd22a2f68d4351e58c1f5b0ae2da9c92a3bb5c1
```

## 安装 Agent

支持运行 systemd 的 Linux x86_64 / ARM64。以 root 身份执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/cosnami/nami/main/agent/install.sh)
```

首次安装会询问控制平面地址、Server UUID 和 Agent 凭据。凭据输入不会回显。
控制平面地址需要指向 Server 的 Agent gRPC 入口。

安装脚本会下载并验证 SHA-256 校验和，创建专用用户，将 Agent 注册为 systemd
服务并设置开机启动。重复执行会升级二进制并保留现有配置、凭据和运行数据。

默认版本固定在安装脚本中，目前为 `agent-v0.3.2`，不会跟随其他组件的 Release。
也可以指定版本：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/cosnami/nami/main/agent/install.sh) --version agent-v0.3.2
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

每个 ZIP 只包含静态链接的 `nami-agent` 可执行文件。Agent 通过二进制分发。

构建和发布新版本时，更新安装脚本的默认版本以及本文档中的版本号，并验证
两种架构的产物与校验和，再发布同名标签。正式发布后的产物不覆盖。

本地安装检查（需要 Docker，参数为待发布的 ZIP 和校验文件目录）：

```bash
bash agent/check.sh /path/to/releases/agent
```
