#!/usr/bin/env bash
# Installs the Claude account proxy as a login service for this user (launchd on macOS, a systemd
# user unit on Linux) and prints the one line that points `claude` at it.
#   install-claude-account-proxy.sh [--dry-run] [--binary <prebuilt claude-account-proxy>]
# Without --binary it is built from this directory (needs Go). For a host without Go, build
# elsewhere (GOOS=linux GOARCH=amd64 go build -o claude-account-proxy .), copy the binary, this
# script and shell.sh to the host, and pass --binary.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin="${HOME}/.local/bin"
dry=0
binary=""
while (($#)); do
  case "$1" in
    --dry-run) dry=1 ;;
    --binary) binary="$2"; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done
run() { if ((dry)); then echo "+ $*"; else "$@"; fi; }

run mkdir -p "$bin"
if [[ -n "$binary" ]]; then
  run install -m 755 "$binary" "$bin/claude-account-proxy"
else
  run bash -c "cd '$here' && go build -o '$bin/claude-account-proxy' ."
fi
run install -m 644 "$here/shell.sh" "$bin/claude-account-proxy-shell.sh"

case "$(uname -s)" in
  Darwin)
    plist="${HOME}/Library/LaunchAgents/dev.claude-account-proxy.plist"
    if ((dry)); then echo "+ write $plist"; else
      mkdir -p "$(dirname "$plist")"
      cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.claude-account-proxy</string>
  <key>ProgramArguments</key><array><string>${bin}/claude-account-proxy</string></array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>${bin}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>${HOME}/Library/Logs/claude-account-proxy.log</string>
</dict></plist>
PLIST
      # An earlier build used another label; stop and remove it so two services never fight for the port.
      old="${HOME}/Library/LaunchAgents/com.hicomputers.claude-account-proxy.plist"
      if [[ -f "$old" ]]; then launchctl bootout "gui/$(id -u)/com.hicomputers.claude-account-proxy" 2>/dev/null || true; rm -f "$old"; sleep 1; fi
      launchctl bootout "gui/$(id -u)/dev.claude-account-proxy" 2>/dev/null && sleep 1 || true
      launchctl bootstrap "gui/$(id -u)" "$plist"
    fi ;;
  Linux)
    unit="${HOME}/.config/systemd/user/claude-account-proxy.service"
    if ((dry)); then echo "+ write $unit"; else
      mkdir -p "$(dirname "$unit")"
      cat > "$unit" <<UNIT
[Unit]
Description=Claude account proxy

[Service]
ExecStart=${bin}/claude-account-proxy
Environment=PATH=${bin}:/usr/local/bin:/usr/bin:/bin
Restart=always

[Install]
WantedBy=default.target
UNIT
      systemctl --user daemon-reload
      systemctl --user enable --now claude-account-proxy.service
    fi ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

echo "Add to your shell profile:  source $bin/claude-account-proxy-shell.sh"
