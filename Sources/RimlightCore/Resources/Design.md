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
