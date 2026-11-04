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

The command is `rimlight`. Call it as `rimlight` below.

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
`build.md` first and follow its loop.

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

## Designing icons

What we are after: icons a real artist could have made, each with an idea
behind it that fits in one sentence, each usable as it is. People install an
app for its icon and keep it in the Dock because they like looking at it.
That is the bar. A render costs a minute, or money on an API key; a weak
idea costs a round.

### Before the first render

1. Read the project: the README or brief, what the app does in one line, the
   platforms, the brand colours, any icon assets. Decide for yourself what
   the app is about. A new set starts fresh. Leave the earlier sets, and any
   notes you kept about them, unread unless the user asks you to build on
   one; someone who wants more of a set keeps chatting in that set.
2. Brainstorm with the user before spending the batch. Bring four to six
   territories, each a different idea of what the icon could be, named for
   this product ("Tempo as a pocket device", "the notepad as a landscape"),
   with two or three concepts in a line each. Then ask what you need to
   know, in one message: a seed idea they have been carrying, icons they
   love and what they love about them, anything they never want to see, and
   which territories pull. Press on vague answers; "something premium" is
   not a direction, "like the Raycast keycap, lit from inside" is. Use
   `AskUserQuestion` for the pick when it is available and plain text for
   the open questions. Skip this when the user already gave a direction, and
   send a prompt they wrote as written.
3. Write the round: a first exploration is 16 to 24 concepts in 3 to 5
   families, a follow-up is smaller. Each concept gets a title, the idea in a
   line you could defend, why it is this app and no other, and a full
   prompt. A seed idea from the user gets explored seriously, with full
   freedom, in several readings. If you cannot say in a line why a concept
   is this app's icon, drop it.
4. Write the rendering standard once per set, from the style section that
   follows, and reuse it in every prompt so the set reads as one hand. It
   comes from the style every time, on a follow-up round too; never paste
   one from an earlier render's prompt.
   One brand colour anchors the set if the project has one; every other
   colour comes from the concept's own materials, and every concept gets its
   own colourway. Say each colour exactly, matte unless stated.
5. Name the set, render one concept, look at it (Read its `icon.png`). If
   the look is off, fix the standard before the rest. Then render the others
   in parallel and look at every one as it lands; a contact sheet is the
   honest view of a batch.

### After a round

Wrap up with your own read, so the user has something to argue with: where
the heat is, which three you would look at first and why, which ones miss
and why. The user then picks, comments and cuts; the next round is built
from that, and only that. When a round misses, ask how before rendering
another: two pointed questions beat forty guesses. Keep a short list of what
the user has said they like and never want, and read it before every round.

Refinement is the opposite of exploration: one icon, a locked base, one axis
per round (layout, then material, then colour), eight to twelve renders, each
an edit of the base rather than a fresh render, so the icon converges
instead of drifting.

### What to avoid

The obvious things, and only these:

- The first idea anyone has for this category. A gear for a build tool, a
  rocket for a launcher, a calculator for a calculator. Take the second or
  third idea, the one only this app could own.
- Words and digits, unless the word or the number is the idea.
- Screenshots of the app's UI.
- A frame, bevel or lit rim added around the tile's edge, or an inner panel
  whose only job is to frame the subject. The bright rims on real iOS 26
  icons are the system's glass edge, not artwork. An object that is the
  tile keeps its own edge, rolled or bevelled as the real thing is; a card
  or box that is the subject is not a panel.

In the original rounds, a coherent material and light across a set made it
read as a studio's work rather than a search result.

## Picking a style

Each style below is one file in `styles`. Before the
brainstorm, decide which styles this app could wear, read each of those
files whole, and build the territories from them. Nothing gets rendered
until the style file behind it has been read in this chat. A first
exploration takes two or three styles, one per family, named in the
family's title. A refinement, or a round built on an icon the user picked,
keeps that icon's style: the same file, its standard written out again from
the file, never copied from the prompt of an earlier render. When the user
names a look, follow it. When they don't, choose by what the app is, say in
one line which styles you chose and why, and move on. The style's rendering
standard goes into every prompt of its family, and its Never list is read
before every round.

- `soft-3d-object.md`: one physical thing with volume in a matte or satin
  material, studio lit, on a field or as the tile. For an app whose idea is
  a thing you could hold.
- `glass-and-chrome.md`: a mark or form in glass, chrome, foil, pearl or
  inner light, drawn by what shows through, reflects or glows. For AI
  tools, wallets, photo and wallpaper apps, anything about clarity or
  light.
- `lettermark-and-wordmark.md`: the name or its initial is the whole icon,
  in type drawn for the brand. For short, strong names with a twist to
  give the letter.
- `mono-mark.md`: one symbol drawn as a logo on a quiet ground, black on
  white or white on near-black. For an app that does one thing that can be
  drawn as a sign.
- `mascot.md`: a character or a face, cropped close. For apps that keep the
  user company: habits, health, journaling, study, pets, food, games.
- `hardware-and-skeuomorph.md`: a real device in faithful materials, its
  face as the tile. For cameras, players, radios, clocks, instruments,
  notebooks, anything with a physical ancestor.
- `system-glyph.md`: Apple's first-party idiom, a UI object with a gentle
  gradient, a top highlight stroke and a tinted contact shadow. For
  calendars, lists, notes, files, finance, messaging.
- `scene-and-collage.md`: a picture rather than a symbol: an illustrated
  place, a vintage print, a sticker collage, a paper object. For apps about
  a time, a place or a held artefact.
