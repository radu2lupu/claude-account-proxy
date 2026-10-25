#!/usr/bin/env bash
# Installs the limitbreak as a login service for this user (launchd on macOS, a systemd
# user unit on Linux) and prints the one line that points `claude` at it.
#   install-limitbreak.sh [--dry-run] [--binary <prebuilt limitbreak>]
# Without --binary it is built from this directory (needs Go). For a host without Go, build
# elsewhere (GOOS=linux GOARCH=amd64 go build -o limitbreak .), copy the binary, this
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
  run install -m 755 "$binary" "$bin/limitbreak"
else
  run bash -c "cd '$here' && go build -o '$bin/limitbreak' ."
fi
run install -m 644 "$here/shell.sh" "$bin/limitbreak-shell.sh"

case "$(uname -s)" in
  Darwin)
    plist="${HOME}/Library/LaunchAgents/dev.limitbreak.plist"
    if ((dry)); then echo "+ write $plist"; else
      mkdir -p "$(dirname "$plist")"
      cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>dev.limitbreak</string>
  <key>ProgramArguments</key><array><string>${bin}/limitbreak</string></array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>${bin}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>${HOME}/Library/Logs/limitbreak.log</string>
</dict></plist>
PLIST
      # Earlier builds ran under other names; stop and remove them so two services never fight for the port.
      for label in com.hicomputers.claude-account-proxy dev.claude-account-proxy; do
        old="${HOME}/Library/LaunchAgents/${label}.plist"
        if [[ -f "$old" ]]; then launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true; rm -f "$old"; sleep 1; fi
      done
      launchctl bootout "gui/$(id -u)/dev.limitbreak" 2>/dev/null && sleep 1 || true
      launchctl bootstrap "gui/$(id -u)" "$plist"
    fi ;;
  Linux)
    unit="${HOME}/.config/systemd/user/limitbreak.service"
    if ((dry)); then echo "+ write $unit"; else
      mkdir -p "$(dirname "$unit")"
      systemctl --user disable --now claude-account-proxy.service 2>/dev/null || true
      rm -f "${HOME}/.config/systemd/user/claude-account-proxy.service"
      cat > "$unit" <<UNIT
[Unit]
Description=limitbreak

[Service]
ExecStart=${bin}/limitbreak
Environment=PATH=${bin}:/usr/local/bin:/usr/bin:/bin
Restart=always

[Install]
WantedBy=default.target
UNIT
      systemctl --user daemon-reload
      systemctl --user enable --now limitbreak.service
    fi ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

# Keep an old profile line working: the old shell file now just loads the new one.
rm -f "$bin/claude-account-proxy"
if [[ -f "$bin/claude-account-proxy-shell.sh" ]] && ! ((dry)); then
  echo 'source "$HOME/.local/bin/limitbreak-shell.sh"' > "$bin/claude-account-proxy-shell.sh"
fi
echo "Add to your shell profile:  source $bin/limitbreak-shell.sh"
