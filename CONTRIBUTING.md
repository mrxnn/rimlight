# Contributing

This file is for anyone who changes the `rimlight` package. It says how to
build and test it, how a change reaches people, and the rules every change
follows.

## Build and test

You need macOS 26 and Swift 6.2.

```sh
swift build && swift test
```

The tests render nothing and make no network call. They run a fake `codex`
script, and a stub `URLProtocol` answers the image APIs. So they need no
ChatGPT sign-in and no API key. CI runs the same two commands on GitHub's
`macos-26` image, from `.github/workflows/ci.yml`.

## How a change ships

The package has no release of its own today. It ships inside the Rimlight
app. The app pins a revision of this repo and carries its own `rimlight`.
At launch, the app replaces the `rimlight` it installed when its own copy
has a higher version.

So every change that should reach people does two things in the package:

- It raises `Rimlight.version` in `Sources/RimlightCore/RimlightCore.swift`.
  Without that, the app never replaces the installed copy.
- It adds an entry to `CHANGELOG.md`.

`scripts/release` builds a signed, notarized archive of the command, and
`packaging/rimlight.rb` is a Homebrew formula template. Neither is used
today. They are kept for a possible public release later.

## Image models

`generate`, `fix` and `build` render through an `ImageGenerator`, in
`Sources/RimlightCore/Generator/ImageGenerator.swift`. They never name a
provider. `ImageGenerators.make` picks the generator from `image.json` and
the command's flags:

- `CodexImageGen` runs `codex exec`.
- `HTTPImageGen` speaks OpenAI's and OpenRouter's Images APIs. The custom
  provider points it at another address.

`RenderNormalizer` turns every API image into the 1254 px square PNG that
the rest of the code measures in.

A new provider is a dialect of `HTTPImageGen` when its API copies one of
the two. Otherwise it is a generator of its own. Either way, it comes with
tests on canned replies, like `HTTPImageGenTests`.

Keys never reach the code as arguments or files. `KeySource` asks the
running Rimlight app over a Unix socket. The app checks the caller's code
signature, then hands over the key from its Keychain item. Without the app,
the only other source is `RIMLIGHT_<PROVIDER>_API_KEY` in a terminal. To
try a model on your own key:

```sh
export RIMLIGHT_OPENROUTER_API_KEY=...
rimlight image --set openrouter --model <slug>   # rimlight image --set codex goes back
rimlight image                                   # prints key=RIMLIGHT_OPENROUTER_API_KEY
```

The skill and the styles were tuned on Codex's image model. A change made
for another model comes with renders from both.

## The skill text

The agent reads these files, all under `Sources/RimlightCore/Resources/`:

- `Instructions.md`, the fixed instructions.
- `Design.md`, the design process.
- `Adaptive.md`, the index of the styles.
- `Build.md`, the guide to `rimlight build`.
- `Styles/`, the eight style files.

Golden tests pin this text byte for byte. The golden is the committed
skill in `skills/rimlight/`:

- `SKILL.md` is the default skill. It is `Instructions.md`, `Design.md`
  and `Adaptive.md` put together.
- `build.md` is `Build.md`.
- `styles/` is `Styles/`.

The committed `SKILL.md` names the styles folder and the build guide by the
relative paths `styles` and `build.md`. An install writes their absolute
paths instead.

A change to any of the text updates the golden in the same commit. Never
edit the golden by hand. Make it from the code:

```sh
RIMLIGHT_UPDATE_GOLDEN=1 swift test --filter GoldenSkillTests
```

The commit message says why the text changed. Reviewers read it as a
change to prose.

A style change comes with renders of the same prompts from before and
after the change, in the pull request. The standards were tuned on Codex's
image model, and only renders show what an edit did to them.

`GoldenCodexTests` pins three strings as literals: the `codex exec`
arguments, the tile template line and the transparency fix prompt. Change
them on purpose or not at all.

Codex's installed skill gets one extra section, `SkillHarness.codexNote` in
`Sources/RimlightCore/Skill/SkillHarness.swift`. Claude Code's skill never
gets it.

## Code and commits

- One finished piece per commit. Each commit builds clean, and its tests
  pass.
- Keep "why" comments short.
- `RimlightCore` never imports AppKit or UIKit.
- Every write under `.rimlight/` goes through `ProjectStore`. It writes a
  temp file and renames it into place. A read-modify-write takes the
  project's lock.
- A change to the files on disk updates `docs/FORMAT.md` in the same
  commit. It raises the schema number when an older reader would misread
  the result.
