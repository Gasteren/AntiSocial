# AntiSocial

> Minimal human interaction, maximum efficiency.

A tiny WoW addon that handles the social pleasantries you'd rather not type yourself. Fires randomized chat messages on a small set of game events with a 1-8 second delay so it doesn't read like a bot.

## Features

- **Event triggers** (each individually toggleable):
  - **Group join**, "hey all" / "hi :)" / "heya"
  - **Mythic+ complete**, context-aware (timed vs depleted) "gg" pool
  - **Group leave**, "ty for group" pool
  - **Group achievement**, "gz" pool, with rarity weighting for big achievements
  - **Group level-up**, "gz" pool
  - **Ready check** (off by default), auto-confirms after a short delay
- **Four mood profiles**: Introvert, Friendly, Goblin, Raider
- **Randomized 1-8s delay** so it doesn't look like clockwork automation
- **Per-player** so it never spams the same target twice

## Mood profiles

| Profile   | Vibe                | Example "hi"    | Example "gg"       |
|-----------|---------------------|-----------------|--------------------|
| Introvert | Bare minimum        | `hi`            | `gg`               |
| Friendly  | Warm, default       | `heya`, `hi :)` | `nice key`, `tyfp` |
| Goblin    | Chaotic key-pusher  | `pumpers?`      | `ez clap`          |
| Raider    | Terse, business     | `hi`            | `ggs`              |

## Slash commands

```
/as                 open settings
/as on | off | toggle
/as profile <name>  Introvert / Friendly / Goblin / Raider
/as test            preview what each trigger says
/as debug           toggle debug output
```

## Mood profiles

| Profile   | Vibe                             | Example "hi"   | Example "gg"     |
|-----------|----------------------------------|----------------|------------------|
| Introvert | Bare minimum                     | `hi`           | `gg`             |
| Friendly  | Warm, default                    | `heya`, `hi :)`| `nice key`, `tyfp` |
| Goblin    | Chaotic key-pusher               | `pumpers?`     | `ez clap`        |
| Raider    | Terse, business-like             | `hi`           | `ggs`            |

## What AntiSocial does NOT do (by design)

This addon **only** fires on discrete game events. It does **not** read other players' chat and reply to it. It does not auto-respond to whispers. It does not impersonate a person in conversation. Those features are explicitly out of scope to stay on the right side of Blizzard's automation rules.

Chat-reactive features (e.g. "someone said hi → say hi back") may arrive in a future version behind safety rails (per-session limit, group-members-only, audit log). They will never be on by default.
