# Mascot

A character or a face is the icon: cartoon, drawn rather than modelled, flat
or softly shaded, usually cropped so close that the face fills the tile. It
suits apps that keep the user company: habits, health, journaling, study,
kids, pets, food, games, couples, AI companions. About a third of the
corpus's 33 Health & Fitness icons are mascots and none of its 9 Finance
icons. Where trust or precision is the product (finance, security, developer
and pro tools, medical) a face reads as a toy. The exceptions are a brand
that already owns a creature (RCKit borrows RevenueCat's cat) and an app
whose voice is the joke (Uncle Rudy roasts you).

## Anchors

- Duolingo: the face crop at its purest. Head wider than the tile, each eye a
  third of the width, no mouth.
- BurnBuddy: the same crop on a crocodile, every feature in one deep teal ink.
- Trendy: the soft-shaded gummy face; lids cut flat across the top make the
  smirk.
- Water Alarm: the peek. A hippo enters from one corner, its water drop holds
  the other.
- Pom: an apple with a face, bleeding off two edges, its features in a dark
  shade of its own red.
- Tiimo: the whole character, centred and calm, both pupils glancing sideways.
- Slop Detective: the graphic version. Thick black outline, four flat colours,
  half out of frame.
- Fatty Cat: hand-drawn at its minimum, two charcoal circles and a "w" on
  crumpled paper.

## Rendering standard

> Rendering: a cartoon character by a professional character designer, clean
> flat vector shapes with smooth curved edges. One big rounded body, its
> outline broken by a few parts (ears, horns, a tuft, a stem), short limbs or
> none, no outline around it. Every feature in one dark ink, a deep shade of
> the body's hue, never pure black. Large simple eyes (dots, vertical ovals, or
> white ovals with dark pupils), one small white catchlight high in each
> pupil, both pupils turned the same way; the mouth one rounded stroke, an open
> D with a tongue, or nothing. Light from the upper left shows only as one
> lighter flat plane on the body: no gradients on features, no specular
> highlights, no rim light, no texture, no cast shadow. The character is large
> and runs off the edges or fills most of the icon. Background one flat colour
> or a two-stop vertical gradient of one hue, top about 10% lighter, no scene,
> no ground. Colours exactly as listed, matte.

Other finishes replace the first sentence and the light sentence:

- Soft-shaded (Trendy, GenK, Imposter, Dogo): "Soft gummy-vinyl finish: a
  broad soft highlight on each mass's upper left, about 15% darker toward the
  lower right, a faint light rim on top edges, features slightly inset; no
  specular dots, no subsurface glow, no fur."
- Hand-drawn (Bears Gratitude, Me+, Fatty Cat): "One black brush line about 2%
  of the icon's width, rounded ends, slight wobble, flat fills a little off the
  line, no shading."
- Pixel (Pixel Pals, Kumo): "A pixel-art sprite about 22 cells across, a
  one-cell black outline, no anti-aliasing, three to five flat colours."

## Composition

Each concept takes one of four relationships to the tile and names it.

- Face crop. The head runs off at least two edges, the eye line sits 45 to 60%
  down, each eye is 25 to 40% of the width and less than one eye-width from
  the other (Duolingo, BurnBuddy, Trendy, Mist).
- Peek. The character enters from an edge or corner, cropped by the bottom,
  covering 60 to 90% of the width; the empty side holds the prop or nothing
  (Water Alarm, Slop Detective, Dogo, Pom).
- Whole character, centred at 75 to 80% of the width, standing on nothing
  (Tiimo, RCKit, Octoglance, Yours Always).
- Object with a face. The app's own object at 60 to 80% of the width, the face
  on its largest flat surface, its own parts used as features where they fit,
  as Solos's tape reels are its eyes (Caffeine Alyx, Clipbud, Jomo).

One character and at most one prop, and the prop is the app's verb: Dogo's
leash, GenK's book, Water Alarm's drop. A cast works only packed into one
silhouette, like Imposter's five beans. Detail lives in the face; the body
stays flat or tone on tone. The character separates from the ground by
value (white on red in RCKit) or by a near shade of its own hue (Duolingo,
BurnBuddy).

A good face changes one thing for its expression: the gaze (Tiimo, Numo, Slop
Detective), the lid (Trendy, Imposter) or closed arcs for joy (Pom, Caffeine
Alyx, Dogo). Brows are one stroke, blush a flat disc under the outer eye
corner. Most have a small mouth or none; the eyes do the work.

## Colour

Two or three hues, one dark ink, white. One register per set: high chroma for
loud apps (Pom's #fd5c62) or pastel for calm ones (Me+'s #c7abfe on
#fbf5f5). The brand colour goes on the body, or on the ground when the
character is white. The ink is a deep shade of the subject's hue or a warm
near-black (Pom #782d28, Water Alarm #15313b, Tiimo #2f2828). Pure black
belongs to the graphic and hand-drawn finishes, as in Slop Detective's
#181818 on #ffa818. At most one warm accent, the size of a beak or a tongue.

- Duolingo: #7dc100 ground, #8ee001 head, #4e4d49 pupils. Two greens a step
  apart, grey ink, a yellow beak as the accent.
- Reflectly: #e7f1fc, #1f2e51, #e58100. Pale ground, navy ink, the orange
  tongue the only saturated colour.
- Water Alarm: #00c090, #18d8c0, #183030, blush #f95e42. Neighbouring greens,
  one complementary accent.

## Never

- Pixar-style 3D: subsurface skin, fur strands, irises and lashes, depth of
  field.
- A small whole character floating in an empty field.
- A scene: sky, floor, horizon, a room.
- A second prop, or confetti, sparkles and floating hearts.
- Text, a name, a number, a speech bubble with words.
- Pure black features on a flat coloured character.
- Star or heart pupils, several catchlights per eye, hatched blush.
- Eyes of two sizes or two gazes, extra fingers, extra limbs. Hands are
  four-fingered mitts, drawn only when the idea needs one.
- A specular dot on every shape, or a rim light.
- A die-cut white sticker border with a drop shadow.
- A yellow smiley or an emoji standing in for a character.
- Outlines on some parts and not others.

## Example prompt

    App icon for Levain, an app that reminds you to feed your sourdough
    starter. The starter is a pet that gets hungry. In a peek composition, a
    plump blob of risen dough rises from the bottom edge across about 70% of
    the width, a soft dome with two small rounded peaks for ears and three
    bubbles in its surface. In the upper middle, two white oval eyes set
    close, both pupils turned up and to the right toward the empty corner, and
    a small open D-shaped mouth with a tongue, waiting to be fed. No prop.

    Rendering: a cartoon character by a professional character designer, clean
    flat vector shapes with smooth curved edges. One big rounded body, its
    outline broken by a few parts (ears, horns, a tuft, a stem), short limbs
    or none, no outline around it. Every feature in one dark ink, a deep shade
    of the body's hue, never pure black. Large simple eyes (dots, vertical
    ovals, or white ovals with dark pupils), one small white catchlight high
    in each pupil, both pupils turned the same way; the mouth one rounded
    stroke, an open D with a tongue, or nothing. Light from the upper left
    shows only as one lighter flat plane on the body: no gradients on
    features, no specular highlights, no rim light, no texture, no cast
    shadow. The character is large and runs off the edges or fills most of the
    icon. Background one flat colour or a two-stop vertical gradient of one
    hue, top about 10% lighter, no scene, no ground. Colours exactly as
    listed, matte.

    Colours: dough #f2ddb8, its lighter upper-left plane #faebd0; ink #6b4423
    for pupils, mouth and bubble rims; eye whites #fffdf8; tongue #ef8a7e;
    background a two-stop vertical gradient of terracotta #d9673b, top about
    10% lighter. No text.

    Transparent background: a real alpha channel outside the icon tile, no
    backdrop, no checkerboard, no cast shadow. Output a PNG with transparency.
