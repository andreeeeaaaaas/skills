# demo-video

Use `/demo-video` to turn a script into a demo video of an app you're building.

Type or dictate what happens and when, such as "0:03 hover the Django row, 0:04 click its ×". Your agent compiles that into a timed plan, drives the real app while recording (real pointer, clicks, typing, and app state through a small demo hook), checks the take, and hands back the files.

Works with macOS apps and iOS Simulator apps.

## Setup

Follow the [installation instructions](../../README.md#install). Then:

- Xcode, for the Swift tool (it builds itself on first use) and the iOS Simulator.
- In System Settings > Privacy & Security, give the terminal app your agent runs in **Screen & System Audio Recording** and **Accessibility**.
- Optional: `ffmpeg` (`brew install ffmpeg`) for `.gif` and `.webm`, and Python 3 with PyYAML for YAML plans.

## Use

Ask your AI:

- **“/demo-video `<script>`”** Record the script. Timestamps are optional.
- **“Make a demo video of the onboarding flow”** Your agent drafts the script with you first.

During a take the pointer and keyboard are driven for you, so don't touch them.

## Output

- `.mov`: transparent background with window shadows. Safari, Keynote, Final Cut.
- `.webm`: transparent, for Chrome and Firefox.
- `.mp4`: on a solid background. Plays everywhere.
- `.gif`: for READMEs.
- `.vtt`: captions, unless they're burned in.
- `.take.json`: when each step happened and whether it passed.

## Not yet

Android, physical devices and web pages.
