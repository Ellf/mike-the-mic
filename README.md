# Talking Face

A small macOS app that shows an animated 64×32 LED-style face and reads Claude Code replies out loud, with the mouth lip-synced to the voice.

Faces: Classic Bot, Kawaii, Visor, Jack-o'-lantern, Psychedelic, Creepy, Windows XP, Crayon Drawing (⌘1–⌘8). ⌘N opens another face window (e.g. one per monitor); each keeps its own face and position, and they all share one voice.

## Build & run

```sh
./build.sh
open "build/Talking Face.app"
```

## Hook it up to Claude Code

Add a Stop hook to `~/.claude/settings.json`:

```json
"hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "/path/to/talking-faces/scripts/claude-stop-hook.sh", "timeout": 5 } ] } ] }
```

Test without Claude: `curl -X POST --data-binary "Hello there" localhost:5151/say`

## Settings

```sh
defaults write io.purplehippo.talkingface voice -string "Kate (Enhanced)"
defaults write io.purplehippo.talkingface lipSyncOffset -float 0.05   # mouth earlier (+) / later (-)
```

Keys: ⌘F pull a random face · ⌘T stay on top · ⇧⌘M mute · Esc or ⌘. stop talking · ⌘J say a test line.
