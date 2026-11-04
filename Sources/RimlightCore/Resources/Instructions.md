---
name: rimlight
description: Design and refine app icons for Apple platforms with Rimlight. Use when the user asks for an app icon, icon concepts, a set of icon directions, variations or edits of an icon, or says "use Rimlight".
---

# Rimlight

Rimlight keeps an app's icon work in `<project>/.rimlight/` as sets of icons.
A set is one exploration. An icon is one render, `icon.png`, plus `icon.json`
with its title and prompt. The Rimlight app shows every set as a grid and gives
each set and each icon its own chat. You do the thinking, the prompt writing
and the generating; the `rimlight` command does the rendering and the
bookkeeping. You never write files under `.rimlight/` yourself.

The command is `{{RIMLIGHT_CLI}}`. Call it as `rimlight` below.

## The command

```
rimlight status [--json]                       sets and icons of the project at cwd (or --project DIR)
rimlight init [--project DIR]                  create .rimlight/ with an empty first set
rimlight set create [--title "..."]            a new empty set; prints its id
rimlight set rename <set-id> --title "..."     name a set
rimlight generate --set <set-id> --slug <slug> --title "..." --prompt-file -
                  [--ref IMAGE]... [--parent <set-id>/<slug>] [--count N] [--force]
rimlight fix <set-id>/<slug>                   the transparency fix of one opaque icon, in place
rimlight fix --all --set <set-id>              the same for every opaque icon of a set
rimlight build <set-id>/<slug> [--direction NAME] [--stage STAGE] [--plan-file -] [--redraw NAME]
                                               a picked render into an Icon Composer .icon; read build.md first
```

`generate` renders through the image model picked in Rimlight's settings:
Codex on the user's ChatGPT plan, or OpenAI or OpenRouter on the user's own
API key. `rimlight image` shows which. It writes the icon and prints a
`SAVED <path> 1254x1254 alpha=yes|no` line per image, whatever the model.
What it does for you:

- The tile. A fresh render (no `--parent`) gets Apple's icon shape as one
  more reference image after your refs, with a line added to the end of your
  prompt saying which image it is. The render is then fitted to that shape.
  So never state the tile's size, corner shape or position in a prompt, and
  a fresh render takes at most four `--ref` images.
- Transparency. Every render is checked by its pixels. One that came back
  with a painted backdrop gets up to three fix renders, then, if it is still
  opaque, Rimlight cuts the backdrop out on the Mac. A model that can't draw
  transparency gets only the cutout. A `CUTOUT` line means the cutout was
  used: tell the user in the chat, in one line, what it says (after failed
  fix renders, that the model tried three times and Rimlight cut the
  background out itself). A `SAVED` line with `alpha=no` means nothing
  worked: say so in one line and offer `rimlight fix <set>/<slug>`.
- Limits. Exit status 3 and a `LIMIT` line mean the image model refuses
  every render until something changes: a plan's image limit, or an account
  out of credit. The command stops at once and keeps what it has. Stop,
  give the user the line as it is, and start no render and no `rimlight fix`
  before the time it names, or, when it names none, until the user says it
  is sorted: each would fail.
- Cost. On an API key every image costs the user money, fix attempts
  included. Render what the request needs and no more.

Rules of the command:

- Pass the prompt on stdin with a quoted heredoc:

  ```
  rimlight generate --set set-001 --slug olive-device --title "Olive device" --prompt-file - <<'PROMPT'
  ...
  PROMPT
  ```

- One `generate` per icon. On Codex a render takes about a minute, up to
  about 4 minutes with fixes; an API model is usually faster. Run them in
  the background and in parallel (`run_in_background`, Bash timeout
  600000). Each tells you when it finishes. Never watch one with `tail -f`,
  a Monitor or a loop of your own that sleeps and checks. To see what is
  still running, run `rimlight status` once. `--count N` makes N variants
  of one prompt in one call, named `<slug>-1` to `<slug>-N`.
- A render keeps running after your turn ends; the app shows a dashed cell
  until it lands. Do not re-run one because the user asks if it is still
  going; check `rimlight status`.
- `--slug` is `[a-z0-9-]`, at most 64 characters, unique in the set,
  readable in Finder. `--force` only replaces a render that failed.
- `--ref` passes images to the image model in order: the first is Image 1,
  the second Image 2, and so on, at most five. Say in the prompt what each
  image is for.
- `--parent` records which icon this one was made from. Set it on every edit
  and every variation.

## Where things go

- In the Rimlight app, the system prompt of each chat names the project root,
  the set you are in and, in an icon's chat, the icon. Write new icons into
  that set. Never create a set from the app's chat; the user creates sets.
- In a terminal, start with `rimlight status`. A new direction goes in a new
  set (`rimlight set create`). If there is no `.rimlight/`, run
  `rimlight init`.
- Name a set before its first render (`rimlight set rename`), two to four
  words that say what the exploration is.

## Prompts

The image model sees only your prompt text, so write every prompt in full.
End each fresh render's prompt with the background it needs:

```
Transparent background: a real alpha channel outside the icon tile, no
backdrop, no checkerboard, no cast shadow. Output a PNG with transparency.
```

An edit or a variation passes the icon being changed as `--ref` (Image 1),
sets `--parent` to it, and says what to change and what to keep. The
image model holds what you name and drifts on what you leave out. For a
material or palette from another icon, pass that icon as Image 2 and say
"Image 2 is the material and colour reference: take its body material,
finish and exact palette; do not copy its subject."

If the user wrote the image prompt themselves, send it as written; add only
the background lines above if it says nothing about the background.

## The target

These renders are concepts. The final icon ships as a layered Icon Composer
package: a 1024 px square the system masks to its rounded shape, with Dark,
Clear and Tinted appearances derived from luminance. Clear and Tinted strip
colour and keep only light against dark, so one hero element that reads
light against a mid or dark body will survive. When the user picks a render
to ship, build it into an Icon Composer package with `rimlight build`. Read
`{{RIMLIGHT_BUILD}}` first and follow its loop.

## Referenced icons

In the Rimlight app the user can drag icons into the message field. The
message then carries a block like this, before the user's text:

```
Referenced icons:
- "Counter with + × a" (set-001/counter-plus-times-a) /abs/path/.rimlight/sets/set-001/counter-plus-times-a/icon.png
```

These are the icons the user pointed at for this message: to compare
against, to borrow from, or to make variations of. Pass their files with
`--ref` and say what each image is for. In an icon's chat the icon being
changed is still the chat's own icon unless the message says otherwise.
