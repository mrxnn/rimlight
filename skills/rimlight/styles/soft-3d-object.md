# Soft 3D object

One physical thing with real volume, lit like a studio product shot, in a
matte or satin material that looks good to hold. It sits on a flat or softly
graded field, runs off an edge, or is the tile. A set picks one point on a
range from inflated and friendly to quiet and precise. Choose it when the
app's idea is an object you could pick up: a suitcase for trips, a whistle
for training, a heart. Choose Lettermark and wordmark for a letter, Hardware
and skeuomorph for a device's controls, Glass and chrome for a material that
bends light, Mascot for a face and Scene and collage for a place.

## Anchors

- Tripsy: the style in one icon. A chunky orange suitcase in grainy soft-touch plastic, edges rolled wide, two slots pressed in, a graphite handle.
- Benchmark Workout Tracker: a speckled lavender dumbbell at three-quarter view on deep indigo, the object a pale tint of the field.
- Amie: the soft extreme. A white marshmallow form with a slot through it, its contact shadow a deeper coral than the coral field.
- Couple Joy: an inflated heart, pinched where the lobes meet, with no highlight. Hue carries the light, coral where lit and magenta in shadow.
- Longevity Deck: felt cards in red, orange and yellow with a pulse line pressed into the front one, filling the tile top to bottom.
- mymind: an abstract form in dense orange flocking, cropped on flat grey. The texture is the idea.
- Superwhisper: the precise end. A satin graphite Möbius triangle on near-black, its sheen only along the twist.
- On Deck: the tile is the softball. Lime leather grain, red stitches as the only detail.
- Superlist: the tile is a red slab with an S-shaped step through it, drawn by light and shadow alone.

## Rendering standard

Pick one material per set for `[MATERIAL]`: soft-touch matte plastic with a
fine even grain like powder coat, dense flocked velvet, pressed wool felt with
a fine speckle, taut inflated matte vinyl creased only where forms meet, or
satin enamel with a faint sheen. `[FIELD]` is the field colour in hex. Drop
the sentence on saturated surfaces when every surface is pale, and the one on
pale objects when none is.

> Rendering: one physical object in [MATERIAL], modelled in 3D and lit like
> a studio product shot by a professional icon artist, idealized rather than
> photographic. Volumes are full and rounded, every edge rolled over in a
> wide soft radius, with no chamfers, seams, screws or panel lines. Detail is
> pressed into or raised from the same material, never printed on. One large
> soft key light from the upper left, a weak fill from the right; brightness
> falls off smoothly across each curve, lightest on top-facing planes and
> upper edges, with no pinpoint highlight and no reflections. A saturated
> surface leans toward yellow where lit and turns 20 to 30 degrees of hue
> away from yellow in shadow, orange into red, pink into magenta, still
> fully saturated. Recesses are the deepest shade of the surface colour,
> never grey or black. A pale object on a deep field is a desaturated tint
> of the field's hue. The only cast shadow is a short soft contact shadow
> directly beneath, the field's hue a few shades darker. The field is
> [FIELD], flat or a two-stop vertical gradient slightly lighter at the top,
> with no texture, floor, horizon or props. No text.

When the object is the tile, replace the last three sentences with "The
object is the whole tile. Its face runs edge to edge and its outer edge is
the icon's edge. No text."

## Composition

- One relationship per concept. Most of the group sits on a field. About a
  quarter is the tile, like On Deck, Superlist and TripCache's open case.
  The rest runs off one or two edges, like mymind and Poppy.
- On a field the object spans 65 to 80% of the width. Measured: Flighty
  62%, Superwhisper 66%, Amie 71%, Tripsy 74%, Benchmark 76%, Whistle 79%.
  Under 60% it reads as a sticker. Past 85%, crop it.
- Objects with a face sit frontal and centred. Long ones lie on a 30 to 45
  degree diagonal, like Flighty's plane, to gain size.
- A crop hides at least a third of the object and cuts through the body,
  never through the feature that names it. Poppy shows only the top of a
  flower.
- One object, or one object plus one attached part such as a handle, cord or
  clip. Promova's two cushions and a ball are the ceiling.
- The outline alone names the thing. Structural parts run chunkier than
  life, 4% of the width for Whistle's cord and 8% for Tripsy's handle.
  Surface detail can be as fine as it likes, like On Deck's stitches or None
  to Run's braided lace.
- The field does nothing. The most it carries is one context pattern a few
  points of lightness off the field, like the streets behind Placify's pin.

## Colour

Two to four colours plus a neutral, with one hue family over 70% of the
coloured area. Saturated surfaces sit at 90 to 100% saturation and keep it
into shadow. Pale tints sit near 30%. Whites are off-white and usually warm,
like Placify's `#fef6ee`. Three schemes cover the group:

- Saturated object on a pale field tinted toward it. Tripsy is `#fa8000` and
  `#fec03d` on `#f2f1ec`, with graphite `#27282c` for the handle and
  about `#840000` in the slots. Whistle is `#ff171a` and `#ffc323` on `#fceee4`.
- Pale object on a deep field of its own hue. Benchmark's field runs
  `#301890` to `#180048` under a `#a890c0` dumbbell. Amie is white on
  `#fdaaad` with a `#d78085` shadow.
- One hue throughout. Superlist runs from `#ff7848` to `#f01800`.
  Superwhisper is greys from black to `#c0c0c0`.

A complementary accent is allowed if it covers under a tenth of the area,
like On Deck's `#cb2400` stitches on `#a9cd00` lime. The brand colour goes on
the object in the first scheme and on the field in the second.

## Never

- Chamfers, bevels, panel lines, screws or vents. Those belong to Hardware.
- Grey or black shading on a coloured surface. Tripsy's slots go to
  about `#840000`.
- Pinpoint specular highlights, reflections, or glass or chrome as the body.
  Obsidian Web Clipper's small chrome paperclip is the limit.
- Words or numbers on the object unless the brief asks. No anchor has any.
- A floor, horizon, water or sky. CruiseSignal's sea turns its ship into a
  toy render.
- Rows of repeated parts, like CruiseSignal's decks of windows. Count the
  parts before writing them.
- Product-photo lighting: hard rim lights, a spotlight pool on a dark sweep,
  depth of field, dust.
- The 3D-emoji look: candy gloss and a face added to the object. A face
  makes it a Mascot.
- A drop shadow offset down and to the right, a long cast shadow, or a gap
  between the object and its shadow.
- Bloom, neon glow or a coloured halo around the subject.

## Example prompt

    Hush, a white-noise app for sleep. The icon is one foam earplug, the
    kind you roll between your fingers and let expand. Sleep is the thing
    you put in your ears.

    Rendering: one physical object in slow-rebound memory foam, matte, with
    a fine even open-cell grain, modelled in 3D and lit like a studio
    product shot by a professional icon artist, idealized rather than
    photographic. Volumes are full and rounded, every edge rolled over in a
    wide soft radius, with no chamfers, seams, screws or panel lines.
    Detail is pressed into or raised from the same material, never printed
    on. One large soft key light from the upper left, a weak fill from the
    right; brightness falls off smoothly across each curve, lightest on
    top-facing planes and upper edges, with no pinpoint highlight and no
    reflections. Recesses are the deepest shade of the surface colour,
    never grey or black. A pale object on a deep field is a desaturated
    tint of the field's hue. The only cast shadow is a short soft contact
    shadow directly beneath, the field's hue a few shades darker. The field
    is a two-stop vertical gradient from #2a1f7a at the top to #140c45 at
    the bottom, with no texture, floor, horizon or props. No text.

    Composition: the earplug stands upright, tilted 20 degrees clockwise,
    centred, its height about 75% of the icon. A tapered cylinder with a
    domed top and a slightly flared base, and one soft waist where a finger
    pressed it. Nothing else.

    Colour: the earplug is pale lavender, #b3aacf on its lit side and
    #7a70a8 on its shadow side. The contact shadow is #0e0833.

    Transparent background: a real alpha channel outside the icon tile, no
    backdrop, no checkerboard, no cast shadow. Output a PNG with transparency.
