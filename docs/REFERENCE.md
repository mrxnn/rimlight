# Rimlight reference

Rimlight designs Apple app icons with an AI image model. This is the full
reference. It covers how the `rimlight` command installs, how a render and
a build work inside, and every option. To start using Rimlight, read the
[README](../README.md) first.

Rimlight is two things. The first is a command, `rimlight`. The second is a
skill, a set of instructions that teaches an agent such as Claude Code or
Codex how to design an icon with it. The agent does the design work. It
talks with you, writes the prompts and looks at every result. `rimlight`
sends each prompt to the image model, fits the image to Apple's icon shape
and stores it in your project under `.rimlight/`. When you pick an icon,
`rimlight build` turns it into an Icon Composer `.icon` file with its own
Dark, Clear and Tinted looks.

You need macOS 26 and an image model. The Rimlight app is a separate, paid
Mac app for browsing and comparing your icons. The command works without
it.

## Install

There is no binary download of `rimlight` yet. You get it with the Rimlight
app, or you build it from source.

### With the Rimlight app

The app carries its own copy of `rimlight`. When no `rimlight` is
installed, the app installs its copy with `rimlight self-install`. At every
launch, the app compares its copy with the one it installed. When its own
copy is newer, it replaces the installed one. So an app update also
updates the command and the skill.

The app replaces only a copy it installed itself. If you have another
copy, the app shows an Update button and lets you decide. If you delete
the app, the command and the skill keep working.

### From source

You need Swift 6.2.

```sh
swift build -c release
.build/release/rimlight self-install
```

`self-install` does three things:

- It copies the binary and its resource bundle into
  `~/.local/share/rimlight/<version>/`. The bundle holds the skill text and
  the tile mask.
- It points `~/.local/bin/rimlight` at that copy.
- It installs the skill, as `rimlight install-skill` does. `--no-skill`
  skips this.

Claude Code's installer puts `claude` in `~/.local/bin`, so that folder is
usually on your `PATH` already. If it is not, `self-install` tells you.
`--prefix DIR` installs under another folder instead of `~/.local`.

To update, run `self-install` again from a newer build. It keeps the
previous version until the next update, so a render that is still running
keeps its files. `rimlight self-uninstall` removes this copy.

### An image model

Every render needs an image model. Codex is the default. Install it, then
sign in with a ChatGPT plan:

```sh
npm i -g @openai/codex
codex login
```

[Image models](#image-models) covers the other choices.

### Keep one copy

Keep one `rimlight` on your `PATH`. A shell runs the first one it finds. If
you have two, the second one never runs, and updating it changes nothing.

```sh
rimlight doctor
```

`rimlight doctor` lists every copy on your `PATH` and says which one runs.
It checks that the installed skill matches that copy, and it checks for
Icon Composer. For each problem, it prints the command that fixes it.

## The skill

`rimlight install-skill` writes the skill for your agents:

| Agent | Folder | When |
|---|---|---|
| Claude Code | `~/.claude/skills/rimlight/` | Always. OpenCode reads this folder too |
| Codex | `~/.codex/skills/rimlight/`, or `$CODEX_HOME/skills/rimlight/` when that is set | Only when the Codex home folder exists |

Each folder holds these files:

- `SKILL.md` is the instructions and the design process.
- `build.md` is the guide to `rimlight build`.
- `styles/` holds the eight style files.
- `.install.json` records which version wrote the skill, with which style
  and which command.

Codex's `SKILL.md` has one extra section at the end. The skill was written
for Claude Code, so this section says what to do instead in Codex. Run
`rimlight` outside the sandbox. Give renders a long timeout. Look at images
with `view_image`. Ask questions in plain text.

If `~/.codex/skills` is a link to `~/.claude/skills`, Codex gets no copy of
its own. Codex already reads Claude Code's skill there.

The options:

- `--harness claude` or `--harness codex` installs for that one agent.
- `--skills-dir DIR` installs into another folder. It moves Claude Code's
  folder, or Codex's when you also give `--harness codex`.
- `--style NAME` picks the style. [The styles](#the-styles) explains them.
  Without `--style`, the command keeps the style the skill had before.

The skill calls plain `rimlight` when the `rimlight` on your `PATH` is the
one that installed it. Otherwise it calls that binary by its full path.

The skill stays in step with the command. Say a newer `rimlight` runs a
project command, such as `rimlight status`, and an older one wrote the
skill. The newer one then rewrites the skill, keeps its style, and prints a
note. `self-install` rewrites it too.

## Use

Open a project in your agent and ask for an icon. The agent then does
this:

1. It reads the project.
2. It brings four to six territories. A territory is one idea of what the
   icon could be. It asks which ones you like.
3. It writes 16 to 24 prompts in three to five families.
4. It renders one to check the look. Then it renders the rest in parallel.
   A render takes about a minute on Codex.

You pick, comment and cut. To refine one icon, the agent locks it and
changes one thing per round. Each round is eight to twelve edits of that
icon.

These are the commands you might type yourself:

```sh
rimlight status        # the sets and icons of the project at or above this folder
rimlight init          # create .rimlight/ with an empty first set
rimlight set create    # a new empty set; prints its id
rimlight image         # the image model that renders, and where its key comes from
rimlight doctor        # which copy runs, and what is wrong
```

`rimlight help` lists every command. `rimlight generate --help` and
`rimlight build --help` explain those two in full.

## How a render works

The agent writes the whole prompt. `rimlight` sends it to the image model
as written, with the `--ref` images in order. The model sees nothing else.

- On Codex, `rimlight generate` runs one headless `codex exec` turn. That
  turn calls Codex's `image_gen` tool.
- On an image API, `rimlight` sends one JSON request. The `--ref` images go
  in it as data URLs.

Every result becomes a square PNG, 1254 px a side, with its alpha kept.
After that step, everything works the same for every model.

### The tile template

A fresh render is one without `--parent`. It gets one more reference image
at the end, Apple's icon shape drawn as a flat grey tile in a 1254 px
frame. The prompt then ends with this line. N is the template's place among
the images.

> Image N is the tile template: a flat grey silhouette of the icon tile's
> exact outline, corner curve, size and position in the frame. The icon's tile
> fills that silhouette exactly, edge to edge, with the same outline, corner
> curve, size and position. Do not copy the template's grey, do not draw its
> outline, and do not draw a smaller tile inside it. Everything outside the
> silhouette is fully transparent.

### The fit

`rimlight` fits every transparent render. It finds the tile the model drew.
It scales that tile to 1024 px and puts it in the middle of the 1254 px
frame. Then it uses Apple's exact mask, as Icon Composer renders it, for
the alpha. The fitted image is `icon.png`. The image from before the fit is
kept as `raw.png`.

### The transparency fix

`rimlight` judges a render by its pixels, not by its file format. A model
can paint a checkerboard into a file that has an alpha channel. When a
render comes back opaque, `rimlight` tries these steps in order. It stops
at the first one that gives a transparent image.

1. An edit of the render with the prompt below.
2. A fresh render of the same request.
3. An edit of that fresh render.
4. A free cutout on your Mac. It clears the painted background from the
   corners inward, or uses the subject mask of macOS's Vision framework. It
   keeps the result only if what is left has the shape of a tile.

> Edit Image 1. Remove the backdrop, the checkerboard and any cast shadow so
> that everything outside the icon tile is fully transparent: a real alpha
> channel, no painted background of any kind. Keep the icon tile itself and
> everything on it identical: its shape, size, position, materials, colours,
> lighting, camera angle, framing and the image size. Output a PNG with
> transparency.

Steps 1 to 3 each cost a render. `--fix-attempts N` changes how many
`generate` makes. The default is 3. A model that cannot draw transparency
skips them and gets only the cutout. `rimlight image --models` says which
models can.

When the cutout is used, `rimlight` prints a `CUTOUT` line, and the skill
has the agent tell you. When an edit or the cutout made the image, the
model's opaque render is kept as `original.png`. `rimlight fix` runs the
same steps on icons that are already stored.

### Limits

Sometimes the image model refuses every render. A ChatGPT plan may have hit
its daily image limit, or an API account may be out of credit. Then
`rimlight` stops at once and spends no fix attempts. It keeps what it has
and prints one line:

```
LIMIT Codex's image limit on your ChatGPT Plus plan is reached. It resets at 21:04, in 7 h 8 min. Renders fail until then.
LIMIT OpenRouter refused the render: Insufficient credits. Add more using https://openrouter.ai/credits. Renders fail until the account is sorted out.
```

It exits with status 3. It also writes the limit to
`~/.local/state/rimlight/limit.json` and keeps it there until a render goes
through. The Rimlight app reads that file to show the limit.

## Image models

Four providers can render:

| Provider | What it uses | Key |
|---|---|---|
| `codex` | The Codex CLI's image tool, on the ChatGPT plan Codex is signed in with. This is the default. It has a daily image limit | None |
| `openai` | OpenAI's Images API. The model is `gpt-image-2.5-flare` unless you pick another | Yours |
| `openrouter` | OpenRouter's Images API, with a model you pick | Yours |
| `custom` | Any service that copies OpenAI's or OpenRouter's API at its own address. Set it with `--base-url` and `--dialect openai` or `--dialect openrouter` | Yours |

For OpenRouter, the model list shows only models that take reference
images and draw raster images. Refinements, fixes and builds all send
images to the model. `rimlight` looks up what each OpenRouter model accepts
and sends only those fields. It asks for a square image at the size closest
to 1254 px, and it sends one request per image.

An API render costs money for every image, fix attempts included. Codex
takes about a minute per render. API models are usually faster.

```sh
rimlight image                                     # the model that renders, and where its key comes from
rimlight image --models --provider openrouter      # the models a provider offers, with prices
rimlight image --set openrouter --model google/gemini-3-pro-image
```

Your choice is saved in `~/.config/rimlight/image.json`. The Rimlight app
writes the same file from its settings, so a choice made in either place
holds for both. The file holds no secrets. `generate`, `fix` and `build`
read it for every render. They also take `--provider`, `--model`,
`--base-url` and `--quality` to override it for one command.

### API keys

The Rimlight app keeps your keys in its Keychain item. When `rimlight`
needs a key, it asks the running app over a local Unix socket,
`~/Library/Application Support/Rimlight/keys.sock`. The app checks the
caller's code signature before it answers. So the key never sits in an
environment variable, an argument or a file the agent could read. If the
app is busy, for example behind a Keychain dialog, a render waits up to
three minutes for its answer.

Without the app, set the key in your terminal:

```sh
export RIMLIGHT_OPENAI_API_KEY=...
export RIMLIGHT_OPENROUTER_API_KEY=...
export RIMLIGHT_CUSTOM_API_KEY=...
```

`rimlight` reads only these names. An `OPENAI_API_KEY` that is already in
your shell is never used.

The skill and the styles were tuned on Codex's image model. Other models
read the same text differently. No other model has been tested on builds
yet.

## Building the .icon

A render is one flat image. `rimlight build` turns the one you pick into an
Icon Composer package made of layers. Dark gets its own ground and keeps
the subject's colours. In Clear and Tinted, the plan can lift the part
that carries the idea to light grey, so it shows over the dark ground.

Ask your agent to build the icon you picked. Then this happens:

1. The agent looks at the icon and writes a layer plan. The plan names the
   ground and each part of the subject.
2. The image model draws every layer as an edit of your pick, on a flat
   colour. `rimlight` keys that colour out again.
3. `rimlight` fits the layers back onto the pick and packs the `.icon`.
4. It renders the six appearances and draws a review sheet.
5. The agent looks at those and redraws what came out wrong.

The skill's `build.md` is the agent's guide.

A build costs one image per layer, one for the ground, and usually one for
Dark's ground. That is four to seven images for most icons, or two to
three minutes on Codex. If the plan changes, only the layers whose words
changed are drawn again. The package is a redraw of your pick, so it is
close to it but not the same pixel for pixel.

Each icon builds in its own folder, `.rimlight/sets/<set>/<slug>/builds/main/`.
The package is `builds/main/out/<Title>.icon`, named after the icon's
title. Some icons can be built more than one good way. `--direction NAME`
builds another way beside the first, in `builds/<direction>/`. A build
keeps `run.json` in its folder up to date while it runs. Each run that
packs the icon writes `build.json`. The app reads both. Nothing is written
into your Xcode project.

The six renders need Xcode 26 with Icon Composer. Without it, `rimlight
build` still makes the package, but no renders.

```sh
rimlight doctor          # reports ictool, Icon Composer's renderer
rimlight build --help    # every stage and option
```

## The styles

Eight style files set the look. Each has anchor icons, a rendering standard
and a Never list.

- `soft-3d-object.md`: one physical thing with volume in a matte or satin
  material, studio lit, on a field or as the tile.
- `glass-and-chrome.md`: a mark or form in glass, chrome, foil, pearl or
  inner light, drawn by what shows through, reflects or glows.
- `lettermark-and-wordmark.md`: the name or its initial is the whole icon,
  in type drawn for the brand.
- `mono-mark.md`: one symbol drawn as a logo on a quiet ground, black on
  white or white on near-black.
- `mascot.md`: a character or a face, cropped close.
- `hardware-and-skeuomorph.md`: a real device in faithful materials, its
  face as the tile.
- `system-glyph.md`: Apple's own first-party look. A UI object with a
  gentle gradient, a highlight along the top and a tinted shadow under it.
- `scene-and-collage.md`: a picture, not a symbol. An illustrated place, a
  vintage print, a sticker collage or a paper object.

By default, `rimlight install-skill` builds the skill with `Adaptive.md`,
an index of all eight. The agent picks the styles that suit the app, two or
three for a first exploration. It reads each style's file from `styles/`
before it renders with it.

`--style <name>` holds the skill to one style. The name is the file name
without `.md`, as in `--style mono-mark` or `--style soft-3d-object`.
`--style none` leaves out the design process and the styles, and installs
only the instructions. Use it when you bring your own process. All eight
style files are installed whatever you pick, so you can still name one in a
message to use it for that request.

## The `.rimlight/` folder

Each set is a folder under `.rimlight/sets/`. Each icon is a folder inside
its set. An icon folder holds:

- `icon.png`, the render.
- `raw.png`, the image before the fit, when there was a fit.
- `original.png`, the model's opaque render, when a fix made the image.
- `icon.json`, the record of how the icon was made.
- `builds/`, when the icon has been built.

Only `rimlight` writes renders. [FORMAT.md](FORMAT.md) describes
every file and field.

## Roadmap

- Test image models other than Codex's on a set of known builds and on one
  blind build, so the model picker can mark the ones that build well.
- `rimlight install-skill --harness opencode`, for OpenCode's own folder.

## License and name

Apache-2.0. See [LICENSE](../LICENSE). "Rimlight" is the name of this project
and of the app, so please give a fork another name.
