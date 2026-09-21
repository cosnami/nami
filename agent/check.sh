#!/usr/bin/env bash
set -euo pipefail

installer_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
artifacts=$(cd "${1:?Usage: bash agent/check.sh /path/to/releases/agent}" && pwd)
container=nami-agent-install-check-$$
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT

docker build --quiet --tag nami-agent-install-check - <<'DOCKERFILE'
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus curl ca-certificates unzip passwd util-linux \
    && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
DOCKERFILE

docker run --detach --name "$container" --privileged --cgroupns=private \
  --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
  --mount "type=bind,source=$installer_dir,target=/installer,readonly" \
  --mount "type=bind,source=$artifacts,target=/artifacts,readonly" \
  nami-agent-install-check >/dev/null

docker exec -i \
  --env NAMI_CONTROL_PLANE_URL=https://127.0.0.1:9443 \
  --env NAMI_SERVER_ID=8bd3eb25-11e0-4df8-ab25-772abe019590 \
  --env NAMI_AGENT_CREDENTIAL=installer-check-only \
  "$container" bash -se <<'CHECK'
for attempt in {1..30}; do
  if systemctl show-environment >/dev/null 2>&1; then break; fi
  sleep 1
done
systemctl show-environment >/dev/null

# Serve the supplied release files without publishing or contacting a control plane.
cp /artifacts/SHA256SUMS /tmp/SHA256SUMS
cat > /usr/local/bin/curl <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
output=
asset=
while (($#)); do
  case "$1" in
    --output) output=$2; shift ;;
    https://github.com/cosnami/nami/releases/download/agent-v*/*)
      asset=${1##*/} ;;
    https://*) exit 1 ;;
  esac
  shift
done
[[ -n $output && -n $asset ]]
if [[ $asset == SHA256SUMS ]]; then
  cp /tmp/SHA256SUMS "$output"
else
  cp "/artifacts/$asset" "$output"
fi
CURL
chmod +x /usr/local/bin/curl

sed -i 's/^[[:xdigit:]]\{64\}/0000000000000000000000000000000000000000000000000000000000000000/' /tmp/SHA256SUMS
if bash /installer/install.sh >/tmp/rejected.log 2>&1; then
  echo 'Installer accepted an invalid checksum' >&2
  exit 1
fi
grep -q 'Archive checksum verification failed' /tmp/rejected.log
test ! -e /usr/local/bin/nami-agent
test ! -e /etc/nami-agent/nami.toml
cp /artifacts/SHA256SUMS /tmp/SHA256SUMS

bash /installer/install.sh
systemctl is-active --quiet nami-agent
systemctl is-enabled --quiet nami-agent
test "$(systemctl show -p User --value nami-agent)" = nami-agent
test "$(systemctl show -p NRestarts --value nami-agent)" = 0
test "$(stat -c %a /etc/nami-agent/credential)" = 640
test "$(cat /etc/nami-agent/credential)" = installer-check-only
systemd-analyze verify /etc/systemd/system/nami-agent.service
sha256sum /etc/nami-agent/nami.toml /etc/nami-agent/credential > /tmp/config.sha256

NAMI_AGENT_CREDENTIAL=must-not-replace-existing bash /installer/install.sh
sha256sum --check /tmp/config.sha256
systemctl is-active --quiet nami-agent
test -z "$(find /usr/local/bin -maxdepth 1 -name '.nami-agent-install.*' -print)"
echo 'PASS: checksum rejection, first installation, systemd service, and preserved configuration'
CHECK
