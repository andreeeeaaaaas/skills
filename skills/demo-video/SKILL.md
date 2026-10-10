---
name: demo-video
description: Record demo videos of macOS apps and iOS Simulator apps from a script the user types or dictates, with timestamps ("0:03 click Save"). Compiles the script into a timed plan, drives the real app (real pointer, clicks, typing, app state hooks) while recording, checks the take, and exports transparent .mov/.webm, .mp4, .gif and captions. Use when the user asks for a demo video, screen recording, product clip, portfolio or README animation, or GIF of an app they're building.
---

# Demo video

Turn the user's script into a recording of the real app. The user describes what happens and when; you compile that into a plan, run it, check the result, and hand back files.

The tool is `scripts/demo-video` in this skill's folder (it builds itself on first run, ~10 s). Subcommands:

| Command | Use |
|---|---|
| `demo-video run <plan.yaml> [--formats mp4,gif] [--tooltips on\|off\|<s>] [--dry-run]` | Launch the app, perform timed steps while recording, export, write `<out>.take.json`. Flags override the plan. Exit 2 means an expectation failed. |
| `demo-video ax --app <name> [--find <text>]` | Print the app's accessibility tree (role, label, title, value, id, frame), to pick targets. |
| `demo-video frames <video> --at 0,2.5,5 --out sheet.png` | Contact sheet of frames with timestamps, to check a take. |
| `demo-video record --out <base> -- <command>` | Plain recording of a macOS app's windows, no steps (also `--pid`, `--app`, `--duration`). |

Plan format: [references/plan-format.md](references/plan-format.md). App state hooks per platform: [references/app-hooks.md](references/app-hooks.md).

## Platforms

- **macOS apps**: records only the app's windows, with transparency and window shadows, cropped to where the windows went. The real pointer moves and clicks, so hover effects work. The app is brought to the front first; plans without pointer steps move the pointer off its windows. Tooltips are off unless the plan sets `pointer.tooltips`. Needs Screen Recording and Accessibility permission for the terminal app running the agent (System Settings > Privacy & Security). The tool says which is missing.
- **iOS Simulator**: boots the simulator (creating the newest iPhone Pro if none exists), cleans the status bar (9:41, full battery), launches the app, waits until it has drawn, and records the device screen at native resolution with `simctl io recordVideo`. Taps click into the device window of Simulator.app (Xcode 26 and earlier) or Device Hub (Xcode 27), which both expose the iOS app's accessibility tree, so targets work the same as on macOS. Taps are drawn as circles afterwards. Needs Xcode and the same two permissions; the device window must stay visible and uncovered during the take. Plans with only `state` and caption steps don't need the window at all.
- **Not yet**: Android (planned: `adb screenrecord` + `adb shell input` + UI Automator), physical devices, web pages. Say so rather than improvising.

## Workflow

### 1. Get the script

Take the user's words as they come: typed or dictated, with or without timestamps. Example:

```
0:00 Board with three servers running
0:03 Hover the Django row, click its ×     caption: Stop a server from the board
0:05 Shows CLOSING, then DELAYED
0:09 Click Force quit
0:15 End
```

If timestamps are missing, pace it yourself: about 1.2 s per action, at least 2.5 s for each caption to be read, 1 s still at the start and 1.5 s at the end. Ask only about things that change the recording (which platform, which device, what the data should look like), not about wording.

### 2. Read the project

Find how to build and launch the app, its platform, and whether it already has a demo mode or plans (`demos/*.demo.yaml`, a `--demo` flag, a `demo` URL host). Reuse what exists.

### 3. Add an app hook if the script needs state the UI can't produce

Things like "a server starts", "a message arrives", "the sync fails", or any fake data. Add a small demo mode once per project, following [references/app-hooks.md](references/app-hooks.md): stdin line commands on macOS, a `<scheme>://demo?cmd=` deep link on iOS. Demo mode uses fake data and its own defaults/storage so it never touches the user's real data. Steps the user can do with the pointer or keyboard should be real UI steps, not hooks: they look right and test the real thing.

### 4. Find targets

Launch the app (or its demo mode) and run `demo-video ax --app "<App Name>"`, or `--find "<text>"` to check one target. Target by accessibility label, title or visible text first, `id` (accessibility identifier) when text is ambiguous or changes, and `point` only as a last resort. If an important control has no label, add an accessibility label or identifier to the app: it helps VoiceOver users too.

### 5. Write the plan

Save it as `demos/<name>.demo.yaml` in the project (commit plans; outputs go to `demos/out/`, which should be gitignored). Map the script:

| Script says | Plan step |
|---|---|
| "click / press / choose X" | `click: X` (`tap:` on iOS) |
| "hover X", "point at X" | `hover: X` |
| "type hello" | `type: hello` |
| "press ⌘K", "hit Escape" | `key: cmd+k`, `key: escape` |
| "drag X to Y", "swipe up" | `drag: {from, to}`, `swipe: {direction: up}` |
| "X happens" (not done by the user) | `state: <hook command>` |
| "shows X", "X appears", "X disappears" | `expect: X`, `expectGone: X` |
| quoted narration, "caption: …" | `caption:` on the step at that time |
| "end", last line | `end: true` |

`at` is when the action lands: the pointer starts gliding `travel` seconds earlier (0.55 s by default) so the click happens on the beat. Put `note:` with the original script line on each step; it shows in the take log.

Show the user the compiled timeline as a short table (time, action, target, caption) and carry on unless they want changes.

### 6. Dry run, then take

Before the first take in a session, tell the user the pointer and keyboard will be taken over for the length of the plan, so they shouldn't touch them. Run `demo-video run demos/<name>.demo.yaml --dry-run` to check every target resolves (no recording), then the real take without `--dry-run`.

### 7. Check the take

- Exit code 2 or ✗ lines: read `<out>.take.json`. Usual causes: the target wasn't on screen yet (raise `within`, move the step later), the label differs (check with `ax --find`), or an animation hadn't finished.
- Compare each step's `landed` with its `at`. Pointer steps normally land within a few milliseconds. A late one means its target appeared late (a push or sheet animation still running): move that step later, or the step before it earlier.
- Expectations run alongside the timeline and never delay later steps, so a caption that should coincide with a result belongs at the time the take log says the result appeared.
- Run `demo-video frames <out>.mp4 --at <each step's time + 0.3>` and read the sheet. Compare each frame with the script: right state, captions readable, nothing cut off. For transparency, check the `.mov` the same way (it renders on a checkerboard).
- Retake after fixing. Don't hand over a take that fails its expectations or doesn't match the script.

### 8. Hand over

List the files and what each is for:

- `.mov`: HEVC with alpha. Safari, Keynote, Final Cut, iMessage.
- `.webm`: VP9 with alpha (add `webm` to formats). Chrome and Firefox.
- `.mp4`: flattened on the background colour. Plays everywhere, smallest.
- `.gif`: for READMEs and places without video.
- `.vtt`: captions as a separate track, when captions aren't burned in.

For a web page with transparency in every browser:

```html
<video autoplay loop muted playsinline>
  <source src="demo.mov" type='video/mp4; codecs="hvc1"'>
  <source src="demo.webm" type="video/webm">
</video>
```
