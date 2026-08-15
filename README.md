# dsh-subagent-route-inheritance

A DSH host plugin that keeps in-process subagent children on their **parent's
live provider/model/reasoning-effort route** instead of the parent's
creation-time `AgentOptions`.

## What it fixes

Two DeepSeek Harness (`@deepseek-ai/dsh` 0.1.0-rc.x) subagent defects:

1. **Model goes stale after a manual switch.** A session model switch only
   writes the session-local selection that `installModelSelection` applies to
   the parent's own requests; `agent.options` is never rewritten. Subagents
   inherit their route from `parent.options`, so children spawned after a
   switch run on the pre-switch model.
2. **`reasoningEffort` is dropped.** `resolveChildAgentOptions` copies only
   provider/model/maxTokens, and a fresh child has neither a persisted request
   header nor a model-selection listener — its first request carries no effort
   and silently falls back to the adapter default.

The parent's logged `request/header` is refreshed at the start of every step,
before any tool call, so it holds the parent's effective route at delegation
time. This plugin mirrors that route onto every child request (and
prompt-assembly `provider`/`model` variables) for the child's whole lifetime,
so a switch mid-child takes effect at the next request — the same
step-boundary semantics the parent's own selection has.

Explicit per-child route overrides (`agentOptions` on the delegation tool) are
left untouched, and an adapter-defaulted effort is never inherited (the
child's own adapter re-materializes its default).

## How it works

The plugin is a plain Cordis function plugin (`name` / `inject` / `apply`):

- listens on `agent/created`;
- for each child (identified by `session.header.parentSession`), installs
  `agent/request` (waterfall) and `system-prompt/assemble` (waterfall)
  listeners on the child's own context;
- each listener reads the live parent's `session.requestHeader()` config and
  applies it to the child's request / assembly variables.

No harness source is modified; the fix lives entirely at the composition
layer.

## Install

The install scripts copy `plugin/subagent-route-inheritance.mjs` into
`<dsh-home>/profiles/<profile>/plugins/` and add the row to the profile's
`cordis.patch.yml` as its own `- insert:` block. Installing twice is a no-op.

The dsh home resolves as `$DSH_HOME`, else `~/.dsh` (Linux/macOS) or
`$HOME\.dsh` (Windows). The default profile is `web`; pass `-Profiles
web,headless` / `--profile headless` or `--all` to cover more profiles.

### Linux / macOS

```sh
./install.sh                 # web profile
./install.sh --all           # web + headless
DSH_HOME=/path/to/.dsh ./install.sh --profile web
```

### Windows (PowerShell)

```powershell
.\install.ps1                 # web profile
.\install.ps1 -All            # web + headless
.\install.ps1 -Profiles web,headless
```

> Execution policy note: if script execution is restricted, run
> `powershell -ExecutionPolicy Bypass -File .\install.ps1`.

Then **restart dsh** (or reload the web profile). The plugin row loads with
the composition; no rebuild is needed.

## Uninstall

```sh
./uninstall.sh               # Linux / macOS
.\uninstall.ps1              # Windows PowerShell
```

Both remove the plugin file and the insert block (or its row lines, if the
block was hand-edited) from each profile's `cordis.patch.yml`, leaving all
other patch content untouched. Restart dsh afterwards.

## Verify

Spawn any subagent, then inspect the child's persisted session log
(`<dsh-home>/sessions/<workspace>/<child-id>/session.jsonl.zstd`): its
`request/header` config should now match the parent's current route, including
`reasoningEffort` when the parent owns one.

## Layout

```
plugin/subagent-route-inheritance.mjs   the plugin (canonical copy)
install.sh / uninstall.sh               Linux / macOS helpers
install.ps1 / uninstall.ps1             Windows PowerShell helpers
```

## Notes

- Applies to the in-process spawn / fork / continuable / workflow subagent
  providers that ship with the default `dsh` profiles.
- A companion upstream source fix (with tests) lives on the
  `fix/subagent-route-inheritance-source` branch of the deepseek-harness
  clone that produced this plugin; this repo deliberately avoids patching
  harness source.

## License

MIT — see [LICENSE](LICENSE).
