# codex-status

`codex-status` reads Codex usage and rate-limit reset-credit data from the
authenticated local Codex session and renders it for several status surfaces.

The ChatGPT backend routes used by this project are private product endpoints,
not a supported public API. Their schemas or availability can change.

## Requirements

- macOS or Linux
- Bash 3.2 or newer
- `curl`
- `jq`
- A local Codex login at `${CODEX_HOME:-$HOME/.codex}/auth.json`

## Install

```bash
./install.sh
```

This installs the runtime under:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/codex-status
```

An existing installed `formatters/theme.json` is preserved during reinstall so
local color and threshold overrides survive source updates. The latest packaged
defaults are always written to `formatters/theme.default.json` for comparison.

## Usage

```bash
~/.config/codex-status/codex-status.sh --usage --format pretty
~/.config/codex-status/codex-status.sh --credits --format pretty
~/.config/codex-status/codex-status.sh --usage --format json
~/.config/codex-status/codex-status.sh --usage --format tmux --compact
~/.config/codex-status/codex-status.sh --usage --format zellij --compact
```

Available formats:

- `json`: stable, machine-readable, PII-free output
- `pretty`: multiline terminal output using the shared muted theme
- `waybar`: Waybar JSON with Pango markup and tooltips
- `codexcli`: compact, unstyled footer text
- `tmux`: compact, unstyled status text
- `zellij`: compact, unstyled status text

`NO_COLOR=1` disables ANSI color in pretty output.

## Theme and gates

Colors and urgency thresholds are defined together in:

```text
~/.config/codex-status/formatters/theme.json
```

Both Waybar and pretty output use the same validated gate-selection code.

## Waybar

Example modules:

```jsonc
"custom/codex-usage": {
    "exec": "~/.config/codex-status/codex-status.sh --usage --format waybar --compact",
    "return-type": "json",
    "interval": 300,
    "tooltip": true
},
"custom/codex-credits": {
    "exec": "~/.config/codex-status/codex-status.sh --credits --format waybar --compact",
    "return-type": "json",
    "interval": 900,
    "tooltip": true
}
```

## Cache

Non-secret API responses are cached with user-only permissions:

- Linux: `${XDG_CACHE_HOME:-$HOME/.cache}/codex-status`
- macOS: `${XDG_CACHE_HOME:-$HOME/Library/Caches}/codex-status`

Authentication tokens are neither cached nor placed in process arguments.
