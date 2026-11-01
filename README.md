# Lair

A macOS menu-bar app to talk with your coding agents by voice. Speech-to-text and text-to-speech run on your Mac.

**[Website](https://lair-voice.netlify.app)** · [Demo video](site/demo.mp4)

## What it does

- **Talk:** hold <kbd>⌥ Space</kbd>, speak, let go. The agent answers out loud. Talking over it cuts it off.
- **Just reply:** after the agent answers, Lair listens for a few seconds (a ring empties on the talk button). Talk, and it sends when you stop. Turn it off in Settings › General.
- **The island:** Lair grows out of the notch when an agent talks or needs you, with its choices and OKs right there, and gets out of the way after. It never steals focus.
- **Agents in your terminal:** connect Claude Code or omp in Settings › On this Mac. Every session you start yourself can then speak to you and ask you out loud. Any other MCP agent can join too: Lair is a local MCP server with two tools, speak and ask.
- **Choices:** a question can come with choices, read out and shown as numbered buttons. Click one, press <kbd>⌘ 1</kbd>, or say "the blue one".
- **They come back by themselves:** when an agent's background work finishes, it tells you as soon as the call is free, then listens for your reply.
- **Several agents:** each call is a new session. Several can run at once; only the one in focus speaks, and the others tell you in one line when they're done or need you.
- **Switch agents:** start a sentence with an agent's name ("Iris, …"), click its name in the panel, or click its column in Mission Control.
- **Pass it on:** "Nova, ask Claude what it thinks", or "ask Echo to do it" to the agent you're talking to. The other agent gets your words and the last exchange, answers out loud, and the first one hears its answer on its next turn.
- **Approvals:** when an agent asks before acting, answer by voice, in the panel or from the notification. The first answer wins. Lair never approves by itself; each agent's own approval mode (Claude's Accept edits, Copilot's Allow all…) is in Settings.
- **Model and thinking:** pick them from the model line, or say "switch to Opus", "think harder", "go fast", "go deep".
- **Mission Control** (<kbd>⌥ ⌘ L</kbd>): each agent's whole stream side by side, with tool calls, diffs, thinking, timings and cost, a line to type in, and Allow/Deny on approvals.
- **Show, don't say:** links and paths appear as chips on screen and are never read aloud.
- **Light or dark, and accessible:** Lair follows your Mac's appearance, with Liquid Glass controls on macOS 26, and respects Reduce Motion, Reduce Transparency, Increase Contrast and VoiceOver.

## Agents

Lair talks to agents over the [Agent Client Protocol](https://agentclientprotocol.com) (ACP), one process per call. Pick a preset in Settings, or give the command of any other ACP agent.

| Preset | Runs | Needs |
|---|---|---|
| Claude | `npx @agentclientprotocol/claude-agent-acp` | [Node.js](https://nodejs.org), Claude Code signed in |
| Codex | `npx @agentclientprotocol/codex-acp` | [Node.js](https://nodejs.org), Codex signed in |
| Copilot | `copilot --acp` | [GitHub Copilot CLI](https://github.com/github/copilot-cli) |
| opencode | `opencode acp` | [opencode](https://opencode.ai) |
| omp | `omp acp` | [omp](https://github.com/can1357/oh-my-pi) |
| Hermes on this Mac | `hermes acp` | [Hermes Agent](https://github.com/NousResearch/hermes-agent) |
| Hermes (remote) | Hermes' OpenAI-compatible API server | Its address and API key |

## Requirements

- macOS 15 or later on Apple Silicon
- Swift 6.4 (Xcode 27), only to build it yourself

The first launch downloads the speech models (Parakeet, Kokoro) through [FluidAudio](https://github.com/FluidInference/FluidAudio).

## Install

Download `Lair-vX.Y.Z.dmg` from [Releases](https://github.com/areguig/lair/releases) and drag Lair to Applications. It's signed with a Developer ID and notarized by Apple, so it opens like any other app.

From 0.2.1 on, Lair updates itself: when a new version is out, an **Update** button shows in the panel.

## Build

```sh
scripts/build-app.sh      # builds and installs ~/Applications/Lair.app
scripts/make-dmg.sh       # or wraps it in .build/Lair.dmg
open ~/Applications/Lair.app
```

The script signs the app with your Developer ID or Apple Development certificate if you have one, so the microphone permission survives rebuilds; `LAIR_SIGN_IDENTITY` picks another. With notary credentials saved by `xcrun notarytool store-credentials <profile>`, `LAIR_NOTARY_PROFILE=<profile> scripts/make-dmg.sh` also notarizes the disk image.

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
