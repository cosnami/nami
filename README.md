# Nami

Nami 的公开发行仓库，提供安装入口与发布产物。

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
