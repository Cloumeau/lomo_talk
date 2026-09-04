# Lomo Talk

A macOS voice wrapper for the locally installed Codex and Claude Code CLIs.

Say what you want to do, let the selected coding agent work in your current directory, read its response in the terminal, and hear Lomo speak it aloud.

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools (`swift`)
- An installed and authenticated `codex` and/or `claude` CLI

## Install

With Homebrew:

```sh
brew tap Cloumeau/tap
brew install --cask Cloumeau/tap/lomo-talk
```

Or build it locally:

```sh
./scripts/install.sh
```

If prompted, add `~/.local/bin` to `PATH` as the installer explains. Then run this from the project directory you want the agent to work in:

```sh
lomo_talk
```

On first launch, macOS asks for Microphone and Speech Recognition access. Lomo stops listening after about 1.4 seconds of silence.

Lomo automatically prefers an installed premium or enhanced English voice. Download additional voices under **System Settings → Accessibility → Spoken Content → System Voice**. To select a particular installed voice by name:

```sh
LOMO_VOICE=Samantha lomo_talk
```

If installation reports that the macOS SDK cannot be resolved, update or reinstall Xcode Command Line Tools and rerun the installer. You can inspect the active tools with `xcode-select -p`.

## Voice commands

- “Switch assistant”
- “Switch to Claude” / “Switch to Codex”
- “Repeat that”
- “Goodbye”

## Safety and behavior

Lomo invokes the existing CLIs in their supported print/exec modes and resumes a private session for the rest of the conversation. It does not bypass either agent's permission system. Because voice mode cannot display and answer interactive approval prompts, operations that require an approval may be declined by the underlying CLI. Run Codex or Claude directly when you need fine-grained interactive approvals.

Speech transcription uses Apple's on-device/system Speech framework; no separate speech API key is configured by this project. Availability and on-device processing can vary by macOS language and system settings.
