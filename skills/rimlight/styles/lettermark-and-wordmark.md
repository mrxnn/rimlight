# Lettermark and wordmark

The app's name or its initial is the whole icon: one letter, two, or a short
word, in type drawn for this brand, usually two colours, flat or in one
material. It suits short, strong names and brands that own a logotype.
Choose another style when the initial is common and the product offers it
no twist; a bare "N" belongs to a thousand apps.

## Anchors

- Savant is one serif S, black fading to grey at the foot, on off-white.
- Readwise Reader cuts the counter of a white serif R as a folded page
  corner and curls the page off the lower right.
- Buggg is a chunky lowercase b, cream on orange, with ink traps where bowl
  meets stem.
- Notedrafts draws a monoline N, its last stroke fading in under a stylus.
- Whering is one inflated matte chartreuse W on flat lavender.
- iA Writer is only the blue cursor, a quarter in from the left on white.
- Wizz is the name as a die-cut sticker: outline, stacked coloured
  extrusion, border.
- grug is the name in black felt-tip on white, small, full stop included.

## Rendering standard

Pick one sub-family per family of concepts, by the brand's voice. A flat
letter suits tools, reading, finance and quiet brands. A dimensional letter
suits warm, tactile consumer brands. A sticker or badge suits social apps
and games with names of six letters or fewer. Handwriting suits journals,
indie apps and products about writing.

In the bracket, name the type's genre (high-contrast serif, extended
grotesque, rounded sans), weight, case and one distinguishing feature.

> Rendering: a lettermark drawn by a type designer for this brand: [the
> letterform], consistent stroke contrast, smooth curves, crisp corners,
> optically centred. Flat vector colour: one solid letter colour on one
> solid field, matte; at most a two-stop gradient within one hue, lighter at
> the top. No outline, no drop shadow, no bevel, no glow, no texture. The
> letter is printed on the face of the icon, not floating above it, and the
> field runs edge to edge. Edges sharp, like a vector export.

A dimensional letter replaces the "Flat vector colour" and "No outline"
sentences with:

> The letter is one soft object in [inflated matte vinyl | extruded satin
> plastic], broad soft light from the top, a faint highlight on upper edges,
> shading only inside its own curves, a contact shadow no wider than a
> stroke. The field stays flat.

A sticker replaces the same two with:

> The word is a die-cut sticker in flat graphic colour: chunky rounded
> [colour] letters, a heavy [colour] outline, a stacked offset extrusion in
> [colours] below each letter, a thin [colour] border around the word.

Handwriting replaces everything before "The letter is printed" with:

> Rendering: the name written once by hand with a [black felt-tip] on a
> plain [colour] field, one monoline weight, round stroke ends, a slightly
> uneven baseline and letter size, no fill, no shadow, no texture.

## Composition

- The letters are the app's real name or initial, or a glyph the name owns
  (Typo's asterisk is in "Typo*"). Text behind the letter only as cropped
  texture that says "page" (Bookology), never meant to be read.
- A bare letter earns its place through the drawing (Buggg's ink traps).
  Otherwise give it one twist from the app, inside the letter (None to Run's
  N is a shoelace) or acting on it (Notedrafts' stylus). If a rival's
  initial would work as well, it is a monogram, not an icon.
- One letter covers 50 to 60% of the tile each way, its bounding box on the
  centre: Savant 51 by 53%, Buggg 58 by 53%, Schema 52 by 57%. Inflated
  letters run to 70% (Amie).
- A word of up to six letters sits on one line at 70 to 75% of the width
  (Bins 72%, Frenzy 74%). Longer names stack into two lines (JULab) or give
  way to the initial. Two letters lock into one block (Aesty's "ae").
- Bleed only when size is the meaning (Shout Screen's "SH", Palabros' P),
  counter kept whole. Off-centre only when position is the meaning (Typo's
  asterisk sits top right, like a footnote mark).
- A pattern on the field only when it is the idea and close in value
  (Schema's grid, #278efe on #007bfe).

## Colour

Two colours, letter and field; a third only for the twist, four or five in
a sticker. Pair a saturated field with a pale letter, or a pale field with a
dark or saturated one. The pale colour takes the field's hue rather than
pure white: Buggg's letter is #fde6d4 on #ff4c03, Untold's #fff4e6 on
oxblood. The brand colour goes to the field when the letter is pale, to the
letter when the field is neutral (Bins, iA Writer). Gradients hold their
hue: iA Writer's cursor runs #01d6ff to #01adfe.

From the index: Savant #252521, #efeee9, #767571 (ink, paper, the grey of
the fade). Buggg #ff5400, #f7e2d2, #ff9916 (the last warms the field's
bottom fifth). Readwise #222c40, #eaeefa, #5699fe (blue only under the
curl).

## Never

- Text that isn't the name: taglines, "App", labels, fake UI copy.
- A default font with nothing decided.
- Misspelled, mirrored, doubled or missing letters. Spell the word in quotes
  letter by letter with its case, and check every render.
- The letter boxed in a circle, shield or inner square; the tile is the
  frame. A badge only if it is the brand's real logo (GO Club).
- A shadow, glow or bevel added to a flat letter, or two materials at once.
- Chrome or rainbow WordArt, which belongs to Glass and chrome.
- A letter beside a little picture of the product, an F next to a fork.
- A busy field behind a word: halftone, static, starbursts (Comicut, Scoop).
- Generator spacing, with letters touching by accident or one oversized
  for no reason.

## Example prompt

    Stet, a writing app that restores any line you cut. A single lowercase
    "s" (one letter: s, lowercase, nothing else written), a heavy
    high-contrast transitional serif with a ball terminal at the upper
    right, about 55% of the icon's height, centred. Under it, three round
    dots evenly spaced across its width: the proofreader's stet mark, "let
    it stand".

    Rendering: a lettermark drawn by a type designer for this brand: the
    lowercase serif s above, consistent stroke contrast, smooth curves,
    crisp corners, optically centred. Flat vector colour: the letter in ink
    #1d1b18, the dots in proofreader red #d6452c, on a warm paper field
    #f3eee4, matte, with a two-stop vertical gradient within its hue, the
    top 6% lighter. No outline, no drop shadow, no bevel, no glow, no
    texture. The letter is printed on the face of the icon, not floating
    above it, and the field runs edge to edge. Edges sharp, like a vector
    export.

    Transparent background: a real alpha channel outside the icon tile, no
    backdrop, no checkerboard, no cast shadow. Output a PNG with transparency.
