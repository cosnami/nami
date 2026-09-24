#!/usr/bin/env bash

set +x
set -euo pipefail
export LC_ALL=C
umask 077

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: bash install.sh [--version TAG] [--repo OWNER/REPO]

Install or upgrade Nami Agent on Linux with systemd (x86_64 or ARM64).
Releases default to cosnami/nami and must include
nami-agent-linux-{x86_64,arm64}.zip and SHA256SUMS.
An omitted version installs the Agent release pinned by this script.
Use an explicit Agent tag, for example --version agent-v0.3.3.

First installation prompts for the control-plane URL, server UUID and credential.
For unattended installation, set NAMI_CONTROL_PLANE_URL, NAMI_SERVER_ID and
NAMI_AGENT_CREDENTIAL, or provision /etc/nami-agent/nami.toml beforehand.
Existing configuration and credentials are preserved on upgrades.
NAMI_REPOSITORY can supply the repository instead of --repo.

Service:       systemctl status nami-agent
Logs:          journalctl -u nami-agent -f
Configuration: /etc/nami-agent/nami.toml
State:         /var/lib/nami-agent
EOF
}

main() {
  repository=${NAMI_REPOSITORY:-cosnami/nami}
  version=agent-v0.3.3
  credential=${NAMI_AGENT_CREDENTIAL:-}
  unset NAMI_AGENT_CREDENTIAL
  while (($#)); do
    case "$1" in
      --repo|--version)
        (($# >= 2)) || die "$1 requires a value"
        case "$1" in
          --repo) repository=$2 ;;
          --version) version=$2 ;;
        esac
        shift 2
        ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1 (see --help)" ;;
    esac
  done

  [[ $repository =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
    || die 'Specify the GitHub release repository with --repo OWNER/REPO'
  [[ $version =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || die 'Invalid release tag'
  [[ $(uname -s) == Linux ]] || die 'This installer requires Linux'
  ((EUID == 0)) || die 'Run this installer as root'
  if [[ ! -d /run/systemd/system ]] || ! command -v systemctl >/dev/null; then
    die 'This installer requires a running systemd instance'
  fi
  case "$(uname -m)" in
    x86_64) architecture=x86_64 ;;
    aarch64|arm64) architecture=arm64 ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac

  binary=/usr/local/bin/nami-agent
  config_dir=/etc/nami-agent
  config=$config_dir/nami.toml
  unit=/etc/systemd/system/nami-agent.service
  service=nami-agent.service
  for path in "$binary" "$unit" "$config_dir" "$config" "$config_dir/credential"; do
    [[ ! -L $path ]] || die "Refusing to replace a symbolic link: $path"
  done

  command -v flock >/dev/null || die 'Install util-linux (flock) and retry'
  exec 9>/run/nami-agent-install.lock
  flock -n 9 || die 'Another Nami Agent installation is running'

  new_config=false
  if [[ ! -e $config ]]; then
    new_config=true
    control_plane_url=${NAMI_CONTROL_PLANE_URL:-}
    server_id=${NAMI_SERVER_ID:-}
    if [[ -z $control_plane_url || -z $server_id || -z $credential ]]; then
      exec 3<>/dev/tty || die 'Set NAMI_CONTROL_PLANE_URL, NAMI_SERVER_ID and NAMI_AGENT_CREDENTIAL for unattended installation'
      if [[ -z $control_plane_url ]]; then
        read -r -p 'Control-plane URL (https://...): ' control_plane_url <&3
      fi
      if [[ -z $server_id ]]; then
        read -r -p 'Server UUID: ' server_id <&3
      fi
      if [[ -z $credential ]]; then
        read -r -s -p 'Agent credential: ' credential <&3
        printf '\n' >&3
      fi
      exec 3>&-
    fi
    [[ -n $credential && ${#credential} -le 4096 && $credential != *[[:cntrl:]]* ]] \
      || die 'The credential must contain 1-4096 bytes without control characters'
    [[ $control_plane_url != *[[:cntrl:]]* && $server_id != *[[:cntrl:]]* ]] \
      || die 'Configuration values must not contain control characters'
    [[ ! -e $config_dir/credential ]] || die "A credential already exists; provision $config and retry"
  fi

  packages=()
  for command in curl unzip; do
    command -v "$command" >/dev/null || packages+=("$command")
  done
  if [[ ! -s /etc/ssl/certs/ca-certificates.crt && ! -s /etc/pki/tls/certs/ca-bundle.crt ]]; then
    packages+=(ca-certificates)
  fi
  if command -v apt-get >/dev/null; then
    command -v useradd >/dev/null || packages+=(passwd)
    if ((${#packages[@]})); then
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
    fi
  elif command -v dnf >/dev/null; then
    command -v useradd >/dev/null || packages+=(shadow-utils)
    if ((${#packages[@]})); then
      dnf install -y "${packages[@]}"
    fi
  elif ((${#packages[@]})); then
    die "Install these packages and retry: ${packages[*]}"
  fi
  for command in curl unzip sha256sum install useradd groupadd getent; do
    command -v "$command" >/dev/null || die "Required command is missing: $command"
  done

  mkdir -p /usr/local/bin
  work_dir=$(mktemp -d /usr/local/bin/.nami-agent-install.XXXXXX)
  rollback_needed=false
  was_active=false
  was_enabled=false
  enable_attempted=false

  rollback() {
    printf 'Installation failed; restoring the previous service.\n' >&2
    if [[ $(systemctl show --property=LoadState --value "$service") != not-found ]]; then
      systemctl stop "$service" || return 1
    fi
    if [[ -e $work_dir/previous-binary ]]; then
      mv -fT -- "$work_dir/previous-binary" "$binary" || return 1
    else
      rm -f -- "$binary" || return 1
    fi
    if $enable_attempted && ! $was_enabled; then
      systemctl disable "$service" >/dev/null 2>&1 || return 1
    fi
    if [[ -e $work_dir/previous-unit ]]; then
      cp -p -- "$work_dir/previous-unit" "$unit" || return 1
    else
      rm -f -- "$unit" || return 1
    fi
    systemctl daemon-reload || return 1
    if $was_active; then
      systemctl start "$service" || return 1
    fi
  }

  cleanup() {
    status=$?
    trap - EXIT
    if $rollback_needed && ! rollback; then
      printf 'Automatic recovery failed. Backups remain in %s\n' "$work_dir" >&2
      exit 1
    fi
    rm -rf -- "$work_dir"
    exit "$status"
  }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  download() {
    curl --fail --silent --show-error --location \
      --proto '=https' --proto-redir '=https' --tlsv1.2 \
      --connect-timeout 10 --max-time 180 --retry 3 "$@"
  }

  release_root=https://github.com/$repository/releases
  asset=nami-agent-linux-$architecture.zip
  printf 'Downloading Nami Agent %s (%s)...\n' "$version" "$architecture"
  download --max-filesize 134217728 --output "$work_dir/$asset" "$release_root/download/$version/$asset"
  download --max-filesize 1048576 --output "$work_dir/SHA256SUMS" "$release_root/download/$version/SHA256SUMS"
  checksum=$(awk -v asset="$asset" '$2 == asset { print $1 }' "$work_dir/SHA256SUMS")
  [[ $checksum =~ ^[[:xdigit:]]{64}$ ]] || die 'SHA256SUMS must contain exactly one checksum for the archive'
  (cd "$work_dir"; printf '%s  %s\n' "$checksum" "$asset" | sha256sum --check --status) \
    || die 'Archive checksum verification failed'
  [[ $(unzip -Z1 "$work_dir/$asset") == nami-agent ]] || die 'The archive must contain only the nami-agent binary'
  unzip -p "$work_dir/$asset" nami-agent > "$work_dir/nami-agent"
  chmod 0755 "$work_dir/nami-agent"
  "$work_dir/nami-agent" --version

  if $new_config; then
    control_plane_url=${control_plane_url//\\/\\\\}
    control_plane_url=${control_plane_url//\"/\\\"}
    server_id=${server_id//\\/\\\\}
    server_id=${server_id//\"/\\\"}
    cat > "$work_dir/nami.toml" <<EOF
version = 1
control_plane_url = "$control_plane_url"
server_id = "$server_id"
agent_credential = { file = "/etc/nami-agent/credential" }
EOF
    "$work_dir/nami-agent" check --config "$work_dir/nami.toml"
    printf '%s' "$credential" > "$work_dir/credential"
  else
    "$work_dir/nami-agent" check --config "$config"
  fi
  unset credential

  getent group nami-agent >/dev/null || groupadd --system nami-agent
  id -u nami-agent >/dev/null 2>&1 \
    || useradd --system --gid nami-agent --home-dir /var/lib/nami-agent --no-create-home --shell /usr/sbin/nologin nami-agent
  [[ $(id -u nami-agent) != 0 ]] || die 'The nami-agent account must not be root'
  install -d -m 0750 -o root -g nami-agent "$config_dir"
  if $new_config; then
    install -m 0640 -o root -g nami-agent "$work_dir/credential" "$config_dir/credential"
    install -m 0640 -o root -g nami-agent "$work_dir/nami.toml" "$config"
  fi

  cat > "$work_dir/nami-agent.service" <<'EOF'
[Unit]
Description=Nami Agent
Wants=network-online.target
After=network-online.target

[Service]
Type=exec
User=nami-agent
Group=nami-agent
ExecStartPre=/usr/local/bin/nami-agent check --config /etc/nami-agent/nami.toml
ExecStart=/usr/local/bin/nami-agent run --config /etc/nami-agent/nami.toml
Restart=on-failure
RestartSec=5s
TimeoutStopSec=90s
LimitNOFILE=1048576
UMask=0077
StateDirectory=nami-agent
StateDirectoryMode=0700
WorkingDirectory=/var/lib/nami-agent
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

  [[ ! -e $binary ]] || cp -p -- "$binary" "$work_dir/previous-binary"
  [[ ! -e $unit ]] || cp -p -- "$unit" "$work_dir/previous-unit"
  if systemctl is-active --quiet "$service"; then was_active=true; fi
  if systemctl is-enabled --quiet "$service"; then was_enabled=true; fi
  rollback_needed=true
  if $was_active; then systemctl stop "$service"; fi
  mv -fT -- "$work_dir/nami-agent" "$binary"
  install -m 0644 "$work_dir/nami-agent.service" "$unit"
  systemctl daemon-reload
  systemctl restart "$service"
  for ((attempt = 0; attempt < 5; attempt++)); do
    sleep 1
    if ! systemctl is-active --quiet "$service" \
      || [[ $(systemctl show --property=NRestarts --value "$service") != 0 ]]; then
      die "The service did not remain running; inspect journalctl -u $service"
    fi
  done
  enable_attempted=true
  systemctl enable "$service"
  rollback_needed=false
  printf 'Nami Agent %s installed and running.\nLogs: journalctl -u nami-agent -f\n' "$version"
}

main "$@"
