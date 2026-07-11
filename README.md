# Elegant Paste-Image-to-CLI for macOS

Paste a clipboard image straight into your terminal and get back a real file path — automatically. Built for AI coding CLIs that can't accept raw image paste.

## The problem

Terminal-based AI coding agents — Claude Code, Kiro CLI, Codex CLI, and others — can *read* an image if you give them a file path, but they can't accept a raw pasted image. Terminals themselves don't help either: `Cmd+V` only understands text, so a screenshot on your clipboard does nothing when pasted.

The usual workaround: open Preview and save the screenshot, or run `pngpaste` manually, then type out the path by hand. Every time.

## What this does

Inside your terminal app (iTerm2 by default, configurable), pressing `Cmd+V`:

- **Clipboard has an image** → saves it to `/tmp/clipboard-<timestamp>-<uuid>.png` and types the file path directly into the terminal
- **Clipboard has text** → pastes normally, unaffected
- **Any other app is focused** → does nothing, native `Cmd+V` everywhere else

One keystroke. No manual save step, no typing paths by hand.

## Features

- Scoped to one app — doesn't touch paste behavior anywhere else
- No extra dependencies — pure Hammerspoon, no `pngpaste` needed
- Collision-safe filenames (timestamp + UUID)
- Guided permission setup — auto-opens System Settings to the Accessibility page on first run if needed
- Temp-only by design — files go to `/tmp`, which macOS clears on reboot. This is intentional: this tool is for quickly handing a screenshot to a CLI, not for archiving images. Use your normal screenshot-to-file workflow for anything you want to keep

## Install

Requires [Hammerspoon](https://www.hammerspoon.org/):

```bash
brew install --cask hammerspoon
```

Then:

```bash
git clone https://github.com/deltaguita/elegant-paste-image-to-cli.git
cd elegant-paste-image-to-cli
./install.sh
```

`install.sh` appends `clipboard-image-paste.lua` to your `~/.hammerspoon/init.lua` (backing up the existing file first), then restarts Hammerspoon. A system Accessibility permission dialog will appear on first run — check the box for Hammerspoon.

## Configuration

Defaults to `iTerm2`. To use a different terminal, or multiple terminals, edit this line in `~/.hammerspoon/init.lua`:

```lua
local TARGET_APPS = { "iTerm2" }  -- e.g. { "iTerm2", "Terminal", "Ghostty" }
```

(Run `hs.application.frontmostApplication():name()` in the Hammerspoon Console to find the right name for your terminal.)

Saved files default to `/tmp`. Change `TMP_DIR` to save elsewhere.

## Known limitations

- Pressing `Cmd+V` twice in quick succession for the *same* clipboard image can still create a duplicate file in rare edge cases (a 2-second debounce prevents most of this, but it's not a hard guarantee). Since files live in `/tmp`, any duplicates are harmless and get cleaned up automatically on the next reboot
- macOS + Hammerspoon only

## License / Credits

Core logic (`hs.pasteboard.readImage()` + `saveToFile()`) adapted from [Przemysław Kołodziejczyk's writeup](https://eshlox.net/clipboard-image-to-file-hammerspoon) (CC BY-SA 4.0).

This repo's code is MIT licensed.
