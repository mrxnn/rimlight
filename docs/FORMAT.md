# The `.rimlight/` format

This file describes every file Rimlight keeps on disk and every field in
them. It is for anyone who writes a tool that reads a project's icons, and
for anyone who changes how `rimlight` stores them.

A project's icon work lives in `<project>/.rimlight/`. This is schema 1.

Three programs touch it:

- The `rimlight` command is the only one that writes renders.
- The Rimlight app creates, renames and deletes sets. It deletes and
  duplicates icons, and it writes the chat, archive and favorite fields.
- An agent writes nothing here directly. It calls `rimlight`.

## Layout

```
<project>/.rimlight/
  project.json
  sets/
    set-001/
      set.json
      <slug>/
        icon.png        the render as stored
        raw.png         the image before the fit, only when icon.png was fitted: the
                        model's own, or its transparency fix when one ran
        original.png    the model's opaque render, only when a transparency fix
                        (an edit or the cutout) made the image from it
        icon.json       the record, written last
        builds/         the layered builds of this render, one folder per direction,
                        made by `rimlight build`
  .jobs/<id>.json       one marker per render in progress
  .lock                 the advisory lock for read-modify-writes
  .cache/               the app's; the command never touches it
```

A folder is a project when `.rimlight/project.json` exists.

Readers skip some things:

- Folders whose names are not set ids or slugs.
- Any set or icon whose JSON is missing or does not decode. A render that
  is still landing looks like this.
- An icon's `builds/` folder, when they read the icon itself.

## Encoding

Every JSON file is UTF-8. It is pretty-printed with sorted keys and
unescaped slashes, and it ends with a newline.

Dates are ISO 8601 in UTC with whole seconds, such as
`2026-10-12T15:25:02Z`. Readers also accept fractional seconds.

Writers write every key. An optional value that is absent is written as
`null`. The one exception is a ref object, which carries only its own
keys. When a key is missing, readers use the default listed below.

## Schema

`project.json`, `set.json` and `icon.json` carry `"schema": 1`. Every write
stamps it. If a reader finds a higher number than its own, it must refuse
the project and say to update `rimlight`. It must never guess at fields it
does not know.

## Writes and locking

Every file is first written as a hidden temp file in the same folder,
`.<name>.<uuid>.tmp`. Then it is renamed over the target. So a reader sees
either the old file or the new one, never half of one.

- Reads take no lock.
- A read-modify-write holds an exclusive `flock` on `.rimlight/.lock` for
  the whole cycle. It waits up to 5 seconds for the lock.
- An icon lands in this order: `original.png`, `raw.png`, `icon.png`, then
  `icon.json`. So a reader that sees the record also sees the image.
- A delete first renames the folder to a hidden name, then removes it.
- Each job marker has one writer, so markers take no lock.

## Identifiers

A set id is `set-` and at least three digits: `set-001`, `set-002` and so
on. A new set takes the highest number plus one.

A slug is 1 to 64 characters of `a-z`, `0-9` and `-`. It cannot start with
a hyphen. It is unique in its set and works as a folder name.

`--count N` names the variants `<slug>-1` to `<slug>-N` and titles them
`<title> 1` to `<title> N`.

Readers take the set id and the slug from the folder names. They ignore the
`id` and `slug` fields.

## `project.json`

Two keys, the integer `schema` and the date `created`. `rimlight init` or
the app writes it once.

## `set.json`

| Key | Type | Meaning | Writer |
|---|---|---|---|
| `id` | string | `set-NNN`, the same as the folder | command, app |
| `title` | string | The set's name, `Untitled set` until renamed | command, app |
| `created` | date | When the set was made | command, app |
| `chat` | object of strings | Harness name to the chat's current session id. Default `{}` | app |
| `chatHistory` | object of string arrays | Harness name to the chat's sessions, oldest first, at most 100. Default `{}` | app |
| `archived` | boolean | Hidden from the sidebar. Default `false` | app |

## `icon.json`

The app writes `archived`, `favorite`, `chat` and `chatHistory`. The
command writes the rest.

| Key | Type | Meaning |
|---|---|---|
| `slug` | string | The same as the folder |
| `title` | string | Display name |
| `created` | date | The first render. A replacement keeps it |
| `by` | string | Who asked for the render, from `--by`. Default `""` |
| `mode` | string | `refine` when `parent` is set, else `generate` |
| `prompt` | string | The agent's prompt, without the template line |
| `parent` | object or null | `{set, icon}`, the icon this one was made from |
| `refs` | array of objects | The `--ref` images in order. `{set, icon}` for an icon in this project, else `{path}`, an absolute path. Default `[]` |
| `generator` | object or null | `{tool, model}` that made the stored image |
| `image` | object | `{width, height, alpha}`. `alpha` is judged from the pixels |
| `archived` | boolean | Listed as archived. Default `false` |
| `favorite` | boolean | Listed in Favorites. Default `false` |
| `chat` | object of strings | As in `set.json` |
| `chatHistory` | object of string arrays | As in `set.json` |
| `fixes` | string array or null | Prompts of edits made to this render in place |
| `fixAttempts` | array or null | Every transparency fix attempt, as `{kind, transparent, seconds}` |

An attempt's `kind` is one of these:

- `transparency-edit`, an edit of the opaque render.
- `reroll`, a fresh render of the same request.
- `cutout`, the painted ground cut away on the Mac. No render is spent.

### Replacing an icon

`generate --force` and `fix` can replace an icon. A replacement keeps
`created`, `archived`, `favorite`, `chat` and `chatHistory`.

- A replacement that refs the icon itself is a fix of its own file. It
  keeps `prompt` and adds the fix's prompt to `fixes`.
- Any other replacement takes the new prompt. It starts `fixes` and
  `fixAttempts` over.

### Duplicating an icon

A duplicate is a copy of the icon's whole folder, `builds/` included, in
the same set. The two can then be refined and built apart.

- Its slug is the first free one of `<slug>-copy`, `<slug>-copy-2` and so
  on. Its title is `<title> copy` or `<title> copy <n>` to match. A copy of
  a copy drops that suffix first.
- It keeps the record, except three fields. `created` is the time of the
  copy. `archived` is false. `chat` and `chatHistory` are empty.
- The folder is copied under a hidden name, then renamed into place with
  its record. This happens under the store's lock.
- The copy is refused while any build direction's `.lock` is held.
- A copied build's package keeps the original's title until the copy is
  built again.

## `.jobs/<id>.json`

The command writes one marker per image before it renders. It removes the
marker when the image lands or the process exits. `rimlight status` and the
app remove any marker whose process is gone.

| Key | Type | Meaning |
|---|---|---|
| `id` | string | A lowercase UUID, also the file name |
| `pid` | integer | The `rimlight` process that renders |
| `hostPID` | integer or null | The agent process above `pid`. If it exits, the render dies too |
| `set`, `slug` | string | The icon the render makes or replaces |
| `title` | string | The title the icon will have |
| `mode` | string | `generate`, `fix` or `build`. `build` is an image that `rimlight build` makes for an existing icon. A reader skips a marker whose mode it does not know |
| `started` | date | When the render began |

## `builds/`

`rimlight build <set>/<slug>` turns the icon's `icon.png`, read where it
is, into an Icon Composer package made of layers. The image model draws
each layer of the agent's plan as an edit of the pick. The command then
keys, fits and packs them. The command writes these folders itself. This is
the one place where it does not write through the store.

### Directions

A pick can have more than one good build. Take a black mark. Its Dark could
keep it black, turn it white, or lighten the ground. Each of these is a
direction with its own folder, `builds/<direction>/`.

- A direction's name is 1 to 32 characters of `a-z`, `0-9` and `-`.
- A build without `--direction` is `main`.
- Readers list `builds/` and take the folders with a valid name. `main`
  comes first, then the rest by name.
- An icon counts as built when any of its directions has a `build.json`.

```
builds/
  main/                   a build without --direction
  flipped/                rimlight build <set>/<slug> --direction flipped
```

### A direction's files

```
<direction>/
  .lock                   held exclusively by a build of this direction for its whole run
  plan.json               the agent's layer plan, from --plan-file
  rounds/plan-<n>.json    every earlier plan.json, n from 1
  run.json                what a build of this direction is doing now, or did last
  build.json              the record of the run that made the package
  src/tile.png            the pick's tile at 1024 px; src/ref.png, the square the image model edits
  src/grid.png            the tile with a grid in tile pixels, for the plan's boxes
  gen/<name>.png          what the image model drew for each layer, `ground` and `ground-dark` included,
                          with its prompt in <name>.txt, the layer's own words in <name>.sig,
                          its key in <name>.key and the render's log in <name>.log
  gen/rounds/<name>-<n>.* every drawing a redraw replaced, n from 1, for --restore
  layers/<name>.png       each layer keyed and fitted at 1024 px; layers/fit.json, the fits;
                          <name>-dark.png, Dark's copy without the ground's hue, and a hero's
                          <name>-mono.png
  out/<Title>.icon        main's package, named by the icon's title; another
                          direction's is out/<Title>, <direction>.icon
  out/renders/            <Rendition>.png: the package in Default, Dark, ClearLight,
                          ClearDark, TintedLight and TintedDark, 1024 px, Display P3
  out/hero.png            the image a viewer shows for the build: a copy of Default's
                          render, or without ictool the assembly cut to the tile
  out/assembled.png       the layers composited plainly, no renderer in between
  out/review.png          the review sheet: the pick, the assembly, the layers, the six renders
  out/compare.png         the pick against Default, and an anaglyph of the two
  out/zoom-*.png          the zoom aid's sheets: by box, by quadrant, and zoom-outline-<layer>-<n>.png,
                          1:1 crops along a layer's outline
```

The contract is `plan.json`, `rounds/`, `run.json`, `build.json`, the
package, `renders/`, `hero.png` and `review.png`. Everything else belongs
to the build and may change between versions.

### The old `build/` folder

Version 0.4.2 and earlier built in `<slug>/build/`, which holds the same
files. The first `rimlight build` of the icon moves it to `builds/main/`
under the project's lock. If `builds/main/` exists already, it leaves
`build/` alone. Until the move, a reader takes `build/` as `main`.

### Drawings

`gen/` holds the drawings. Each one cost an image, so nothing removes this
folder.

- A layer is drawn again only when its own words change. Its words are kept
  in `gen/<name>.sig`.
- `dark` is in no layer's words, so changing it draws no layer again.
- A `.sig` written by 0.5.0 or earlier has one more last line, `neutral
  light` or empty. Readers drop that line before they compare, so such a
  drawing still matches.
- Before a direction draws a layer, it looks for the same drawing in
  another direction of the icon. It copies it when that direction's
  `<name>.sig` and `src/ref.png` match its own, trying `main` first. Dark's
  ground also needs the same `gen/ground.png`. The copy is its own file,
  never a link.

### Safe reads

Every image a build writes lands whole, renamed into place. The `pack`
stage makes the package and the renders in a hidden `out/.pack-<uuid>/`,
then swaps each one in as one folder. So a reader of `out/` sees the last
build or the new one, never half of either. A reader needs no lock.

When the icon's title changes, the next package takes the new name and the
old package goes.

`rimlight build --prune` removes what a run from `fit` makes again. That
is `layers/`, `out/renders/` and `out/zoom-*.png`, in one direction.

### Removing a direction

A viewer removes a direction as a whole, and never while its `.lock` is
held. Under the store's lock, it renames the folder to
`<slug> <direction> build`, a name no reader takes. Then it moves that
folder to the Trash. It removes `builds/` once it is empty. Another
direction keeps its own copies of any drawings the two shared.

### `run.json`

`run.json` is what the app shows while a build runs.

- A run that includes `draw`, `fit` or `pack` writes it when the run
  starts, as each stage starts, and when the run ends.
- A run of only `preview` or `sheet`, an aid, or a dry run leaves it as it
  was.
- It is written atomically without the store's lock, because the run holds
  `.lock`.
- Once the icon's `icon.json` is gone, no build writes `run.json` or
  `build.json`. A run whose icon was deleted stops.

| Key | Type | Meaning |
|---|---|---|
| `schema` | integer | 1. A reader skips a build with a higher one. It does not refuse the project |
| `state` | string | `running`, `done` or `failed` |
| `stage` | string or null | The stage that is running. Null once the run ended |
| `stages` | string array | The stages that finished, in order |
| `failed` | string or null | The stage that failed |
| `pid` | integer | The `rimlight` process. If a `running` record's process is gone, by the same test as a job marker's, the run was killed. Read it as stopped |
| `host` | integer or null | The agent process the run ran under, as a job marker's `hostPID`. Null from a terminal |
| `round` | integer | The plans in `rounds/` plus `plan.json` |
| `started`, `updated` | date | When the run started, and when this record was written |

A viewer shows a direction that has a `hero` to show or a live run. A
direction with neither, such as a `main` that only made its tile, is not a
build yet.

### `build.json`

Each run that includes the `pack` stage writes the direction's
`build.json`, under the store's lock.

| Key | Type | Meaning |
|---|---|---|
| `pick` | string | SHA-256 of `icon.png` when the run began. If the hash differs now, the package is stale |
| `rimlight` | string | The version that ran |
| `engine` | string | The pipeline that made the package: `layers` and the version of its prompts. The key keeps the name 0.3.0 gave it |
| `stages` | string array | The stages that ran, in order |
| `failed` | string or null | The stage that failed, or null when the run finished |
| `built` | date | When the run ended |
| `schema` | integer | 1, from 0.6.0 on. The keys below are there only with it |
| `host` | integer or null | As in `run.json`, for the run that made the package |
| `round` | integer | As in `run.json` |
| `package` | string | The package, relative to the direction's folder |
| `hero` | string or null | `out/hero.png`, the image a viewer shows |
| `renders` | object | Rendition to its render's path. Empty without ictool |
| `ground` | layer or null | The ground's files in the package |
| `layers` | layer array | The layers above the ground, top first |

A layer has these keys:

- `name`.
- `image`, `dark` and `tinted`. Each is a path into the package's
  `Assets/`, or null.
- `only`, which is `light` or `dark` for a layer hidden in the other
  appearance. It is absent otherwise.

A run that fails before `pack` keeps the last record's account of the
package, because that package is still there.

A record without `schema` comes from 0.5.2 or earlier. For one of those, a
reader shows `out/renders/Default.png`, never the assembly, which is an
unmasked square. It reads the layers from the package's own `icon.json`.

### `plan.json`

The plan has these top-level keys:

| Key | Takes |
|---|---|
| `ground` | `keep` and `remove`, each in words |
| `dark` | `generate`, `dim`, `invert`, `{"keep": "words"}` or `{"tone": "#rrggbb"}` |
| `layers` | The layers, bottom to top, at most eight |
| `checks` | Optional. At most eight non-empty sentences, each naming something from the pick that must survive |
| `consent` | Optional. The user's own words. A plan needs it when any layer has `only` or `{"draw": ...}` |

Each layer has these keys:

| Key | Takes |
|---|---|
| `name` | Required. `a-z`, `0-9` and `-`. Not `ground` or `ground-dark` |
| `what` | Required. The part, in words |
| `without` | What to leave out of the drawing |
| `shadow` | A shadow the layer keeps |
| `key` | `magenta`, the default, `black` or `clear` |
| `box` | `[x0, y0, x1, y1]` in the 1024 px tile, where the part sits in the pick. Required for `clear` |
| `soft`, `hero`, `grey`, `match` | Booleans |
| `dark` | `invert`, `pick`, `{"tone": "#rrggbb"}` or `{"draw": "words"}` |
| `only` | `light` or `dark` |

`--plan-file` refuses a value outside what a key takes. It keeps an unknown
key and prints a warning.

### What the Dark options do

Most of these are free. They draw nothing and change no layer's words.

- The plan's `"dark": "invert"` makes Dark's ground in code. It flips the
  ground's lightness and keeps its hue, chroma and shading. The flip is in
  OKLab, on its toe-corrected lightness, which is close to CIELAB's L*. So
  a warm near-black becomes a warm near-white.
- A layer's `"dark": "invert"` makes its Dark image,
  `layers/<name>-dark.png`, the same way from the fitted layer. Alpha is
  kept.
- A layer's `"dark": "pick"` moves the fitted layer onto the pick's colour
  for Dark. Lightness shifts as under `match`. Chroma scales by the ratio of
  the two medians, and hue turns by the angle between them, so no pixel
  crosses neutral. So a part recoloured for Default looks as it does in the
  pick when shown in Dark.
- A layer's `"dark": {"tone": "#rrggbb"}` moves it the same way onto that
  colour instead of the pick's.
- A layer's `{"draw": "words"}` is not free. The image model draws
  `gen/<name>-dark.png`, an edit of the pick in the layer's place. The fit
  places it with the layer's own fit.

A layer with `only` gets `hidden-specializations` in the package's
`icon.json`. With `dark`, it is hidden by default and shown in Dark. With
`light`, it is the other way round. Tinted, which Clear uses too, is set
like the default. A layer only in Dark is drawn as a new part in the pick's
style. The fit keeps it where it was drawn, or lays its solid bounds into
its `box`. It sits under no layer of Default's.

`match` shifts a fitted layer's colour in OKLab. The shift is the
difference between two medians: that of the layer's solid inside, 6 px
clear of its outline, and that of the pick in the same place. It acts in
the fit and is free too.

`checks` draw nothing either. They stay in `plan.json` and are in no
drawing's words. The `sheet` stage prints each one as a `CHECK` line.

## Renders

`icon.png`, `raw.png` and `original.png` are square PNGs, 1254 px a side,
whatever the image model.

- Codex draws that size. An API render within 2% of square is
  centre-cropped and resized to it, with alpha kept. One further off is
  refused.
- A fitted render's tile is 1024 px, centred, with 115 px on every side. So
  the middle crops to Icon Composer's 1024 px canvas without resampling.
  Alpha is 0 outside the tile.
- `image.alpha` is true when two things hold. The four corner patches
  average an alpha below 8, and at least 0.5% of all pixels have an alpha
  below 8.
- An opaque render is stored as it came, with no `raw.png`.

`original.png` is the render the winning fix started from:

- For an edit of the first render, or for a cutout, it is the model's first
  render.
- For an edit of a re-roll, it is the re-roll.
- A re-roll that comes back transparent stands as drawn and keeps no
  `original.png`.

`rimlight fit` leaves `original.png` alone. A replacement without one
removes it. Only the command writes `icon.png`. The app never crops, masks
or recompresses it.

## Provider and harness values

The keys are neutral. Their values name the provider or the agent that
wrote them.

`generator.tool` names who drew the image, and `generator.model` the model:

| `tool` | Provider | `model` |
|---|---|---|
| `codex-image-gen` | The Codex CLI's image tool, on the ChatGPT plan | The model Codex ran the turn with, such as `gpt-6-luna` |
| `openai-images` | OpenAI's Images API, on the user's key | OpenAI's model id, such as `gpt-image-2.5-flare` |
| `openrouter-images` | OpenRouter's Images API, on the user's key | OpenRouter's model slug, such as `google/gemini-3-pro-image` |
| `custom-images` | Any service that copies one of those APIs at its own address | The model id that service was sent |

The other values:

- `by` in `rimlight generate` defaults to the agent it runs under,
  `claude-code` or `codex`. From a plain terminal it is `claude-code`.
- `chat` and `chatHistory` are keyed by agent. The app writes `claude` for
  a Claude Code chat and `codex` for a Codex chat.
- `hostPID` is the nearest `claude` or `codex` process above `rimlight`.

Another provider or agent writes its own values under the same keys.

## Files outside the project

The command and the app share two small files outside `.rimlight/`. Both
are JSON, encoded as above.

### `image.json`

`image.json` says which image model renders. It lives in
`$RIMLIGHT_CONFIG_DIR`, else `$XDG_CONFIG_HOME/rimlight/`, else
`~/.config/rimlight/`.

The app writes it from its settings, and `rimlight image --set` writes it
from a terminal. Every render reads it, so a switch takes effect on the
next image. With no file, Codex renders.

It holds no secrets. API keys stay with the app, or in a terminal's
`RIMLIGHT_<PROVIDER>_API_KEY`.

| Key | Type | Meaning |
|---|---|---|
| `provider` | string | `codex`, `openai`, `openrouter` or `custom`. Default `codex` |
| `models` | object of strings | Provider to the model picked for it, so switching back keeps the pick. Default `{}` |
| `baseURL` | string or null | The custom provider's API root, such as `https://example.com/v1` |
| `dialect` | string or null | The API the custom provider speaks, `openai` or `openrouter`. Default `openai` |
| `quality` | string or null | The API's quality setting, such as `medium`. Null leaves it to the provider |

### `limit.json`

`limit.json` holds a refusal that stops every render. It lives in
`$RIMLIGHT_STATE_DIR`, else `$XDG_STATE_HOME/rimlight/`, else
`~/.local/state/rimlight/`.

The command writes it when the image model refuses a render because of a
plan's image limit or an account out of credit. It removes the file when a
render goes through. The app reads it to show a banner.

Version 0.7 called it `codex-limit.json`, without `provider` and `note`.
Readers still take that file when there is no `limit.json`.

| Key | Type | Meaning |
|---|---|---|
| `provider` | string | The provider that refused. Default `codex` |
| `resetsAt` | date or null | When the limit lifts, if the provider said |
| `plan` | string or null | Codex's ChatGPT plan, such as `plus` |
| `note` | string or null | An API provider's own words for the refusal |
| `recorded` | date | When it was written. A record without `resetsAt` holds for a day from here |
