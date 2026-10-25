# limitbreak

<p align="center"><img src="assets/limitbreak.gif" alt="Arcade-style battle: an account's limit gauge fills, LIMIT BREAK, the next account takes over" width="640"></p>

```
   ★ L I M I T   B R E A K ★
   ADA    [██████████] LIMIT   → spent
   GRACE  [░░░░░░░░░░] ready   → takes the hit
```

Use several Claude accounts from **one** Claude Code install, and switch between them automatically when an account's usage limit is hit, without restarting the session or losing its history.

A small local proxy (a single Go binary, standard library only, a few MB of RAM) sits between `claude` and Anthropic's API. It sends each request on the active account's own login. When Anthropic answers that the account's 5-hour or weekly window is spent, the proxy remembers that account until its reset time and **replays the same request on the next account** before Claude Code ever sees the error. To the session nothing happened.

```
claude ──ANTHROPIC_BASE_URL──▶ proxy 127.0.0.1:48617 ──▶ api.anthropic.com
                                 │  active account's token
                                 └─ 429 "rejected"? mark spent, retry on the next account
```

Try it without touching any real login: `limitbreak video` plays a simulated switch in your terminal as a little arcade battle.

## Quick start

```sh
git clone https://github.com/radu2lupu/limitbreak && cd limitbreak
./install.sh                                   # builds and starts the background service
echo 'source "$HOME/.local/bin/limitbreak-shell.sh"' >> ~/.zshrc   # or ~/.bashrc
limitbreak add                       # sign in another account (browser), repeat per account
```

Open a new terminal and run `claude` as usual. When one account's limit is hit, the next one answers.

## What it does and does not touch

- Only `/v1/messages*` requests are sent on an account's token. Everything else (claude.ai connectors, MCP, artifacts, profile) goes through untouched with Claude Code's own credentials, so those keep working.
- It never sets `CLAUDE_CODE_OAUTH_TOKEN` (that makes Claude Code drop its connectors and local MCP servers).
- Accounts are the logins Claude Code already holds: the default one plus every `~/.claude-<name>` config directory that has a login. Tokens are read from the macOS Keychain item Claude Code keeps per config dir, or from `<dir>/.credentials.json`. They are never copied, logged, or exposed by `GET /_status`.
- An expired token is refreshed by running one tiny `claude -p` under that account's directory, so Claude Code stays the only thing that refreshes a login.
- If no account can serve a request, it passes through with Claude Code's own login: never worse than no proxy.
- Only a window rejection (`429` with `anthropic-ratelimit-unified-status: rejected`) switches accounts. Ordinary rate limits go back to Claude unchanged.

## Install

Needs Go 1.22+ to build, macOS or Linux. Prebuilt binaries are attached to each [release](../../releases).

```sh
git clone https://github.com/radu2lupu/limitbreak
cd limitbreak
./install.sh          # builds, installs ~/.local/bin/limitbreak, starts a launchd / systemd user service
```

Then add the printed line to `~/.zshrc` or `~/.bashrc`:

```sh
source "$HOME/.local/bin/limitbreak-shell.sh"
```

That defines a `claude` function that points Claude Code at the proxy when it is running and runs plain `claude` when it is not. Use `./install.sh --binary <prebuilt>` on a host without Go.

## Add accounts

```sh
limitbreak add            # signs in a new account in your browser, names it account-N
limitbreak add work       # or pick the name
limitbreak list           # accounts, who they are, which one is active (*)
limitbreak remove work    # sign it out and delete its login from this machine
```

`add` runs Claude Code's own browser sign-in into its own config directory (`~/.claude-<name>`), checks the login landed, tells you which email it is, and warns if you added the same account twice. The running proxy picks it up within 30 seconds; no restart. The default account is whatever plain `claude auth login` signs in. Raw status for scripts: `curl -s http://127.0.0.1:48617/_status`.

Every switch is logged (`~/Library/Logs/limitbreak.log` on macOS, the journal on Linux): the account that ran out, when it resets, and the one now serving.

## Options

`limitbreak serve --port 48617 --upstream https://api.anthropic.com --home ~ --credentials auto|keychain|file`

A request path may begin with `/_c/<client>/` to give a client (an agent, a tool) its own active account; the prefix is stripped before forwarding.

## Caveats, read these

- **Terms of service.** This uses the official `claude` binary with accounts you own, but spreading load across subscription accounts may conflict with Anthropic's terms for your plan. Read them; you are responsible for your use. Not affiliated with or endorsed by Anthropic.
- **Don't copy a login between machines.** Refresh tokens rotate; two machines holding the same one will log each other out. Sign in once per machine.
- **Headless hosts.** On macOS over SSH the Keychain is locked; run the proxy as a user service in the login session (what `install.sh` does).
- The reset time is read from Anthropic's response headers, which are not a documented contract and may change.

## Alternatives

You are not short of options. These are the projects I found that do something similar (read their READMEs, I have not audited them): [claude-swap](https://github.com/realiti4/claude-swap) (switches accounts at a usage threshold, dashboard), [teamclaude](https://github.com/KarpelesLab/teamclaude) (proxy that pools Claude, Codex and API-key accounts), [claude-rotate](https://github.com/clement-z/claude-rotate) (proxy with burst-aware 429 handling and analytics), [swisscode](https://github.com/jellologic/swisscode) (proxy with 429 failover and a traffic inspector), [claude-rotate by OpenGraphLabs](https://github.com/OpenGraphLabs/claude-rotate) (resumes the session on the next account).

This project's niche is being small and conservative: one dependency-free Go binary, it reuses the logins Claude Code already holds, switches mid-request so the session never restarts, and leaves connectors, MCP servers and artifacts alone. It has no dashboard, no pre-limit switching and no non-Claude providers.

## Uninstall

macOS: `launchctl bootout gui/$(id -u)/dev.limitbreak; rm ~/Library/LaunchAgents/dev.limitbreak.plist`.
Linux: `systemctl --user disable --now limitbreak`.
Then remove `~/.local/bin/limitbreak*` and the `source` line from your shell profile. Accounts you added stay as ordinary `~/.claude-<name>` logins; `limitbreak remove <name>` deletes one.

## Develop

```sh
go vet ./... && go test ./...
```

## License

MIT, see [LICENSE](LICENSE).
