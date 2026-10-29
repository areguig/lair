# Lair

A macOS menu-bar app to talk with your coding agents by voice. Speech-to-text and text-to-speech run on your Mac.

**[Website](https://lair-voice.netlify.app)** · [Demo video](site/demo.mp4)

## What it does

- **Talk:** hold <kbd>⌥ Space</kbd>, speak, let go. The agent answers out loud. Talking over it cuts it off.
- **Just reply:** after the agent answers, Lair listens for a few seconds (a ring empties on the talk button and the orb). Talk, and it sends when you stop. Turn it off in Settings › General.
- **Floating orb:** during a call, the agent's orb floats above every window. Click it to talk, click again to send, drag to move it.
- **Several agents:** each call is a new session. Several can run at once; only the one in focus speaks, and the others tell you in one line when they're done or need you.
- **Switch agents:** start a sentence with an agent's name ("Iris, …"), click its name in the panel, or click its column in Mission Control.
- **Pass it on:** "Nova, ask Claude what it thinks", or "ask Echo to do it" to the agent you're talking to. The other agent gets your words and the last exchange, answers out loud, and the first one hears its answer on its next turn.
- **Approvals:** when an agent asks before acting, answer by voice, in the panel or from the notification. The first answer wins. Nothing is approved automatically.
- **Model and thinking:** pick them from the model line, or say "switch to Opus", "think harder", "go fast", "go deep".
- **Mission Control** (<kbd>⌥ ⌘ L</kbd>): each agent's whole stream side by side, with tool calls, diffs, thinking, timings and cost, a line to type in, and Allow/Deny on approvals.
- **Show, don't say:** links and paths appear as chips on screen and are never read aloud.

## Agents

| Kind | Runs | Needs |
|---|---|---|
| `claude-code` | `claude -p`, one process per call | [Claude Code](https://claude.com/claude-code), signed in |
| `omp` | `omp --mode rpc`, one process per call | [omp](https://github.com/can1357/oh-my-pi), signed in |
| `hermes` | Hermes' OpenAI-compatible API server | Its address and API key |

## Requirements

- macOS 15 or later on Apple Silicon
- Swift 6.4 (Xcode 27), only to build it yourself

The first launch downloads the speech models (Parakeet, Kokoro) through [FluidAudio](https://github.com/FluidInference/FluidAudio).

## Install

Download `Lair-vX.Y.Z.dmg` from [Releases](https://github.com/areguig/lair/releases) and drag Lair to Applications. The app isn't notarized yet, so macOS blocks the first launch. Allow it once in System Settings › Privacy & Security › Open Anyway, or run:

```sh
xattr -d com.apple.quarantine /Applications/Lair.app
```

## Build

```sh
scripts/build-app.sh      # builds and installs ~/Applications/Lair.app
scripts/make-dmg.sh       # or wraps it in .build/Lair.dmg
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
| `disabled` | `true` turns the agent off: it keeps its settings but leaves the panel and Mission Control (the **On** switch in Settings) |

At the top level, `"listenForAnswers": false` stops Lair listening for your reply after each answer.

Secrets (API keys, header values) live in the Keychain, never in the file. A soul, which is extra instructions for one Claude Code or omp agent, is a Markdown file at `~/.config/lair/souls/<id>.md`.

## Troubleshooting

- What happened: `log show --last 1h --predicate 'subsystem == "dev.lair.app"'`. This shows each call
  start, agent process start and exit, output an agent printed outside its protocol, every problem
  shown in the panel, and turn timings.
- Agent error output: `~/Library/Logs/Lair/<id>.log`

## Credits

- [FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache 2.0) runs the speech models on the Neural Engine.
- [Parakeet TDT 0.6B v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) by NVIDIA (CC-BY-4.0) for speech-to-text.
- [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) (Apache 2.0) for the voices.
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT) for the global shortcuts.

The models download on first launch; they're not part of this repository.

## License

[MIT](LICENSE)
