# Changelog

## 0.8.8, unreleased

- A 403 from an image API no longer says the key was rejected. The key works
  but isn't allowed this, as with an OpenAI organization that isn't verified
  yet, so the failure shows the API's own message. A 401 still says the key
  was rejected.

## 0.8.7, unreleased

- The design guide's brainstorm example names an invented app, so the text the
  app ships and installs for agents carries no private project name.

## 0.8.6, unreleased

- `install-skill` installs for Codex too, in `$CODEX_HOME/skills` or
  `~/.codex/skills`, when that home exists. Codex's `SKILL.md` is Claude
  Code's text with a `## Codex` section after it (`SkillHarness.codexNote`):
  run `rimlight` outside the sandbox, one command at a time, with a long
  timeout; look with `view_image`; ask in plain text without
  `AskUserQuestion`. Claude Code's skill is byte for byte what it was.
  `--harness claude|codex` picks one, and `--skills-dir` alone stays Claude
  Code's. A Codex skills folder linked to Claude Code's gets no Codex copy,
  so the note never lands in Claude Code's skill. `--json` keeps the first
  install's fields at the top and lists every install in `skills`.
- `self-install` installs both the same way, and its `--json` adds `skills`.
- A project command refreshes an older Codex skill as it does Claude Code's.

## 0.8.5, unreleased

- `IconFilter`'s traits give way to what an icon was made with: `references`
  and `models`, the image models by the id `icon.json` records, one group
  where either pick lets an icon through. `IconFilter.models(in:)` lists the
  models that drew a set of icons. The chat and opaque traits are gone.
- `IconFilter.builds` keeps icons with a finished Icon Composer build, or
  those without one; `matcher` and `arrange` take the built icons' ids, and
  `ProjectStore.hasBuild` answers it for one icon with a listing and a stat.
- A transparency fix keeps the model's opaque render as `original.png` beside
  the icon, so a cutout or an edit can be checked against what the model drew.
  `raw.png` was never that after a fix: it is the image before the tile fit.

## 0.8.4, unreleased

- The cutout clears Codex's painted checkerboard: any blend of its two greys
  counts as ground, so the flood crosses the soft seams between squares, and
  only the largest piece of the drawing is kept, so the noise's specks don't
  spread the tile across the frame.

## 0.8.3, unreleased

- The cutout comes last. A model that draws transparency gets its fix renders
  first, since its own alpha is cleaner; only a render still opaque after them
  is cut out on the Mac. A model that can't draw transparency still gets the
  cutout alone. A cutout prints a `CUTOUT` line saying why it was needed, and
  the skill has the agent tell the user.

## 0.8.2, unreleased

- A render waits up to three minutes for the app to hand over its key, with a
  NOTE after five seconds, instead of giving up at five while the app shows a
  dialog such as the Keychain's. A key that doesn't arrive says why: the app
  refused, didn't answer, or isn't running.

## 0.8.1, unreleased

- An opaque render can be cut out on the Mac: the painted ground is cleared
  from the corners in, or by Vision's subject mask, and the result kept only
  when it is shaped like a tile. `fixAttempts` records it as `cutout`. A model
  that can't draw on transparency gets no paid fix at all.
- The tile fit takes a tile drawn edge to edge once its corners are clear.
- `rimlight image --models` and the model lists say what each model costs and
  whether it draws on transparency.

## 0.8.0, unreleased

- Renders go through the image model picked in Rimlight's settings or with
  `rimlight image --set`: Codex on the ChatGPT plan as before, OpenAI's or
  OpenRouter's Images API on the user's key, or any service copying one of
  them at its own address. `generate`, `fix` and `build` take `--provider`,
  `--model`, `--base-url` and `--quality` for one command.
- `rimlight image` shows the model that renders and where its key comes from,
  and `--models` lists a provider's models. The app hands keys over a local
  socket after a code-signature check; a terminal can set
  `RIMLIGHT_<PROVIDER>_API_KEY`.
- Every API render is normalized to the 1254 px square PNG Codex draws, so the
  tile fit, the fixes and the build work the same on every model.
- OpenRouter requests send only the fields the model lists, one request per
  variant, and its errors read as their own lines: a rejected key, out of
  credit, a budget with its reset time, a moderation refusal, a model that
  doesn't exist.
- `generate --json` gains a `render` object, and an API render prints
  `RENDER <tool> <model> <s>s` where Codex still prints `CODEX`. `icon.json`
  records `openai-images`, `openrouter-images` or `custom-images` as
  `generator.tool`.
- The limit file is `limit.json`, with `provider` and `note`; a
  `codex-limit.json` from 0.7 is still read. Exit status 3 now means any
  refusal of every render, an account out of credit included.
- The skill, `build.md` and the help text say "the image model" for whoever
  draws, and keep Codex's name on the drawing quirks measured on it.

## 0.7.2, 2026-10-30 (private)

- A render started from a Codex chat knows Codex is its host: `icon.json` says
  `"by": "codex"`, and the job marker names the Codex process the app launched,
  including npm's, where that process is node running Codex's script.
- `--by` defaults to the agent that was detected instead of always `claude-code`.

## 0.7.1, 2026-10-25 (private)

- When `~/.local/bin` is not on PATH, `install-skill` and `skill` name the
  standalone link `~/.local/bin/rimlight` instead of the version folder it
  points at, which an update removes.

## 0.7.0, 2026-10-25 (private)

- A layer's Dark copy has more ways to change colour, all free.
  `"dark": "pick"` moves it onto the pick's colour, so a part recoloured
  for Default goes back to the pick's in Dark. `"dark": {"tone": "#rrggbb"}`
  moves it onto any colour. A pick copy now scales chroma and turns hue
  instead of shifting in OKLab, which had sent a brown disc's rim into
  blue.
- Dark can show other parts than Default, as a last resort.
  `"dark": {"draw": "words"}` has Codex draw a layer's Dark copy, and
  `"only": "light"` or `"dark"` puts a layer in one appearance. A plan
  with either needs `"consent"` in the user's own words, which the sheet
  prints as a `CONSENT` line, and the build guide has the agent ask first.
- `removeBuild` sends one build direction to the Trash.
- An icon can be a favorite, and `duplicateIcon` copies an icon with its
  builds to `<slug>-copy` with a fresh chat.

## 0.6.0, 2026-10-23 (private)

- A build says what it is doing. Each direction's `run.json` holds the
  running stage, the round, the process and the Claude Code process it runs
  under, written as each stage starts and when the run ends, so the app can
  show a build while it runs and tell which chat started it.
- `build.json` names what the run made: the package, `out/hero.png`, the
  six renders, and the ground and each layer's files in the package. A
  round that fails before pack keeps naming the package that is there.
- `out/hero.png` is the image to show for a build: Default's render, or
  without ictool the assembly cut to the tile.
- Nothing a build writes is ever half there. Every image is renamed into
  place whole, and pack makes the package and the renders in a hidden
  folder and swaps each in at once; a failed render leaves the last build
  as it was.
- A build whose icon was deleted stops, instead of making its folder again.
## 0.5.2, 2026-10-23 (private)

- Clear and Tinted take the darker of the two grounds. They always took
  Dark's, which for `"dark": "invert"` on a dark pick is light grey:
  quiet-pick's flipped direction lost its white square in all four.
- An `EDGE` line reports the same block every run. Blocks that tied went
  to whichever the dictionary listed first.
- A named direction's first build makes its own tile. It stopped at "no
  tile yet" and asked for `--stage preview` first, which cost a run.
- Every draw and dry run prints `SPENT`: the images drawn for the icon so
  far, every direction together, kept or replaced, a copy shared between
  directions counted once. The agent added quiet-pick's `COST` lines up to
  9 when 7 were drawn, and told the user it had reached its budget.
- A dry run with a `clear` layer says that one coming back opaque costs
  one more image.
- The build guide counts fixes from `SPENT`, and the note says so when the
  agent comes to recommend another direction than the one it asked with.

## 0.5.1, 2026-10-23 (private)

- The build guide is strict about what it sees at zoom. Any flaw in a 1:1
  crop that the pick lacks, a wavy or stepped outline, a band, halo or
  fringe, mottle, a part a shade off, is a defect to fix, never "invisible
  at icon size". Every round walks each layer's outline with `--stage
  zoom --outlines`; an `EDGE` warning blocks "Done" unless the pick shows
  the same at the same place; every round is priced with `--dry-run`, and
  a free round that prices above 0 is checked before it is sent. The fixes
  table gains rows for a rough or banded outline, a mottled fill and an
  off colour, and the note says what went wrong in plain words.
- `--stage zoom --outline LAYER` (repeatable), or `--outlines` for every
  layer, writes 1:1 crops along the layer's whole outline, the pick beside
  Default and Dark (or the renditions `--rendition` names), as few sheets
  as hold them, `out/zoom-outline-<layer>-<n>.png`, with a `ZOOM` line
  each. Each crop is labelled with its box. The outline under a layer
  above is left out.
- The `pack` stage prints an `EDGE` line per layer: its outline and fill
  in Default against the pick's at full size, each at the 64 px block
  where Default is furthest from the pick. `outline` is how far the edge
  wobbles about its own course in pixels, `band` how much lighter or
  darker the pixels just inside the edge are than those a little further
  in, `fill` the grain inside. A `WARNING` names the layer and a box ready
  for `--stage zoom --box` where the outline is rougher than the pick's,
  carries a band the pick's does not, or the fill is mottled. MATCH, at a
  quarter of the tile, could not see quiet-pick's stepped grey tile.
  The line also gives the inside's median `lightness` and `colour ΔE`,
  OKLab ΔE times 100 against the pick's; from 3 a `WARNING` says the
  colour is off. quiet-pick's grey tile came back 4.3 off, about #3f3f3f
  for #333333, which no other check saw.
- A layer's `"match": true` moves it onto the pick's colour after the fit,
  every pixel shifted in OKLab by the difference between the medians of
  its solid inside and the pick there, so shading and texture stay. Free.
- The magenta key gives a part's outline its own colour and Codex's
  smooth edge. It ramped alpha on the distance to the key, which turned
  quiet-pick's flat grey tile's corner into steps with a light rim and a
  green fringe. Now each pixel beside a solid part is unmixed along the
  line from the key to that part's colour, which sets its alpha and makes
  its colour the part's; the outermost solid pixels within a small step of
  the part's colour take it, which removes the purple and green pixels
  Codex leaves where its colour channels change a pixel apart; and a solid
  pixel near the outline that is off the part's colour loses the key's
  spill, which sleep-dial's pointer showed as a purple line. A drawing is
  keyed at the size Codex drew it and resized after, and a resize no
  longer lightens a dark part's edge where it overshoots alpha.
- Changing `dark` never draws a layer again. A layer's signature named
  whether its light was asked neutral, so switching quiet-pick's Dark from
  `dim` to a `tone` redrew both tiles for two images. Drawings made before
  still match: the old last line of their `.sig` is ignored when comparing,
  between directions too. The prompt still asks for neutral light only
  when Dark recolours the ground, since under `dim` a night scene's
  coloured light is part of the picture.

## 0.5.0, 2026-10-23 (private)

- The build guide has the agent finish the icon before handing it over. It
  writes `checks` from the pick, judges every round by `MATCH`, `CONTRAST`
  and `CHECK`, and fixes what fails, with up to six images of its own fixes
  without asking. Before, it stopped after two rounds and the user found
  the flaws.
- An icon with more than one good way to build, such as a flat black mark
  whose Dark can keep it black or flip it white, gets one question before
  any image: up to three directions, Build all, or the user's own words.
  Each direction builds in its own folder.
- `rimlight build --direction NAME` builds another way of the same pick in
  its own folder, `builds/<direction>/`, such as a Dark that turns a black
  mark white beside one that keeps it black. Without the flag the direction
  is `main`. Every stage, aid and option acts on that direction's folder;
  `main`'s package is still `out/<Title>.icon`, another direction's is
  `out/<Title>, <direction>.icon`. `ProjectStore` lists an icon's directions,
  `main` first, and reads and writes each one's `build.json`.
- A direction draws only what no other direction of the icon has drawn:
  before `draw` spends an image on a layer, it copies another direction's
  drawing of that layer from the same words and the same pick, with a
  `SHARED <id>/<layer> from <direction>` line. `COST`, `--dry-run` included,
  counts only what Codex will draw; the dry run lists each copy as
  `would share`. `--redraw` always draws.
- An icon's `build/` from 0.4.2 or earlier moves to `builds/main/` the first
  time `rimlight build` touches it, with a `MOVED` line. When `builds/main/`
  exists already it stays, with a warning. Until then readers take it as
  `main`.
- The `sheet` stage writes `out/compare.png`, the pick against the Default
  render with an anaglyph of the two (red where the pick is lighter, cyan
  where Default is), adds that overlay to `review.png`, and prints a
  `MATCH` line: the share of the tile that matches the pick and up to
  three boxes, ready for `--stage zoom --box`, where a part moved or
  changed shape. A redraw's drift in shade, grain or glow does not count.
- The `pack` stage prints a `CONTRAST` line per appearance with each
  layer's contrast against what is behind it, and a `WARNING` for a layer
  that fades into it along much of its outline. Clear and Tinted judge the
  hero only, or warn when every layer fades.
- `plan.json` takes `checks`, up to eight sentences of what must survive
  from the pick. They cost nothing and the sheet prints each as a `CHECK`
  line every round.
- `dark: "invert"`, and a layer's own `"dark": "invert"`, flip lightness
  for Dark in code while hue, chroma and shading stay: a warm near-black
  becomes a warm near-white. Free.
- Mono's hero lift no longer turns a flat layer's dither into grain in
  Clear and Tinted: a flat layer lifts to a flat light grey.

## 0.4.2, 2026-10-22 (private)

- When Dark recolours the ground, each layer gets a Dark copy with the
  ground's hue taken out of it: the caliper's black button kept the orange
  housing's reflection in its socket, which read as orange light over a
  matte black Dark. Default keeps the pick's reflections. A part that is
  itself the ground's colour, and a grey ground, are left alone.
- The magenta key takes its spill out of the outline's band, where a pixel a
  quarter magenta read as solid and left a purple rim.

## 0.4.1, 2026-10-22 (private)

- `dark` in `plan.json` takes the user's own Dark: `{"keep": "words"}` has
  Codex draw Dark's ground from those words, and `{"tone": "#rrggbb"}`
  recolours the ground in code to that colour, keeping its grain, for free.
  Changing only `dark` draws no other layer again. Before, Dark could only
  be Codex's "same hues, stepped down" or the ground dimmed, so a user who
  wanted an orange housing matte black in Dark had no way to ask.

## 0.4.0, 2026-10-22 (private)

- `rimlight build` draws the icon in layers instead of splitting the pick.
  The agent writes `plan.json`: the ground, Dark's ground (`generate` or
  `dim`) and each layer, bottom to top, with what Codex draws it on (`magenta`,
  `black` or `clear`) and what the fit does with it (`shadow`, `hero`, `soft`,
  `grey`). `--plan-file FILE|-` checks and stores it, keeping each earlier one
  in `rounds/`. The stages are `preview`, `draw` (the Codex images, four at a
  time, a layer drawn again only when its prompt changed, `--redraw NAME` to
  force one, `--stage draw --dry-run` for the count), `fit`, `pack` and
  `sheet`, with the aids `zoom` and `grid`. All of it is Swift.
- A layer is drawn again only when its own words change, so editing one
  layer no longer redraws the others; `box`, `hero`, `soft` and `grey` are
  free. Every replaced drawing stays in `gen/rounds/`, and `--restore NAME`
  brings it back. `--plan-file FILE --dry-run` prices a plan without storing
  it. A box places any layer Codex moved or resized, keyed or not, and a fit
  that reaches the edge of its search without one prints a `WARNING`.
- The Python engine is gone: no uv, Python, PyTorch or SAM, no setup, no
  `--setup`, no exit 5, and Intel Macs can build. `rimlight doctor` reports
  ictool alone, and no longer suggests a Homebrew tap that does not exist yet.
- `THIRD-PARTY-NOTICES.md` goes with the wheels it covered; the package ships
  no code by others.

## 0.3.0, unreleased

- The layered build's engine, the Python prototype that turns a picked render
  into an Icon Composer `.icon`, ships in the resource bundle as `Engine/`
  with its `uv.lock` (Python 3.14.0, torch 2.14.1 and SAM 2) and three
  prebuilt pure-Python wheels. `THIRD-PARTY-NOTICES.md` carries the wheels'
  licences and lists what the first build downloads.
- `rimlight build --root DIR <id>...` runs the engine's stages (preview,
  subject, edits, analyse, build, then the review sheet) or one of them with
  `--stage`, and the aids `verify`, `sheet`, `zoom` and `grid`. Its first run on
  a Mac sets the engine up in `~/Library/Application Support/Rimlight/`: its
  own uv 0.11.19, hash checked, then Python and the packages synced from the
  lock, an import check and the SAM weights, with `SETUP` lines; `--setup`
  does only that and repairs an environment that cannot import. The Codex
  images the engine lists are made here, twelve at a time, and
  `--stage edits --dry-run` prints their count without making any. Exit 3 is
  Codex's image limit, 4 a missing input, 5 an engine that could not be set
  up, which leaves nothing half made. Apple silicon only.
- `rimlight doctor` reports the build engine, its weights, its uv, ictool and
  Apple silicon.
- `rimlight build <set-id>/<slug>` builds a project's icon in its own
  `build/` folder from its `icon.png`, the package named by the icon's title.
  `--subject-file FILE|-` checks the subject and stores it, keeping each
  earlier one in `rounds/`; `build.json` records the pick's hash, versions and
  stages of the run that made the package; a lock keeps one build of an icon
  at a time; Codex images get job markers of mode `build`; `--prune` removes
  what a run from `analyse` makes again. `docs/FORMAT.md` documents `build/`.
- `scripts/release` refuses a release unless `scripts/engine-test` passes,
  which checks the engine's lock and runs its tests. The formula's caveats
  and the README's "Building the .icon" give the first build's download,
  about 430 MB, and its needs: Apple silicon and Xcode 26.

## 0.5.1, 2026-10-23 (private)

- Version 0.2.1.
- `rimlight self-install` installs the running binary into
  `~/.local/share/rimlight/<version>/` with `~/.local/bin/rimlight` pointing at
  it, and the skill with it. `rimlight self-uninstall` removes that copy.
- `rimlight doctor` lists every `rimlight` on `PATH`, which one runs, who
  installed each, and the installed skill, with the command that fixes each
  problem.
- `rimlight skill` prints the skill text a chat starts with, for the app and
  for reading.
- `rimlight version --json` reports the version, path, kind and schema.
- When Codex refuses a render because the ChatGPT plan's image limit is
  reached, `generate` and `fix` stop at once instead of spending their fix
  attempts, print a `LIMIT` line with the reset time, and exit with status 3.
  The limit is kept in `~/.local/state/rimlight/codex-limit.json` for the app
  until a render goes through. The skill tells the agent to pass the line on
  and wait, and never to watch renders with a wait loop of its own.
- The installed skill keeps a `.install.json` record. `install-skill` without
  `--style` keeps the recorded style, and a project command run by a newer
  `rimlight` than the one that wrote the skill rewrites it with the same
  style.
- The `rimlight` command, version 0.1.0: `init`, `status`, `set create`,
  `set rename`, `generate`, `fix`, `fit`, `install-skill` and `version`, writing
  the `.rimlight/` format at schema 1 and rendering through the Codex CLI.
- The `rimlight` agent skill, installed to `~/.claude/skills/rimlight/` by
  `rimlight install-skill` with the eight style files beside it.
- The skill is adaptive by default. The agent picks the styles that suit each
  app from the eight and reads their files, and the soft 3D object style is
  one of them rather than the default.
- `rimlight install-skill --style <name>` installs the skill with one of the
  eight styles or `none` in place of `adaptive`, and its output and `--json`
  name the style it installed.
- Renders fitted to Apple's icon shape: a grey tile template on every fresh
  render, then a 1024 px tile centred in the 1254 px frame and cut with the
  Icon Composer mask. An opaque render gets up to three transparency fix
  attempts.
