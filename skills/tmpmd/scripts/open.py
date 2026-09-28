#!/usr/bin/env python3
"""Open a Markdown file in a new Obsidian tab, or focus the tab already showing it.

Uses the Obsidian CLI (Obsidian 1.12+, enabled in Settings > General). Falls back to
the system's default app when the CLI is missing, off, or fails.

Usage: open.py <file>
"""
import json
import os
import shutil
import subprocess
import sys

# Obsidian stores files outside a vault as "file:<real path>".
JS = """const f=%s;let l;app.workspace.iterateAllLeaves(x=>{if(x.getViewState().state?.file===f)l=x});
(l?Promise.resolve():(l=app.workspace.getLeaf('tab')).setViewState({type:'markdown',state:{file:f,mode:'preview'}}))
.then(()=>app.workspace.setActiveLeaf(l,{focus:true}));'ok'"""


def in_obsidian(path):
    if not shutil.which("obsidian"):
        return False
    code = JS % json.dumps("file:" + os.path.realpath(path))
    try:
        out = subprocess.run(["obsidian", "eval", "code=" + code], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.TimeoutExpired):
        return False
    if "=> ok" not in out:
        return False
    subprocess.run(["open", "-a", "Obsidian"], check=False)  # bring the window forward
    return True


def open_file(path):
    if sys.platform == "darwin" and in_obsidian(path):
        return
    subprocess.run(["open" if sys.platform == "darwin" else "xdg-open", path], check=False)


if __name__ == "__main__":
    open_file(sys.argv[1])
