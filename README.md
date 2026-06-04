# context-prompt

Displays your current environment contexts on the right side of your terminal prompt.

```
user@host ~/projects/myapp $                 <git:main><aws:prod><k8s:prod-cluster>
```

Works in **bash** and **zsh**. Pure shell — no binaries, no dependencies.

---

## Built-in providers

| Segment | Source |
|---|---|
| `<aws:profile>` | `$AWS_PROFILE` environment variable |
| `<k8s:context>` | `~/.kube/config` current context (no `kubectl` call) |
| `<git:branch>` | Current git branch or short SHA when detached |
| `<venv:name>` | Active Python virtualenv from `$VIRTUAL_ENV` |

---

## Installation

```bash
git clone https://github.com/mgaede01/context-prompt.git context-prompt
bash context-prompt/install.sh
```

The installer copies files to `~/.context-prompt/` and adds a source line to your `~/.bashrc` or `~/.zshrc`. Open a new terminal or reload your rc file to activate.

**Manual install** — add this line to your rc file yourself:

```bash
source ~/.context-prompt/context-prompt.sh
```

**Uninstall:**

```bash
bash context-prompt/uninstall.sh
```

This removes `~/.context-prompt/` and cleans the source line from your rc files. Run `exec $SHELL` afterwards to clear the `ctxp` function from the current session.

---

## `ctxp` command

After installation, the `ctxp` command is available in your shell:

```
ctxp enable  <provider>           re-enable a disabled provider
ctxp disable <provider>           hide a provider from the prompt
ctxp order   <provider> ...       set the left-to-right display order
ctxp color   <provider> [color]   show or set a provider's color
ctxp color   list                 list all available colors
ctxp list                         show all providers, their status, and color
ctxp status                       print what the right prompt currently shows
ctxp add     <name> '<cmd>'       register a custom one-liner provider
ctxp help                         show usage
```

---

## Managing providers

**See what's active:**
```
$ ctxp list
PROVIDER     STATUS     COLOR
aws          enabled    yellow
k8s          enabled    blue
git          enabled    green
venv         enabled    magenta
```

**Disable noisy providers:**
```bash
ctxp disable k8s    # hide k8s when not doing cluster work
ctxp disable git    # hide git branch if already in your PS1
```

**Re-enable later:**
```bash
ctxp enable k8s
```

---

## Changing display order

Use `ctxp order` to set exactly how providers appear left-to-right:

```bash
ctxp order k8s aws git
```

Any enabled provider you omit is automatically appended at the end. Disabled providers in the list are skipped (they must be enabled first).

**Check the current output:**
```bash
ctxp status
# <k8s:prod-cluster><aws:company-west><git:main>
```

---

## Changing colors

Use `ctxp color` with a color name:

```bash
ctxp color aws red        # highlight prod AWS account
ctxp color k8s cyan
ctxp color git none       # remove color from git segment
```

**Available colors** (run `ctxp color list` to preview them in your terminal):

| Standard | Bright variant |
|---|---|
| `red` | `brightred` |
| `green` | `brightgreen` |
| `yellow` | `brightyellow` |
| `blue` | `brightblue` |
| `magenta` | `brightmagenta` |
| `cyan` | `brightcyan` |
| `white` | `brightwhite` |
| `gray` / `grey` | — |
| `orange` | — |
| `none` | — |

Check what color a provider is currently using:
```bash
$ ctxp color aws
ctxp: aws color is 'red'
```

Color changes take effect immediately on the next prompt and are saved automatically (see [Persistence](#persistence)).

Set `NO_COLOR=1` to disable all colors globally (follows the [no-color.org](https://no-color.org) convention).

---

## Adding custom providers

**One-liner** — name plus a command string:
```bash
ctxp add terraform '
  ws=$(terraform workspace show 2>/dev/null) || return
  [[ "$ws" == "default" ]] && return
  printf "<tf:%s>" "$ws"
'
```

**Full form** — define a function with colors, then register it:
```bash
ctxp_provider_myapp() {
    [ -z "$MYAPP_ENV" ] && return
    printf "\033[36m<myapp:%s>\033[0m" "$MYAPP_ENV"
}
ctxp_register myapp
```

One-liner providers added with `ctxp add` are saved automatically and restored in new shells (see [Persistence](#persistence)). The **full form** above defines the function directly in your current shell, so put it in your rc file after the `source` line to have it persist.

---

## Persistence

Configuration changes are saved automatically and reapplied in every new shell — no need to edit your rc file. This covers:

- `ctxp enable` / `ctxp disable`
- `ctxp order`
- `ctxp color`
- `ctxp add` (one-liner custom providers)

State is written to `${XDG_CONFIG_HOME:-~/.config}/context-prompt/config`, an auto-generated file that is rewritten on each change. You normally never edit it by hand. To reset to defaults, delete it:

```bash
rm "${XDG_CONFIG_HOME:-$HOME/.config}/context-prompt/config"
```

The file is sourced once at startup, after the built-in providers load, so saved settings layer cleanly on top of the defaults.

---

## How it works

- **Zsh**: hooks into `precmd` and sets `RPROMPT` before each prompt
- **Bash**: prepends a function to `PROMPT_COMMAND` that uses `tput` to position the cursor at the right edge of the terminal

Providers that produce no output (e.g. `AWS_PROFILE` is unset) contribute nothing to the prompt — segments only appear when relevant.

---

## Development

The test suite runs under **both** bash and zsh — run it under each to exercise the shell-specific prompt and persistence paths:

```bash
bash test/test.sh     # bash
zsh  test/test.sh     # zsh
bash test/run.sh      # both (zsh auto-skipped if not installed)
```

Tests isolate their state in a temporary `XDG_CONFIG_HOME`, so running them never touches your real configuration.