# Plan format

A plan is YAML (needs `python3` with PyYAML) or JSON. Paths are relative to the plan file.

## macOS example

```yaml
name: kill-flow                      # default: file name; output goes to out/<name>
platform: macos
app:
  build: [swift, build]              # optional, run in cwd before launching
  launch: [.build/debug/MyApp, --demo]
  cwd: ..                            # default: the plan's folder
  env: { MY_FLAG: "1" }              # DEMO=1 is always set
output:
  formats: [mov, mp4, gif, webm]     # default mov, mp4 (iOS: mp4)
  captions: burn                     # vtt (default) | burn | both | none
  background: ececec                 # flatten colour for mp4/gif
  padding: 40                        # points around the windows
pointer:
  travel: 0.55                       # seconds to glide to each target
  start: [300, 200]                  # where it waits, from the window's top-left
  tooltips: false                    # hide help tags (default); true shows them after 0.5 s, or seconds
steps:
  - { at: 0, state: add sample-data }
  - { at: 2.5, hover: "Django backoffice", caption: Hover a row to stop it }
  - { at: "0:03.6", click: "Stop DJANGO", note: click its × }
  - { at: 3.8, expect: closing, within: 1 }
  - { at: 8.2, click: { label: Force quit } }
  - { at: 16, end: true }
```

## iOS Simulator example

```yaml
name: onboarding
platform: ios
app:
  bundleId: com.example.MyApp
  install: ../build/Build/Products/Debug-iphonesimulator/MyApp.app   # optional
  device: iPhone 17 Pro              # name or UDID; default booted, else newest iPhone Pro
  args: [-demo]
  urlScheme: myapp                   # state steps open myapp://demo?cmd=<command>
  appearance: light                  # or dark
  cleanStatusBar: true               # 9:41, full battery (default)
output:
  formats: [mp4, gif]
  captions: burn
  touches: true                      # draw taps (default on iOS)
steps:
  - { at: 1, tap: Get Started, caption: One tap to start }
  - { at: 2.5, tap: { id: email-field } }
  - { at: 3, type: "sam@example.com" }
  - { at: 4.5, swipe: { direction: up } }
  - { at: 6, state: "notification arrives" }
  - { at: 9, end: true }
```

Build an iOS app for the simulator with `xcodebuild -scheme <Scheme> -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build`, then point `install` at the `.app`.

## Steps

Every step has `at`: seconds from the start of the recording (`3`, `3.5`, `"0:03"`, `"1:02.5"`). Steps at the same time run in the order written. Each step has one action:

| Action | Value | Notes |
|---|---|---|
| `state` | command string | Sent to the app's demo hook (stdin line on macOS, deep link on iOS). |
| `click`, `doubleClick`, `rightClick` | target | Glides there, lands at `at`. |
| `tap` | target | Same as click; use on iOS for readability. |
| `hover` | target | Glides there and stays. |
| `drag` | `{ from: target, to: target }` | Presses at `at`, moves over `travel` (min 0.35 s). |
| `swipe` | `{ on: target?, direction: up/down/left/right, distance: 300 }` | Finger direction. Starts at the middle by default. Distance is in points on the Mac screen; the device window is usually shown smaller than life, so 250 moves further on the device. |
| `scroll` | `{ on: target?, lines: 5 }` | Positive moves down the page. |
| `type` | text | Typed at a natural pace into the focused field. `\n` presses Return. |
| `key` | combo | `cmd+k`, `cmd+shift+p`, `escape`, `return`, `tab`, `space`, `left`, `cmd+,`, `f5`. |
| `expect` | target | Passes once it's on screen, within `within` seconds (default 2). |
| `expectGone` | target | Passes once it's gone. |
| `end` | `true` | Recording stops here. Default: last step + 1.5 s. |

Any step can also carry:

- `caption`: shown from `at` until the next caption, `captionFor` seconds, or 3.5 s. A step can be caption-only.
- `within`: seconds to wait for a target to appear (default 2).
- `travel`: glide time for this step only.
- `note`: the script line it came from.

## Targets

A bare string matches an element's label, title, value or identifier: exact matches first, then partial matches, smallest element first. Or use a map:

```yaml
click: { label: "Stop DJANGO" }      # accessibility label or title
click: { id: save-button }           # accessibility identifier, exact
click: { text: "backoffice", role: button, index: 1 }   # second matching button
click: { label: Row, offset: [120, 0] }                 # 120 pt right of its centre
click: { point: [40, 12] }           # from the window's (iOS: screen's) top-left, last resort
```

`role` is the accessibility role without the `AX` prefix (`Button`, `StaticText`, `TextField`, `Row`, `Window`). Use `demo-video ax --app <name> --find <text>` to see what a target matches.

## Tooltips

macOS help tags are hidden by default, so a resting pointer doesn't pop one up by chance. `pointer.tooltips: true` (or a delay in seconds) shows them; give the hover step at least that long plus 0.3 s before the next move. The runner passes `-NSInitialToolTipDelay` after `app.launch`, so the launch command must hand extra arguments to the app. Tooltips are separate windows, so one outside the app's window widens the crop.

## Command line

`--formats mp4,gif` and `--tooltips on|off|<seconds>` override `output.formats` and `pointer.tooltips` for one take.

## Take log

`<out>.take.json` lists each step's planned time, when it started and landed, whether it passed, and why not. Times are seconds from the recording's first frame.
