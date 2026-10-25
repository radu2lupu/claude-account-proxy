# Source this from ~/.zshrc or ~/.bashrc. `claude` then goes through the account proxy when it is
# running on this host, and runs as before when it is not.
claude() {
  local port="${CLAUDE_ACCOUNT_PROXY_PORT:-48617}"
  if curl -s -m 1 -o /dev/null "http://127.0.0.1:${port}/_status"; then
    ANTHROPIC_BASE_URL="http://127.0.0.1:${port}" command claude "$@"
  else
    command claude "$@"
  fi
}
