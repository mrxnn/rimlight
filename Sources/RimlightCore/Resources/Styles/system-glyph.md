# System glyph

Apple's idiom for its first-party icons, borrowed by the best third-party
utilities: one UI object or simple symbol (a calendar page, a card, a
checkbox, a bubble, an arrow) in rounded shapes, each surface a gentle
two-stop gradient with a thin lighter stroke on its top edge and a short
tinted shadow beneath, on a solid or softly graded tile. Flatter than Soft
3D object, with none of the reflection of Glass and chrome. It suits apps
whose core thing is already an interface object: calendars, lists, notes,
files, finance, messaging. Choose another style when the product has a
physical hero worth modelling, the name is the idea, or the brief wants a
character.

## Anchors

- Things 3: a white checkbox card sunk in a navy frame on a blue tile 10 lightness points darker at the foot. The model for object on tile.
- Fantastical: the calendar page is the tile, a red band on the top quarter, four event squircles each with a lighter top stroke and a glow in its own hue.
- Copilot: one blue arrow on white, 15 points darker at the foot, hue held, a lighter rim and a blue-tinted shadow straight below.
- Goodlinks: a white bookmark on crimson, fading to a crimson tint at its foot. The white-on-colour treatment.
- Denim (2026): a blue card with two pill text lines, its gradient a 20 degree turn from cyan to azure at even lightness.
- Persist: the list card rises from the bottom edge, text as pale bars, status dots in plain iOS system colours.
- Gentler Streak: one orange blob on white, flat face, thin top rim, a slab edge. The style at its most reduced.
- Share Schedule: four white cells on red, pure white at the top and pinker lower down, two of them joined by a liquid bridge that carries the idea.
- Flighty: a white airliner on charcoal, the dark-tile variant.
- One Is Not None: four colour-coded quadrants on near-black. Several hues, each in its own shape.

## Rendering standard

Paste it whole, keeping one of the three tile options and naming its colours.

> Rendering: an iOS system icon in the manner of Apple's first-party icons,
> smooth vector surfaces with gentle depth. One UI object or simple symbol,
> seen straight on, built from rounded rectangles, circles and pills with
> generous continuous corners and round stroke caps. Each coloured surface
> has a two-stop vertical gradient: the top 12 to 15 lightness points
> lighter than the bottom with the hue held, or a 15 to 20 degree hue shift
> top to bottom at even lightness. White parts are pure white in their
> upper half and fade to a pale tint of the tile colour at the foot. A
> highlight stroke about 1% of the icon's width traces every shape,
> strongest along its top edge: the shape's own colour lifted 6 to 10
> lightness points, never pure white. Light from straight above. Each
> object casts one soft contact shadow directly beneath it, tinted with its
> own hue, gone within 5% of the icon's width. Inner parts sit a few pixels
> proud or recessed, and text is drawn as rounded bars. No texture, noise,
> reflections, specular hotspots or perspective. The tile is one colour,
> 10 to 14 lightness points lighter at the top, or white fading to a pale
> tinted grey, or near-black fading darker.

## Composition

The subject meets the tile in one of three ways. Most often it sits on the tile,
centred on both axes and spanning 55 to 80% of the tile's width, two thirds
typical: Copilot 64%, Denim 71%, Goodlinks 57%, Things 79% with its frame.
Below half the width it reads as a sticker. Or the object is the tile: a
calendar page gives its header band the top 25 to 32% (Fantastical 25,
Daylish 28, Shift Day 32), closes it with a darker seam and a short shadow
onto the page, and sets three to six parts on a faint grid below. Or the
object enters from one edge and is cropped by it: Persist's card starts 28%
down and runs off the bottom. Keep at least half of it in view.

One object. Inside it, two to six repeated parts of one kind (bars, cells,
pills) and at most one accent, such as a check or a star. One compact
silhouette, corner radii around 15 to 22% of each shape's short side. Detail
lives inside the object; a tile pattern stays within a few lightness points
of the tile, like Copilot's diagonal dashes. Thickness shows as an edge
only: Things' card has two thin grey layers under it, Gentler Streak a side
wall 10 points darker than the face and up to 8% of the width. Rotate only
as a gesture, like Moneycoach's cards at 45 degrees.

## Colour

One hue plus white. Either the tile carries the hue and the subject is white
tinted toward it (Goodlinks, Invoice Maker, Share Schedule), or the tile is
white and the subject carries the hue (Copilot, Gentler Streak, Denim), or
the tile is near-black and the subject is bright (Flighty, AI Flow,
Widgetsmith). Hues sit at iOS system strength, 80 to 100% saturation and 47
to 65% lightness: blue #007aff, red #ff3b30, yellow #ffcc00, green #34c759,
orange #ff9500, purple #af52de. The brand colour goes on whichever surface
is coloured. White tiles end in a grey tinted toward the subject, Copilot's
at #d8e1ee. Dark tiles are cool neutrals, Flighty's running from #25262a
to #0e0e10, and on them the top stroke rises to 20 points. Use several hues
only when the object is colour-coded, each in its own shape at matched
saturation and lightness.

- Goodlinks: #e22952 #fbd6dd #fd87a1 #e49cab. One crimson in four values.
- Copilot: #227bf8 #eaedf2 #a5c0e2 #60bdff. One blue on cool white.
- Things 3: #057fed #cdd2df #162a5e #5a6069. Blue, its own navy, slate for the check.
- Fantastical: #f4362e #f8f1e5 #ffc521 #e3a097. Red band, warm white page, event colours.

## Never

- Pure white strokes on coloured shapes, or strokes past 1.5% of the width.
- Specular hotspots, reflections, frosted or refracting glass, chrome.
- Grey shadows offset to one side, or long cast shadows.
- Perspective, three-quarter views, inflated or rounded-over volume.
- Texture of any kind: paper grain, felt, noise, brushed metal.
- Letters, numbers or fake UI copy on the object. Ask for rounded bars; the generator fills any card it can with gibberish.
- Outline-only line glyphs. Exemplars fill their shapes, and Things' check is a stroke 7% of the width.
- More than two gradient stops, or a hue swing past 60 degrees on one surface.
- Sparkles, floating dots, a second object, a scene behind the subject.
- Screenshots or literal UI: status bars, real controls, accurate type.

## Example prompt

    An app icon for Tabby, an app that splits a restaurant bill between
    friends. A paper receipt torn into two halves standing side by side with
    a narrow gap, together spanning about two thirds of the icon's width,
    centred. Each half has a zigzag torn foot, three pale green-grey rounded
    bars for the lines of the bill and one shorter deep green bar for the
    total. No letters, numbers or currency signs.

    Rendering: an iOS system icon in the manner of Apple's first-party
    icons, smooth vector surfaces with gentle depth. One UI object or simple
    symbol, seen straight on, built from rounded rectangles, circles and
    pills with generous continuous corners and round stroke caps. Each
    coloured surface has a two-stop vertical gradient: the top 12 to 15
    lightness points lighter than the bottom with the hue held, or a 15 to
    20 degree hue shift top to bottom at even lightness. White parts are
    pure white in their upper half and fade to a pale tint of the tile
    colour at the foot. A highlight stroke about 1% of the icon's width
    traces every shape, strongest along its top edge: the shape's own colour
    lifted 6 to 10 lightness points, never pure white. Light from straight
    above. Each object casts one soft contact shadow directly beneath it,
    tinted with its own hue, gone within 5% of the icon's width. Inner parts
    sit a few pixels proud or recessed, and text is drawn as rounded bars.
    No texture, noise, reflections, specular hotspots or perspective. The
    tile is green, #3fd872 at the top falling to #22b858 at the bottom, hue
    held.

    Transparent background: a real alpha channel outside the icon tile, no
    backdrop, no checkerboard, no cast shadow. Output a PNG with transparency.
