# Building the .icon

`rimlight build` turns the render the user picked into an Icon Composer
package with a real Dark, Clear and Tinted appearance. You look at the pick
and write a layer plan: the ground, and each part of the subject as its own
layer. The image model draws every layer as an edit of the pick, and the
command keys, fits and packs them, renders the six appearances, compares
Default with the pick and draws a review sheet. The package is a redraw of
the pick in layers, close to it but not pixel for pixel, and it is what
ships.

Build a render once the user picks it to ship. Each build lives in a
direction's folder, `.rimlight/sets/<set>/<slug>/builds/<direction>/`. A
build without `--direction` is `main`, and its package is
`builds/main/out/<Title>.icon`, named by the icon's title; another
direction's package is `out/<Title>, <direction>.icon`. It needs Xcode 26
with Icon Composer for the renders.

The user wants the finished icon, not a draft to correct. You build it,
judge it, fix it and judge it again, as many rounds as it takes, and hand
it over only when it passes "Done" below or the budget runs out. Never hand
over a round you can see is wrong, and never ask the user to judge a round
you have not judged yourself.

## The loop

1. Run `rimlight build <set>/<slug> --stage preview`. Read the icon's
   prompt (`prompt` in its `icon.json`) and look at the grid the `GRID` line
   names, `src/grid.png`: the 1024 px tile with a line every 32 px and a
   label every 128 px, in tile pixels.
2. Write the checks: three to six sentences naming what must survive from
   the pick, each one specific enough to be false in a bad build. "The grey
   crescent is widest at the upper-left corner and tapers to nothing at the
   top-right and bottom-left corners", not "the crescent looks right". Name
   the shapes, the overlaps, the tilts and asymmetries, the palette and
   where the idea lives. They go in the plan's `checks`.
3. Decide whether the icon has more than one good direction ("Directions"
   below). When it has, ask the user before you spend an image.
4. Write the plan (below). Price it with
   `rimlight build <set>/<slug> --plan-file - --dry-run <<'JSON'`, which
   checks it and prints the `COST` line, storing and spending nothing, and
   tell the user the count in one line. Then send it with
   `rimlight build <set>/<slug> --plan-file - <<'JSON'`, ending the JSON
   with `JSON` on its own line. That checks it, stores it as `plan.json`,
   keeps the one before in `rounds/`, and runs every stage through the
   review sheet. Add `--direction <name>` to both for a named direction.
5. Refine: judge the round ("Judging a round"), fix what fails ("Fixes"),
   send the plan again, and judge again. Repeat until the build is done.
6. Hand over with the note below.
7. Make the changes the user asks for as further rounds, the same way, and
   judge each one before you hand it back. The user's changes do not count
   against your budget.

A build draws its layers four images at a time, in about a minute on
Codex, and fits and packs them in seconds. Run it in the background (Bash
`run_in_background`, timeout 600000) and wait for it to finish rather than
watching it. A second build of the same direction waits for the first.

### The budget

Free changes have no limit: `box`, `hero`, `soft`, `grey`, `match`,
`dark` set to `dim`, `invert` or a `tone` on the ground or `invert`, `pick` or
a `tone` on a layer, `--restore`, and `checks`. Try them freely; a run from `fit` takes
seconds. No change to `dark` draws a layer again, except a layer's
`{"draw": ...}`, which is one image.

Images you spend on your own fixes, after the first build of each
direction, may total six for the icon, all directions together. Price
every round with `--dry-run` before you send it, free ones included, and
read its `COST`. A round you meant to be free that prices above 0 changed
something you did not intend: find it before you send. A `clear` layer
that comes back opaque is drawn again on magenta for one more image, and
the dry run says so. Ask the user before a round that would take you past
six, and before any single round of more than three.

Every dry run and every round that draws prints `SPENT`, the images drawn
for the icon so far in every direction, kept or replaced. Count your fixes
from it, as `SPENT` less the first builds' `COST`, never by adding up
`COST` lines yourself, and give the same numbers in the note.

### Done

A round is done when all of these hold:

- Every `CHECK` holds in Default, judged at zoom, not on the sheet.
- `MATCH` names no region, or every region it names is a difference you
  zoomed on and accept: Icon Composer's own shadow in place of a cast
  shadow, a texture redrawn in the same pattern. A part that moved, grew,
  shrank, lost its tilt or changed outline is not accepted.
- No `CONTRAST` warning, or one you zoomed on that is true of the pick too
  (brown on brown in the pick stays brown on brown).
- No `EDGE` warning, unless the 1:1 crop of its box shows the same thing
  at the same place in the pick's crop beside it. "Slight" is not a
  reason to pass one.
- You walked every layer's outline at 1:1 this round
  (`--stage zoom --outlines`) and found nothing the pick lacks
  ("Defects at zoom").
- Each appearance passes "Judging a round".

When the budget runs out first, stop on the best round (`--restore` any
drawing a later round made worse), and say in the note what still fails,
the fix you would make and what it costs.

When something wrong comes from the command itself, not the plan, get as
close as the plan allows, finish, and name the defect in the note. Do not
stop the build to report it.

## Directions

Most icons have one right build, and you make it. Some have two or three
good ones that only the user can choose between, because the choice is
taste, not correctness. Ask before the first image when the icon is one of
these:

- A mark in black, white or grey on a plain ground, such as a logo or a
  flat sign. Its Dark can keep the subject and darken the ground, flip the
  whole icon (`invert` on the ground and on each layer, so black becomes
  white), or keep the subject on a lighter ground that still reads at
  night.
- A subject whose own colour is near any dark ground: black, charcoal,
  navy, deep brown. A darker ground makes it sink, so its Dark needs a
  choice.
- A pick or a user request that leaves the treatment open where the
  options look clearly different, such as two parts that could each carry
  the idea in Clear and Tinted.

Not forks: anything the plan settles by being right (the split into
layers, the boxes, a key), and anything the user already said. When you
are unsure, it is not a fork: build the best one and test the alternatives
yourself for free.

Ask with the AskUserQuestion tool where you have it, else as a numbered
list in your reply, and wait for the answer:

- One question, such as "How should Dark go?", with a header of one word.
- Up to three directions, the one you recommend first with
  "(Recommended)" after its label. Each option's description says what the
  user will see and what it costs: "The tile turns warm white on black and
  the crescent dark grey. Free once the layers are drawn."
- Then one more option, "Build all", with its total cost. Directions that
  differ only in free settings share their drawings, so building them all
  usually costs no more than building one.
- The user can always type an answer instead. Treat it as a direction of
  its own and build it, or the directions it combines with.

If the user dismisses the question without an answer, build the one you
recommend.

## Other parts in Dark

Dark shows the same parts as Default, in other colours. Get there with the
free settings first: the ground's `dark`, and `invert`, `pick` or a `tone`
on a layer. People find an app by its icon, and a picture that changes
when the phone goes dark is harder to find, so a different part in Dark is
a last resort.

Use it only when the user asks for a part that is not there in Default,
such as a moon where the sun was or stars only at night, or when they reject
every recolour you showed. Before any plan that has it, ask, and wait:

- Say what changes: which part becomes what, or which part appears or
  goes away in Dark.
- Say what it costs: one image for each part the image model draws for
  Dark.
- Say what it gives up: the build compares Default with the pick, and
  nothing compares Dark's new parts with anything, so you judge them by eye
  in the Dark render, and the user judges them too.
- Offer the recolour that comes closest as the first option, with
  "(Recommended)", and the different parts as the second.

Only after a yes, put the user's reply in the plan's `consent`, in their
own words, such as `"consent": "Yes, a moon and stars at night"`. Never
write it yourself, and never carry it over from another icon. The command
refuses a plan that has these layers without it.

Two settings make Dark differ:

- `"dark": {"draw": "a pale crescent moon"}` on a layer: the image model
  draws the layer's Dark copy from these words, in the layer's place and
  the pick's style, and the layer's fit places it. One image.
  `--redraw <name>-dark` draws it again.
- `"only": "dark"` on a layer: a part only Dark shows, such as the stars.
  Its `what` describes the new part and where it goes, since the pick does
  not have it, and its `box` puts it there. It cannot be `hero`, `soft` or
  `match`, which act against the pick. `"only": "light"` on a layer hides a
  part in Dark, such as a cloud that is gone at night. Clear and Tinted
  always show what Default shows.

The sheet labels these layers and prints a `CONSENT` line. Judge Dark's own
parts against the user's words, at zoom in Dark, the way you judge the
others against the pick.

When an icon has directions, every build of it is named: give each a short
name that says what it is, such as `keep-black`, `flipped` or `graphite`.
The name becomes its folder and the end of its package's name. Build the
recommended one first, refine it to done, then build each other direction
with its own plan and `--direction <name>`: any layer with the same words
is copied from the first (`SHARED` lines), so only what differs is drawn.
Refine each to done. An icon with one direction builds as `main`, with no
`--direction`. A new direction needs no preview of its own: its first
build makes its tile.

If, once they are built, you would recommend another direction than the
one you recommended in the question, say so in the note and what changed
your mind.

## The plan

```json
{
 "ground": {"keep": "the ruled notebook paper: cream, with pale blue rules and one red margin line near the left edge",
            "remove": "the blue keycap and the shadow it casts on the paper"},
 "dark": "generate",
 "layers": [
  {"name": "keycap", "what": "the blue keycap, its body, sides and dished top",
   "without": "the two white bars on its top; paint the blue dished top where they were",
   "box": [40, 40, 980, 920]},
  {"name": "legend", "what": "the two white horizontal bars printed on the keycap's top",
   "box": [330, 340, 690, 555], "hero": true}
 ],
 "checks": [
  "the keycap sits a little left of centre, its dished top facing up and to the right",
  "two white bars on the top, the upper one longer",
  "one red margin line near the left edge of the paper, crossing the pale blue rules"
 ]
}
```

- `ground`: what the background is (`keep`) and what to take out of it
  (`remove`), shadows the objects cast on it included. The image model
  draws it edge to edge with the objects gone, and it is never moved.
- `dark`: Dark's own ground. Every icon gets one, so Dark always differs
  from Default. Five forms:
  - `"generate"`: the image model draws a night version of the ground, the
    same hues stepped down, for a light or coloured ground: paper, a
    housing, a cover, a sky at dusk. One image.
  - `"dim"`: the ground a step darker, made in code, for a ground that is
    dark already, such as a night scene; the step is small by design. Free.
  - `"invert"`: the ground's lightness flipped in code, its hue kept: white
    becomes near-black, a warm grey stays warm. For a flat mark whose Dark
    flips, together with `invert` on its layers. Free.
  - `{"keep": "the same housing in matte black plastic"}`: the image model
    draws Dark's ground from your words, as an edit of the ground, so its
    layout and grain stay. For a Dark the user describes. One image.
  - `{"tone": "#1c1c1e"}`: the ground recoloured in code to that exact
    colour, its own grain and shading kept. For a Dark the user names by
    colour. Free.

  The first build uses `generate`, `dim` or, for a flipped direction,
  `invert`. Changing only `dark` draws no other layer again. Offer `tone`
  first when a flat colour will do, since it is free and exact.
- `layers`, bottom to top, at most eight. Each has a `name` (`a-z`, `0-9`,
  `-`) and `what` it is, in words the image model can find in the pick.
  `without` says what to leave out of it and what to paint where that was.
  Say where a part is by what is around it ("on the left, under the
  shell"), never by coordinates: the image model edits a larger square
  than the grid's.
- `box`: `[x0, y0, x1, y1]`, the part's extent in the pick, in tile pixels
  read off the grid. Give every layer one. Codex often draws a small part
  bigger and nearer the middle, even on a key, and the fit then places it
  by its box. The fit measures a part by its solid pixels, so box a light,
  a star or a glow by its bright core, not its faint rays or falloff. A box
  costs nothing and can be corrected without a redraw.
- `checks`: the sentences from step 2, at most eight. They cost nothing
  and draw nothing; the sheet prints each as a `CHECK` line every round, so
  you judge the round against them.

What the image model draws each layer on, `key`:

- `magenta`, the default: the layer on flat magenta, keyed out. Codex
  mostly keeps a large part's size and place on it. Use it for every solid
  part.
- `black`: the layer on black, keyed by its brightness. Use it for lights:
  glowing dots, lit filaments, stars, a lamp's light. Codex tends to draw a
  light together with what gives it off, and on black the source's bright
  parts survive the key, so name the source in the light's `without`: "the
  lamp itself, its shade, arm and base; paint pure black where it is".
- `clear`: real transparency, for translucent glass and soft halos that
  neither key can hold. Codex tends to centre and enlarge a part alone on
  transparency, so a `clear` layer must have its `box`. A `clear` layer
  that comes back opaque is drawn again on magenta by itself, for one
  image.

What else a layer can say:

- `shadow`: a shadow another part casts on this one, kept on it, such as
  "the soft shadow the bird casts on the twig's upper side". Without it,
  leaving the bird out of the twig takes the bird's shadow too.
- `hero`: the part that carries the idea, lifted to light grey in Clear and
  Tinted, where a dark layer would show as clear glass. One per icon.
- `soft`: a glow whose strength the fit sets, since the image model draws
  a glow at its own strength.
- `grey`: plain metal. Its colour is taken out after drawing, since Codex
  keeps a colour cast from what surrounds it in the pick.
- `match`: the layer's colour moved onto the pick's after the fit, its
  shading and texture kept. For a part the image model drew a shade off,
  such as a flat #333333 tile that came back #3f3f3f. Free.
- `"dark": "invert"`: the layer's Dark image is its lightness flipped in
  code, hue and shading kept, so a black tile is a warm white in Dark and
  its pale rim a dark grey. Free.
- `"dark": "pick"`: the layer's Dark image takes the pick's colour, its
  shading and texture kept. For a part recoloured in Default at the user's
  request that should look as in the pick in Dark, such as a charcoal disc
  drawn brown to match a brown ground. Free.
- `"dark": {"tone": "#3a3a3c"}`: the layer's Dark image moved onto that
  colour the same way, its shading and texture kept. For a part the user
  wants in another colour in Dark only. Free.
- `"dark": {"draw": "words"}` and `"only"`: see "Other parts in Dark".
  Never without the user's consent.

How to split the subject:

- One layer per thing a person would name: the keycap and its legend, the
  dial's face, its ring of dots and its needle.
- Parts whose places depend on each other are one layer: a row of dots, a
  ring of ticks, a string of lights, two shapes that overlap so that one
  shows only as a sliver around the other. Drawn apart, Codex redraws each
  one upright and whole, and their fit is lost.
- A shadow goes on the layer it falls on, through `shadow`.
- Detail that is part of the ground stays in the ground: the ruled lines of
  the paper, the grain of a housing, engraved ticks, the stars of a sky.

For a small part, enlarge the grid:
`rimlight build <set>/<slug> --stage grid --box X0,Y0,X1,Y1` writes
`src/grid-<box>.png` with a finer grid in tile pixels.

## Judging a round

Read what the round printed first, then look:

- `MATCH`: how much of the tile matches the pick in Default, and up to
  three boxes where a part moved or changed shape. `out/compare.png` puts
  the pick, Default and an overlay of the two side by side. In the
  overlay, red is where the pick is lighter and cyan where Default is, so a
  coloured sliver along an outline means the outline moved. A thin change,
  such as a band that lost its taper, can stay under `MATCH`'s threshold
  and show only as a sliver there: look along every outline in the overlay,
  not only in the boxes.
- `CONTRAST`: each layer against what is behind it, per appearance, and a
  `WARNING` naming the layer, the appearance and where, when a part fades
  into its surroundings.
- `CHECK`: your checks. Hold each one against Default at zoom and say to
  yourself whether it holds.
- `EDGE`: each layer in Default against the pick at full size. `outline`
  is how far its edge wobbles in pixels, `band` how much lighter (+) or
  darker (−) a rim just inside the edge is, `fill` the grain inside,
  `lightness` the inside's median, and `colour ΔE` how far its colour is
  from the pick's. Each is printed beside the pick's own. A `WARNING` names
  a rougher outline, a band, a mottled fill or a colour off the pick's, and
  where.

Then look at `out/review.png`: the pick, the plain assembly of the layers,
the ground and its Dark copy, each layer on a checkerboard, the compare
overlay, and the six appearances in true colour. Zoom with
`rimlight build <set>/<slug> --stage zoom --quadrants`, which writes the
pick and the six appearances at 1024 px, a quadrant a sheet, and with
`--stage zoom --box X0,Y0,X1,Y1` on every `MATCH` box and every `CONTRAST`
or `EDGE` warning. `--scale 1` draws a crop 1:1, and `--rendition Dark
--rendition ClearDark`, the flag once per appearance, limits it to those.
`--stage zoom --outlines` walks every layer's whole outline in 1:1 crops,
the pick beside Default and Dark, and prints a `ZOOM` line per sheet;
`--outline <name>` does one layer.

Judge each appearance:

- In Default, the icon reads as the pick: the same parts in the same
  places, the same outlines, the same palette and light. Small redraw
  differences are expected; a missing part, a moved part, a changed shape
  or a changed idea is not.
- In Dark, the ground is darker and every part still stands apart from
  it: a part that sinks into Dark's ground fails, even if it keeps its
  colour. Nothing of the old ground stays on the subject, and no part
  carries a colour cast from the light ground. When Dark recolours the
  ground, the command gives each layer a Dark copy with the ground's hue
  taken out of it, so a part that reflects an orange housing in Default
  shows no orange over a black Dark; a `FIT` line says which layers got
  one. A part that is itself the ground's colour keeps it. Dark should
  look designed, not like Default with the lights off: a warm subject on a
  cold blue-black, or a black subject on a near-black, fails.
- In Mono, which is Clear Light, Clear Dark, Tinted Light and Tinted Dark,
  the subject reads clearly lighter than the ground, and the detail that
  carries the idea is still there.

Each layer's own drawing is in `gen/<name>.png`, with its prompt beside it
in `.txt`; look there when a layer looks wrong in the assembly.

### Defects at zoom

Icon Composer, the App Store and Finder's large previews show the icon at
1024 px, so a flaw you can see in a 1:1 crop is a flaw in the icon. Every
round that changed a layer, look through every `--outlines` sheet, crop by
crop, pick first, then Default and Dark. Then zoom where the subject meets
the tile's edge and on the inside of every flat or plain part. Anything there that the pick does not have is a defect
to fix:

- an outline that is wavy, scalloped, stepped or jagged where the pick's is
  smooth
- a lighter or darker band, a halo or a coloured fringe along an edge
- mottle, grain, blotches or a cloth-like texture in a part the pick shows
  flat
- a part a shade lighter, darker or warmer than in the pick

Never pass one as "slight", "only at zoom" or "invisible at icon size". If
you saw it and are unsure, it is a defect. Only a difference you can name
as the pick's own, at the same place in the pick's crop, passes.

For a judgement between free options, such as two Dark tones or which part
is hero, run each, look at each, and keep the one that best passes the
above. Say in the note what you tried.

## Fixes

Each fix is a change to the plan, sent again with `--plan-file -`. A layer
whose own words changed is drawn again for one image; `--redraw <name>`
draws one again with the same words, for a drawing that simply came out
wrong. Every drawing a redraw replaces is kept, and
`rimlight build <set>/<slug> --restore <name>` brings it back for free when
the new one came out worse; run again, it swaps back.

| What you see | Fix |
|---|---|
| A part is too big, too small or in the wrong place | Correct its `box` from the grid, free. A `WARNING ... give it a box` line after `FIT` means the same |
| A part is missing, doubled or changed from the pick | Name it more exactly in `what`, with what it is made of and what is around it; or `--redraw` it |
| Two parts lost the way they overlap, or a sliver between them changed width | Make them one layer |
| A part lost its tilt or skew | Say the tilt in `what` ("its top edge rising a little to the right"), or make it one layer with what it overlaps |
| A redraw came out worse than the drawing before | `--restore <name>`, free |
| A layer holds something that belongs to another layer or the ground | Say it in that layer's `without` |
| The ground keeps an object, or its shadow | Name them in `ground.remove` |
| Parts of a row or ring don't line up | Make them one layer |
| A cast shadow is gone | `shadow` on the layer it falls on |
| A glow has a coloured ring or a hard edge | `"key": "black"` |
| An outline is wavy, stepped or scalloped, or has a band, halo or fringe the pick lacks (`EDGE` warning, or seen at zoom) | `"key": "clear"` with its `box`, one image; on a part that is flat or one colour, also say so in `what` ("one flat, even dark grey with a crisp, smooth edge") |
| A part's fill is mottled or textured where the pick's is flat | Say "one flat, even colour with no texture" in `what` and redraw it, one image |
| A part is a shade lighter, darker or warmer than the pick (`EDGE` colour warning) | `"match": true`, free |
| A part keeps a colour cast in Dark that is not the ground's | `"grey": true` if it is metal or another plain grey; else name the colour it should be in `what` and `--redraw` it |
| A glow is too strong or too weak | `"soft": true` |
| The subject vanishes in Clear or Tinted | `"hero": true` on the part that carries the idea |
| A part fades into Dark's ground (`CONTRAST` warning in Dark) | A `tone` lighter or darker than the part, free; for a black, white or grey mark, `invert` on the ground and the layer, free |
| A pale part fades into a pale ground in Default | Name a darker shade in its `what` and redraw it, one image; check that its Dark still reads |
| Dark is too dark, or too close to Default | `"dark": "dim"` or `"dark": "generate"` |
| The user wants another part in Dark, such as a moon for the sun or stars at night | A recolour first; if they still want it, ask as "Other parts in Dark" says, then `"dark": {"draw": ...}` or `"only"` with their `consent` |
| The user wants one part in another colour in Dark only | `"dark": "pick"` on that layer to take the pick's colour, or `"dark": {"tone": "#rrggbb"}`, free |
| The user wants Dark in another colour ("matte black", "deep navy") | `"dark": {"tone": "#rrggbb"}`, free, or `"dark": {"keep": "<their words>"}`, one image |

## What it prints and how it ends

The lines that matter: `PREVIEW` and `GRID`, `PLAN FILE`, `COST N images`,
`SHARED` per drawing copied from another direction, `DRAW` per layer with
`SAVED` or `FAILED`, `FIT` per layer with its scale and shift, `RESTORE`,
`SPENT`, `ICON <package>`, `RENDERS <folder>`, `CONTRAST` per appearance,
`EDGE` per layer, `SHEET <review sheet>`, `MATCH`, `CONSENT`, `CHECK` and, from zoom, `ZOOM`. A
`WARNING` about the plan, a fit, a contrast or an edge names what was found
and goes on. `MOVED` says an older
`build/` folder became `builds/main/`.

| Exit | Meaning | What to do |
|---|---|---|
| 0 | The stages ran | Judge the round |
| 1 | A stage failed | Read the error; fix the plan and run again if it is the plan's, else tell the user |
| 2 | The plan or the options are not valid | Fix what the message lists |
| 3 | The image model refuses every render: a plan's image limit, or an account out of credit | Stop on the best round, and give the user the `LIMIT` line as it is; spend nothing more until it lifts |
| 4 | A stage's input is missing | Run the command the message names |

`rimlight build <set>/<slug> --prune` frees the fitted layers and the
renders once the user is happy; a later run from `fit` makes them again
for free. What the image model drew stays.

## The note

Hand over once, when every direction is done. The app shows each package
with a button to open it in Icon Composer, so the note names each package
and says what it is; keep it short:

- per direction, its package, `builds/<direction>/out/<name>.icon`, and in
  one or two sentences how it reads in Default, Dark and Mono
- what your rounds fixed, in a sentence: "The first round lost the tile's
  tilt; one layer for both squares fixed it."
- what still falls short, if anything: where it is, the fix and its cost
- the images spent, the first builds and your fixes apart; when a
  round cost more than you priced, or the command did something wrong,
  say what the user would see and what it cost in plain words, not the
  command's internals

End with a question only when a choice is left that is the user's to
make, with your recommendation and what the other way costs. Do not list
choices you already settled, and do not end on "what would you like
changed?".
