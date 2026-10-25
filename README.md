# claude-account-proxy

Use several Claude accounts from **one** Claude Code install, and switch between them automatically when an account's usage limit is hit, without restarting the session or losing its history.

A small local proxy (a single Go binary, standard library only, a few MB of RAM) sits between `claude` and Anthropic's API. It sends each request on the active account's own login. When Anthropic answers that the account's 5-hour or weekly window is spent, the proxy remembers that account until its reset time and **replays the same request on the next account** before Claude Code ever sees the error. To the session nothing happened.

```
claude ──ANTHROPIC_BASE_URL──▶ proxy 127.0.0.1:48617 ──▶ api.anthropic.com
                                 │  active account's token
                                 └─ 429 "rejected"? mark spent, retry on the next account
```

## What it does and does not touch

- Only `/v1/messages*` requests are sent on an account's token. Everything else (claude.ai connectors, MCP, artifacts, profile) goes through untouched with Claude Code's own credentials, so those keep working.
- It never sets `CLAUDE_CODE_OAUTH_TOKEN` (that makes Claude Code drop its connectors and local MCP servers).
- Accounts are the logins Claude Code already holds: the default one plus every `~/.claude-<name>` config directory that has a login. Tokens are read from the macOS Keychain item Claude Code keeps per config dir, or from `<dir>/.credentials.json`. They are never copied, logged, or exposed by `GET /_status`.
- An expired token is refreshed by running one tiny `claude -p` under that account's directory, so Claude Code stays the only thing that refreshes a login.
- If no account can serve a request, it passes through with Claude Code's own login: never worse than no proxy.
- Only a window rejection (`429` with `anthropic-ratelimit-unified-status: rejected`) switches accounts. Ordinary rate limits go back to Claude unchanged.

## Install

Needs Go 1.22+ to build, macOS or Linux.

```sh
git clone https://github.com/radu2lupu/claude-account-proxy
cd claude-account-proxy
./install.sh          # builds, installs ~/.local/bin/claude-account-proxy, starts a launchd / systemd user service
```

Then add the printed line to `~/.zshrc` or `~/.bashrc`:

```sh
source "$HOME/.local/bin/claude-account-proxy-shell.sh"
```

That defines a `claude` function that points Claude Code at the proxy when it is running and runs plain `claude` when it is not. Use `./install.sh --binary <prebuilt>` on a host without Go.

## Add accounts

Log each account in once into its own config directory:

```sh
CLAUDE_CONFIG_DIR=~/.claude-work claude auth login --claudeai
CLAUDE_CONFIG_DIR=~/.claude-second claude auth login --claudeai
```

The proxy rediscovers `~/.claude-*` every 30 seconds; no restart. Check with:

```sh
curl -s http://127.0.0.1:48617/_status
```

Every switch is logged (`~/Library/Logs/claude-account-proxy.log` on macOS, the journal on Linux): the account that ran out, when it resets, and the one now serving.

## Options

`claude-account-proxy --port 48617 --upstream https://api.anthropic.com --home ~ --credentials auto|keychain|file`

A request path may begin with `/_c/<client>/` to give a client (an agent, a tool) its own active account; the prefix is stripped before forwarding.

## Caveats, read these

- **Terms of service.** This uses the official `claude` binary with accounts you own, but spreading load across subscription accounts may conflict with Anthropic's terms for your plan. Read them; you are responsible for your use. Not affiliated with or endorsed by Anthropic.
- **Don't copy a login between machines.** Refresh tokens rotate; two machines holding the same one will log each other out. Sign in once per machine.
- **Headless hosts.** On macOS over SSH the Keychain is locked; run the proxy as a user service in the login session (what `install.sh` does).
- The reset time is read from Anthropic's response headers, which are not a documented contract and may change.

## Develop

```sh
go vet ./... && go test ./...
```

## License

MIT, see [LICENSE](LICENSE).
