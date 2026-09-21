# Nami

Nami 的公开发行仓库，提供安装入口与发布产物。

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
