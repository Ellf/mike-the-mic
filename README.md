# Mike the Mic

![Mike the Mic on stage, mid-joke](assets/mike.png)

Mike is a small macOS app that gives [Claude Code](https://claude.com/claude-code) a face and a voice. When Claude finishes a reply, Mike reads it out loud, and his mouth moves along with the words on an animated 64×32 LED-style display.

The idea: you talk to Claude through a microphone, and Claude talks back through... a microphone. Mike was designed with my son, who also came up with several of the faces.

## Faces

| Key | Face |
| --- | --- |
| ⌘1 | **Mike**: a googly-eyed microphone doing stand-up on a comedy stage |
| ⌘2 | Classic Bot |
| ⌘3 | Kawaii |
| ⌘4 | Visor |
| ⌘5 | Jack-o'-lantern |
| ⌘6 | Psychedelic (rainbow swirl eyes) |
| ⌘7 | Creepy (scary, but teen-friendly) |
| ⌘8 | Windows XP (watch out for the blue screen) |
| ⌘9 | Crayon Drawing |
| ⌘0 | Friendly Alien |

The faces blink and pull random expressions while they talk. Press ⌘F to make one pull a face on demand.

## Requirements

- macOS 14 or later on Apple silicon
- Xcode Command Line Tools (`xcode-select --install`)

## Build and run

```sh
git clone https://github.com/Ellf/mike-the-mic.git
cd mike-the-mic
./build.sh
open build/Mike.app
```

The app is signed ad hoc, so it only runs on the Mac that built it. There's no notarised download.

## Connect it to Claude Code

Add a Stop hook to `~/.claude/settings.json`, using the full path to your clone:

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "/path/to/mike-the-mic/scripts/claude-stop-hook.sh", "timeout": 5 } ] }
    ]
  }
}
```

When Claude finishes a reply, the hook sends it to Mike, and Mike reads it out. Code blocks and Markdown symbols are stripped first. If Mike isn't running, the hook does nothing.

To test without Claude:

```sh
curl -X POST --data-binary "Hello there" localhost:5151/say
curl -X POST localhost:5151/stop
```

The server only listens on localhost (port 5151).

## Using Mike

| Shortcut | What it does |
| --- | --- |
| ⌘J | Tell a joke (a random one from [icanhazdadjoke.com](https://icanhazdadjoke.com), or a built-in one when offline) |
| Esc or ⌘. | Stop talking |
| ⌘F | Pull a random face |
| ⌘T | Stay on top of other windows |
| ⇧⌘M | Mute |
| ⌘N | Open another face window |

- **Voices:** pick any installed macOS voice from the Voice menu, or right-click a face and choose Voice. More voices can be downloaded in System Settings → Accessibility → Spoken Content.
- **Several windows:** open one face per monitor with ⌘N. Each window remembers its own face and position. They all share one voice.
- **Right-click** any face for the same menu.

## Settings

The voice and other settings are saved automatically. The lip sync can be fine-tuned from Terminal:

```sh
defaults write io.purplehippo.talkingface lipSyncOffset -float 0.05   # mouth earlier (+) or later (-)
```

## How it works

- `Sources/Face.swift` draws every face onto a 64×32 grid of "LEDs", using SwiftUI's `Canvas`.
- `Sources/Speaker.swift` renders speech with the built-in `say` command, and `LipSync.swift` reads the audio levels to drive the mouth.
- `Sources/HookServer.swift` is a tiny HTTP server that receives the Claude Code hook.
- `concepts/face-styles.html` is the browser sketch the first faces were designed in.

## License

[MIT](LICENSE)
