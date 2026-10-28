# Lair

A macOS menu-bar app to talk with your coding agents by voice. Speech-to-text and text-to-speech run on your Mac.

[Demo video](docs/demo.mp4)

## What it does

- **Talk:** hold <kbd>⌥ Space</kbd>, speak, let go. The agent answers out loud. Talking over it cuts it off.
- **Floating orb:** during a call, the agent's orb floats above every window. Click it to talk, click again to send, drag to move it.
- **Several agents:** each call is a new session. Several can run at once; only the one in focus speaks, and the others tell you in one line when they're done.
- **Approvals:** when an agent asks before acting, answer by voice, in the panel or from the notification. The first answer wins. Nothing is approved automatically.
- **Model and thinking:** pick them from the model line, or say "switch to Opus", "think harder", "go fast", "go deep".
- **Mission Control** (<kbd>⌥ ⌘ L</kbd>): each agent's whole stream side by side, with tool calls, diffs, thinking, timings and cost, and a line to type in.
- **Show, don't say:** links and paths appear as chips on screen and are never read aloud.

## Agents

| Kind | Runs | Needs |
|---|---|---|
| `claude-code` | `claude -p`, one process per call | [Claude Code](https://claude.com/claude-code), signed in |
| `omp` | `omp --mode rpc`, one process per call | [omp](https://github.com/can1357/oh-my-pi), signed in |
| `hermes` | Hermes' OpenAI-compatible API server | Its address and API key |

## Requirements

- macOS 15 or later on Apple Silicon
- Swift 6.2 (Xcode 26)

The first launch downloads the speech models (Parakeet, Kokoro) through [FluidAudio](https://github.com/FluidInference/FluidAudio).

## Build

```sh
scripts/build-app.sh      # builds and installs ~/Applications/Lair.app
open ~/Applications/Lair.app
```

The script signs the app with your Apple Development certificate if you have one, so the microphone permission survives rebuilds. Set `LAIR_SIGN_IDENTITY` to pick another identity.

```sh
swift build
swift test
```

## Configure

Use **Settings…** in the panel, or edit `~/.config/lair/config.json`, which Lair writes with defaults on first launch:

```json
{
  "agents": [
    { "id": "claude", "name": "Claude", "kind": "claude-code", "voice": "af_heart", "color": "#D97757",
      "model": "sonnet", "directory": "~/projects" },
    { "id": "home", "name": "Home", "kind": "hermes", "voice": "bf_emma", "color": "#7B5CFF",
      "url": "http://hermes.local:8642" }
  ]
}
```

| Field | Meaning |
|---|---|
| `voice` | A Kokoro English voice: `af_*`, `am_*` (American), `bf_*`, `bm_*` (British) |
| `model`, `thinking` | Starting model and thinking level; unset uses the agent's own default |
| `directory` | Working folder for Claude Code and omp sessions |
| `permissionMode` | Claude Code's `--permission-mode`; unset keeps your Claude Code settings |
| `url`, `headers` | Hermes: API address, and names of extra headers such as a proxy token |

Secrets (API keys, header values) live in the Keychain, never in the file. A soul, which is extra instructions for one Claude Code or omp agent, is a Markdown file at `~/.config/lair/souls/<id>.md`.

## Troubleshooting

- What happened: `log show --last 1h --predicate 'subsystem == "dev.lair.app"'`. This shows each call
  start, agent process start and exit, output an agent printed outside its protocol, every problem
  shown in the panel, and turn timings.
- Agent error output: `~/Library/Logs/Lair/<id>.log`
