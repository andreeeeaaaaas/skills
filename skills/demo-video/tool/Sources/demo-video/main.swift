import Foundation

// demo-video: records demos of macOS apps and iOS Simulator apps, driven by a timed plan.

let usage = """
Usage: demo-video <command> [options]

Commands:
  run <plan>     perform a plan's timed steps while recording, then export the take
  record         record one macOS app's windows (launch or attach), no scripted steps
  ax             print an app's accessibility tree, to find targets for a plan
  frames <video> contact sheet of frames, to check a take

Run `demo-video <command> --help` for options.
"""

var arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.isEmpty ? "help" : arguments.removeFirst()
switch command {
case "run": await runCommand(arguments)
case "record": await recordCommand(arguments)
case "ax": axCommand(arguments)
case "frames": await framesCommand(arguments)
case "help", "-h", "--help": print(usage)
default: fail("unknown command \(command)\n\n\(usage)")
}
exit(0)
