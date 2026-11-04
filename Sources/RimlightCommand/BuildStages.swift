import Foundation
import RimlightCore
import Synchronization

/// The work of each stage of `rimlight build`, for every icon of one run. The rules come from the trial in
/// Rimlight-Research/layer-trial: every layer is an edit of the pick; a layer on a key keeps its place; the ground
/// is never moved; Dark always gets its own ground.
struct BuildStages {
    let target: Build.Target
    let say: @Sendable (String) -> Void
    /// The image model draws render with; an error stops the draw stage, not the build.
    var renderer: Result<Renderer, any Error> = .failure(ImageFailure.unavailable("no image model was set up for this build"))

    /// Images drawn at once. The trial drew three at a time; four keeps a Codex build near two minutes.
    static let parallelImages = 4
    /// Dark's ground for a ground that is dark already: a step darker, the same ground.
    static let dimFactor: Float = 0.8
    static let groundName = "ground"
    static let groundDarkName = "ground-dark"

    private func file(_ id: String, _ path: String) -> URL { target.layout.file(id, path) }
    private func exists(_ id: String, _ path: String) -> Bool { FileManager.default.fileExists(atPath: file(id, path).path) }

    func plan(_ id: String) throws -> LayerPlan {
        let data = try Data(contentsOf: file(id, "plan.json"))
        return try PlanFile.check(data).plan
    }

    // MARK: Inputs

    /// What a stage needs that is not there, as a message naming the command that makes it.
    func missingInput(_ stage: String, redraw: [String], planStored: Bool = true) -> String? {
        func fix(_ id: String, _ earlier: String) -> String { "run `\(target.command(id)) --stage \(earlier)` first" }
        for id in target.ids {
            switch stage {
            case "preview":
                let pick = target.layout.pick(id)
                if !ProjectStore.isRegularFile(pick.path) { return "\(id): no pick at \(pick.path)" }
            case "draw":
                if !exists(id, "src/ref.png") { return "\(id): no tile yet; \(fix(id, "preview"))" }
                if planStored, !exists(id, "plan.json") {
                    return "\(id): no plan yet; write one and send it with `\(target.command(id)) --plan-file -`"
                }
                if let plan = try? plan(id) {
                    let names = Set([Self.groundName, Self.groundDarkName] + plan.layers.flatMap(Self.drawings))
                    if let unknown = redraw.first(where: { !names.contains($0) }) {
                        return "\(id): the plan has no layer \"\(unknown)\" to redraw"
                    }
                }
            case "fit":
                if !exists(id, "src/tile.png") { return "\(id): no tile yet; \(fix(id, "preview"))" }
                guard let plan = try? plan(id) else { return "\(id): no valid plan.json; send one with --plan-file" }
                var needed = [Self.groundName] + plan.layers.flatMap(Self.drawings)
                if plan.dark.drawn { needed.append(Self.groundDarkName) }
                if let name = needed.first(where: { !exists(id, "gen/\($0).png") }) {
                    return "\(id): \(name) is not drawn yet; \(fix(id, "draw"))"
                }
            case "pack":
                if !exists(id, "layers/fit.json") { return "\(id): no fitted layers yet; \(fix(id, "fit"))" }
            case "sheet", "zoom":
                if !exists(id, "out/assembled.png") { return "\(id): no package yet; \(fix(id, "pack"))" }
            case "grid":
                if !exists(id, "src/tile.png") { return "\(id): no tile yet; \(fix(id, "preview"))" }
            default: break
            }
        }
        return nil
    }

    // MARK: preview

    /// The pick's tile at 1024 px, the 1254 px square the image model edits, and the grid the agent places boxes on.
    func preview(_ ids: [String]? = nil) throws {
        for id in ids ?? target.ids {
            let pick = try LayerImage.read(target.layout.pick(id))
            let made = try LayerImage.tile(fromPick: pick)
            try FileManager.default.createDirectory(at: file(id, "src"), withIntermediateDirectories: true)
            try made.tile.write(to: file(id, "src/tile.png"))
            try made.reference.write(to: file(id, "src/ref.png"))
            try made.tile.gridOverlay(step: 32, labelEvery: 128).write(to: file(id, "src/grid.png"))
            say("PREVIEW \(id): \(file(id, "src/tile.png").path)")
            say("GRID \(file(id, "src/grid.png").path)")
        }
    }

    /// Previews each icon that has a pick but no tile in this direction: free, and what every later stage reads.
    /// A first build of a named direction stopped at "no tile yet" before.
    func previewMissing() throws {
        let missing = target.ids.filter {
            ProjectStore.isRegularFile(target.layout.pick($0).path) && !(exists($0, "src/ref.png") && exists($0, "src/tile.png"))
        }
        if !missing.isEmpty { try preview(missing) }
    }

    /// The `SPENT` line: every drawing the image model has made for the icon, in every direction, kept or replaced. A drawing
    /// one direction copied from another is the same file, so it counts once. The agent added up quiet-pick's COST
    /// lines to 9 when 7 were drawn, and stopped short of its budget.
    func spentLine(_ id: String) -> String {
        let fm = FileManager.default
        var drawn = Set<String>()
        for name in Set(target.layout.directions(id) + [target.layout.direction]) {
            let gen = target.layout.folder(id, direction: name).appending(path: "gen", directoryHint: .isDirectory)
            for dir in [gen, gen.appending(path: "rounds", directoryHint: .isDirectory)] {
                for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasSuffix(".png") {
                    if let hash = try? BuildRecord.sha256(of: dir.appending(path: f)) { drawn.insert(hash) }
                }
            }
        }
        return "SPENT \(id): \(drawn.count) image\(drawn.count == 1 ? "" : "s") drawn for this icon so far, every direction together"
    }

    // MARK: draw

    struct DrawJob: Sendable {
        let id: String
        let name: String
        /// The layer's own words, kept in `<name>.sig` once drawn: a change means a redraw. Not the whole prompt,
        /// which lists the other layers to leave out, so editing one layer redrew its neighbours too.
        let signature: String
        /// What the image model is sent, kept in `<name>.txt`.
        let sent: String
        let ref: URL
        let out: URL
        /// The key the drawing is on, kept in `<name>.key` for the fit.
        let key: LayerPlan.Key?

        var promptFile: URL { out.deletingPathExtension().appendingPathExtension("txt") }
        var signatureFile: URL { out.deletingPathExtension().appendingPathExtension("sig") }
        var keyFile: URL { out.deletingPathExtension().appendingPathExtension("key") }
        var logFile: URL { out.deletingPathExtension().appendingPathExtension("log") }
    }

    /// A drawing another direction of the icon has already, copied instead of drawn: the same layer, drawn from the
    /// same words and the same `src/ref.png`.
    struct Shared {
        let job: DrawJob
        /// The direction it comes from, and that direction's `gen/`.
        let from: String
        let gen: URL
    }

    /// Draws every layer whose drawing is missing, whose prompt changed, or that `redraw` names; Dark's ground
    /// after the ground, since it is an edit of it; then any clear layer that came back opaque, again on
    /// magenta. A layer another direction of the icon has drawn from the same words is copied from there instead,
    /// and COST counts only what the image model draws. Returns the COST line and the exit status: 3 on a limit.
    func draw(redraw: [String], dryRun: Bool, plan pending: LayerPlan? = nil) throws -> (cost: String, status: Int32) {
        let fm = FileManager.default
        var first: [DrawJob] = []
        var dark: [DrawJob] = []
        var shared: [Shared] = []
        for id in target.ids {
            let plan = try pending ?? plan(id)
            let ref = file(id, "src/ref.png")
            func job(_ name: String, _ prompt: String, _ signature: String, ref: URL, key: LayerPlan.Key?) -> DrawJob {
                DrawJob(id: id, name: name, signature: signature, sent: prompt, ref: ref, out: file(id, "gen/\(name).png"), key: key)
            }
            func stale(_ j: DrawJob) -> Bool {
                redraw.contains(j.name) || !fm.fileExists(atPath: j.out.path)
                    || !Self.sameSignature(try? String(contentsOf: j.signatureFile, encoding: .utf8), j.signature)
            }
            // read only when a layer is stale, since it compares each direction's ref.png with this one's
            var others: [(name: String, gen: URL)]?
            /// The first other direction with this layer drawn from the same words, on `ground` for Dark's ground;
            /// none for a layer `redraw` names, which asks the image model for a new drawing.
            func donor(_ j: DrawJob, ground: URL? = nil) -> Shared? {
                guard !redraw.contains(j.name) else { return nil }
                if others == nil { others = otherDirections(id) }
                for other in others ?? [] {
                    let png = other.gen.appending(path: "\(j.name).png")
                    let sig = other.gen.appending(path: "\(j.name).sig")
                    guard ProjectStore.isRegularFile(png.path),
                        Self.sameSignature(try? String(contentsOf: sig, encoding: .utf8), j.signature)
                    else { continue }
                    if let ground {
                        let theirs = other.gen.appending(path: "\(Self.groundName).png")
                        guard fm.contentsEqual(atPath: theirs.path, andPath: ground.path) else { continue }
                    }
                    return Shared(job: j, from: other.name, gen: other.gen)
                }
                return nil
            }
            let ground = job(Self.groundName, LayerPrompts.ground(plan), Self.signature(ground: plan), ref: ref, key: nil)
            // the ground this direction will have, and whether the image model draws it
            var groundNow = ground.out
            var groundChanges = false
            var groundDrawn = false
            if stale(ground) {
                groundChanges = true
                if let s = donor(ground) {
                    shared.append(s)
                    groundNow = s.gen.appending(path: "\(Self.groundName).png")
                } else {
                    first.append(ground)
                    groundDrawn = true
                }
            }
            for layer in plan.layers {
                var jobs = [job(layer.name, LayerPrompts.layer(plan, layer), Self.signature(layer, plan), ref: ref, key: layer.key)]
                if case .draw(let words) = layer.dark {
                    // an edit of the pick like the layer, so it is drawn beside it, not after
                    jobs.append(job(Self.darkName(layer.name), LayerPrompts.layerDark(plan, layer, words: words),
                        Self.signature(layer, darkWords: words), ref: ref, key: layer.key))
                }
                for j in jobs where stale(j) {
                    if let s = donor(j) { shared.append(s) } else { first.append(j) }
                }
            }
            if let prompt = LayerPrompts.darkGround(plan) {
                let j = job(Self.groundDarkName, prompt, Self.signature(dark: plan), ref: ground.out, key: nil)
                // Dark's ground is an edit of the ground: another direction's fits only an identical ground
                if groundChanges || stale(j) {
                    if !groundDrawn, let s = donor(j, ground: groundNow) { shared.append(s) } else { dark.append(j) }
                }
            }
        }
        let all = first + dark
        let cost = "COST \(all.count) image\(all.count == 1 ? "" : "s")"
            + (all.isEmpty ? "" : " (\(all.map { "\($0.id)/\($0.name)" }.joined(separator: ", ")))")
        say(cost)
        if dryRun {
            for s in shared { say("  would share \(s.job.id)/\(s.job.name) from \(s.from)") }
            for j in all { say("  would draw \(j.id)/\(j.name)") }
            // quiet-pick's round priced 2 and drew 3: its clear tile came back opaque
            if first.contains(where: { $0.key == .clear }) {
                say("  each clear layer that comes back opaque is drawn again on magenta, 1 more image")
            }
            return (cost, 0)
        }
        try share(shared)
        var status = make(first)
        if status == 0 { status = make(dark) }
        guard status == 0 else { return (cost, status) }

        // a clear layer Codex gave a painted checkerboard instead of transparency: drawn again on magenta, which
        // the trial found keeps the layer's place too
        var again: [DrawJob] = []
        for id in target.ids {
            let plan = try plan(id)
            for layer in plan.layers where layer.key == .clear {
                var redo = [(layer.name, Self.signature(layer, plan), LayerPrompts.layer(plan, layer, key: .magenta))]
                if case .draw(let words) = layer.dark {
                    redo.append((Self.darkName(layer.name), Self.signature(layer, darkWords: words),
                        LayerPrompts.layerDark(plan, layer, words: words, key: .magenta)))
                }
                for (name, signature, sent) in redo {
                    let out = file(id, "gen/\(name).png")
                    guard first.contains(where: { $0.id == id && $0.name == name }),
                        let image = try? LayerImage.read(out), !image.hasAlpha
                    else { continue }
                    again.append(DrawJob(
                        id: id, name: name, signature: signature, sent: sent, ref: file(id, "src/ref.png"), out: out, key: .magenta))
                }
            }
        }
        if !again.isEmpty {
            say("COST \(again.count) more image\(again.count == 1 ? "" : "s") (\(again.map { "\($0.id)/\($0.name)" }.joined(separator: ", ")) "
                + "came back opaque, drawn again on magenta)")
            status = make(again)
        }
        return (cost, status)
    }

    /// The icon's other directions whose `src/ref.png` is this one's, `main` first: a direction previewed from
    /// another pick drew other pictures.
    private func otherDirections(_ id: String) -> [(name: String, gen: URL)] {
        let ref = file(id, "src/ref.png")
        guard ProjectStore.isRegularFile(ref.path) else { return [] }
        return target.layout.directions(id).compactMap { name in
            guard name != target.layout.direction else { return nil }
            let folder = target.layout.folder(id, direction: name)
            let theirs = folder.appending(path: "src/ref.png")
            guard FileManager.default.contentsEqual(atPath: theirs.path, andPath: ref.path) else { return nil }
            return (name, folder.appending(path: "gen", directoryHint: .isDirectory))
        }
    }

    /// Copies each shared drawing and its files into this direction's `gen/`. The drawing it replaces goes to
    /// `gen/rounds/`, as a redraw's does, so `--restore` brings it back.
    private func share(_ shared: [Shared]) throws {
        let fm = FileManager.default
        for s in shared {
            let gen = s.job.out.deletingLastPathComponent()
            try fm.createDirectory(at: gen, withIntermediateDirectories: true)
            try Self.keepRound(of: s.job.name, in: gen)
            for ext in Self.drawingFiles {
                let from = s.gen.appending(path: "\(s.job.name).\(ext)")
                let to = gen.appending(path: "\(s.job.name).\(ext)")
                // a failed draw's log, or a key with no drawing, may be left over
                try? fm.removeItem(at: to)
                // copyItem clones on APFS, so the copy takes no more disk
                if fm.fileExists(atPath: from.path) { try fm.copyItem(at: from, to: to) }
            }
            say("SHARED \(s.job.id)/\(s.job.name) from \(s.from)")
        }
    }

    /// Draws `jobs` through the image model, `parallelImages` at a time, under job markers in the store. No more
    /// start once the model refuses renders for a limit.
    private func make(_ jobs: [DrawJob]) -> Int32 {
        guard !jobs.isEmpty else { return 0 }
        let markers: [String?] = target.store.map { store in
            Jobs.begin(store, images: jobs.map { job in
                let (set, slug) = Build.split(job.id)
                return (set, slug, target.titles[job.id] ?? slug)
            }, mode: .build)
        } ?? Array(repeating: nil, count: jobs.count)
        defer { markers.forEach(Jobs.end) }

        let generator: any ImageGenerator
        let model: String?
        switch renderer {
        case .success(let r): (generator, model) = (r.generator, r.model)
        case .failure(let error):
            say("ERROR: \(error)")
            return 1
        }
        let limit = Mutex<RenderLimit?>(nil)
        let failed = Mutex(0)
        let next = Mutex(0)
        let say = self.say
        DispatchQueue.concurrentPerform(iterations: min(Self.parallelImages, jobs.count)) { _ in
            while true {
                let index: Int? = next.withLock { n in
                    guard n < jobs.count, limit.withLock({ $0 }) == nil else { return nil }
                    defer { n += 1 }
                    return n
                }
                guard let index else { return }
                let job = jobs[index]
                defer { Jobs.end(markers[index]) }
                switch Self.make(job, generator: generator, model: model) {
                case .saved(let s): say("DRAW \(job.id)/\(job.name): SAVED \(s)")
                case .failed(let s):
                    failed.withLock { $0 += 1 }
                    say("DRAW \(job.id)/\(job.name): FAILED, see \(job.logFile.path): \(s)")
                case .limit(let l):
                    limit.withLock { $0 = $0 ?? l }
                    say("DRAW \(job.id)/\(job.name): not drawn, the image model refuses renders")
                }
            }
        }
        if let l = limit.withLock({ $0 }) {
            say(Fixer.limitLine(l))
            return Fixer.limitStatus
        }
        return failed.withLock { $0 } == 0 ? 0 : 1
    }

    enum Made { case saved(String), failed(String), limit(RenderLimit) }

    /// What an image API is asked for outside the drawing: the keyed layers are drawn on a
    /// painted key, a `clear` one on real transparency, and the ground and unkeyed layers as
    /// the model sees fit, which keeps the pick's clear corners.
    static func background(_ key: LayerPlan.Key?) -> ImageRequest.Background {
        switch key {
        case .magenta, .black: .opaque
        case .clear: .transparent
        case nil: .auto
        }
    }

    /// One edit by the image model into the job's `out`, with the prompt kept beside it only once the drawing landed, so a
    /// failed draw is tried again next run.
    static func make(_ job: DrawJob, generator: any ImageGenerator, model: String?) -> Made {
        let fm = FileManager.default
        let gen = job.out.deletingLastPathComponent()
        var log = "rimlight build draw: \(job.id) \(job.name)\n\(job.sent)\n"
        defer { try? Data(log.utf8).write(to: job.logFile) }
        let temp: URL
        do {
            try fm.createDirectory(at: gen, withIntermediateDirectories: true)
            temp = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: gen, create: true)
        } catch {
            log += "ERROR: \(error)\n"
            return .failed("\(error)")
        }
        defer { try? fm.removeItem(at: temp) }
        let request = ImageRequest(
            prompt: job.sent, refs: [job.ref], count: 1, model: model, outputDir: temp, background: Self.background(job.key))
        do {
            let result = try generator.run(request)
            log += "\(generator.tool) \(result.model), \(String(format: "%.0f", result.seconds)) s, thread \(result.threadID ?? "-")\n"
            if let u = result.usage { log += "input=\(u.input) cached=\(u.cached) output=\(u.output)\n" }
            log += result.messages.joined(separator: "\n") + "\n"
            guard let image = result.images.first else { return .failed("the image model returned no image") }
            // the drawing it replaces stays in gen/rounds/, so --restore can bring back one that fitted better
            try Self.keepRound(of: job.name, in: gen)
            try fm.moveItem(at: image, to: job.out)
            try Data(job.sent.utf8).write(to: job.promptFile, options: .atomic)
            try Data(job.signature.utf8).write(to: job.signatureFile, options: .atomic)
            if let key = job.key {
                try Data(key.rawValue.utf8).write(to: job.keyFile, options: .atomic)
            } else {
                try? fm.removeItem(at: job.keyFile)
            }
            log += "SAVED \(job.out.path)\n"
            return .saved(job.out.path)
        } catch ImageFailure.limit(let l) {
            log += Fixer.limitLine(l) + "\n"
            return .limit(l)
        } catch {
            log += "ERROR: \(error)\n"
            return .failed("\(error)".split(separator: "\n").first.map(String.init) ?? "\(error)")
        }
    }

    /// What a drawing depends on: the words that describe it and the key it is drawn on. Not `hero`, `soft`, `grey`,
    /// `match` or `box`, which act in the fit and are free, and not `dark`: switching quiet-pick's Dark from `dim` to a
    /// `tone` redrew both tiles, and every change of Dark is meant to be free for the layers.
    static func signature(_ layer: LayerPlan.Layer, _ plan: LayerPlan) -> String {
        // a layer only in Dark is asked as a new part, not out of the pick; said only then, so no older drawing goes stale
        (["layer \(LayerPrompts.version)", layer.what, layer.without ?? "", layer.shadow ?? "", layer.key.rawValue]
            + (layer.only == .dark ? ["only dark"] : [])).joined(separator: "\n")
    }

    /// A layer's drawn Dark copy depends on the layer's words, the words for Dark, and the key.
    static func signature(_ layer: LayerPlan.Layer, darkWords words: String) -> String {
        ["layer-dark \(LayerPrompts.version)", layer.what, words, layer.without ?? "", layer.key.rawValue].joined(separator: "\n")
    }

    /// `gen/<name>-dark.png`, a layer's Dark copy when the image model draws it.
    static func darkName(_ layer: String) -> String { "\(layer)-dark" }

    /// What the image model draws for a layer: the layer, and its Dark copy under `"dark": {"draw": ...}`.
    static func drawings(_ layer: LayerPlan.Layer) -> [String] {
        if case .draw = layer.dark { return [layer.name, darkName(layer.name)] }
        return [layer.name]
    }

    /// Whether a stored `.sig` is `wanted`. A layer's signature up to 0.5.0 ended in a line saying whether its light
    /// was asked neutral, "neutral light" or empty; it is dropped before comparing, so no drawing goes stale.
    static func sameSignature(_ stored: String?, _ wanted: String) -> Bool {
        guard let stored else { return false }
        return normalised(stored) == normalised(wanted)
    }

    static func normalised(_ signature: String) -> String {
        guard signature.hasPrefix("layer ") else { return signature }
        for tail in ["\nneutral light", "\n"] where signature.hasSuffix(tail) { return String(signature.dropLast(tail.count)) }
        return signature
    }

    /// Dark's ground depends on the ground and on the user's words for it, if any.
    static func signature(dark plan: LayerPlan) -> String {
        var words = ""
        if case .describe(let w) = plan.dark { words = "\n" + w }
        return "dark \(LayerPrompts.version)\n" + signature(ground: plan) + words
    }

    static func signature(ground plan: LayerPlan) -> String {
        ["ground \(LayerPrompts.version)", plan.ground.keep, plan.ground.remove].joined(separator: "\n")
    }

    static let drawingFiles = ["png", "txt", "sig", "key", "log"]

    /// Moves the current drawing of `name` and its files into `gen/rounds/<name>-<n>.*`, n one past the highest.
    static func keepRound(of name: String, in gen: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: gen.appending(path: "\(name).png").path) else { return }
        let rounds = gen.appending(path: "rounds", directoryHint: .isDirectory)
        try fm.createDirectory(at: rounds, withIntermediateDirectories: true)
        let n = (roundNumbers(of: name, in: rounds).max() ?? 0) + 1
        for ext in drawingFiles {
            let from = gen.appending(path: "\(name).\(ext)")
            if fm.fileExists(atPath: from.path) { try fm.moveItem(at: from, to: rounds.appending(path: "\(name)-\(n).\(ext)")) }
        }
    }

    static func roundNumbers(of name: String, in rounds: URL) -> [Int] {
        ((try? FileManager.default.contentsOfDirectory(atPath: rounds.path)) ?? []).compactMap { file in
            guard file.hasPrefix("\(name)-"), file.hasSuffix(".png") else { return nil }
            return Int(file.dropFirst(name.count + 1).dropLast(4))
        }
    }

    /// Swaps each named layer's drawing with the one it replaced, the latest in `gen/rounds/`: a redraw that
    /// landed worse goes back for free. Run twice, it swaps back.
    func restore(_ names: [String]) throws {
        let fm = FileManager.default
        for id in target.ids {
            let gen = file(id, "gen")
            let rounds = gen.appending(path: "rounds", directoryHint: .isDirectory)
            for name in names {
                guard let n = Self.roundNumbers(of: name, in: rounds).max() else {
                    throw StoreError.io("\(id): \(name) has no earlier drawing to restore")
                }
                let temp = gen.appending(path: ".restore-\(name)", directoryHint: .isDirectory)
                try? fm.removeItem(at: temp)
                try fm.createDirectory(at: temp, withIntermediateDirectories: true)
                for ext in Self.drawingFiles {
                    let current = gen.appending(path: "\(name).\(ext)")
                    let earlier = rounds.appending(path: "\(name)-\(n).\(ext)")
                    if fm.fileExists(atPath: current.path) { try fm.moveItem(at: current, to: temp.appending(path: ext)) }
                    if fm.fileExists(atPath: earlier.path) { try fm.moveItem(at: earlier, to: current) }
                    let held = temp.appending(path: ext)
                    if fm.fileExists(atPath: held.path) { try fm.moveItem(at: held, to: earlier) }
                }
                try? fm.removeItem(at: temp)
                say("RESTORE \(id)/\(name): the drawing before is back; the one it replaced is gen/rounds/\(name)-\(n).png")
            }
        }
    }

    // MARK: fit

    /// The ground as drawn, Dark's ground, then each layer bottom up: keyed by what it was drawn on, fitted onto
    /// the tile over what is already placed, and written to `layers/` with `fit.json`.
    func fit() throws {
        for id in target.ids {
            let plan = try plan(id)
            let concept = try LayerImage.read(file(id, "src/tile.png"))
            try FileManager.default.createDirectory(at: file(id, "layers"), withIntermediateDirectories: true)
            // Codex keeps a full-frame edit's layout, so the ground is never moved
            let ground = try LayerImage.read(file(id, "gen/\(Self.groundName).png")).resized(to: 1024).opaque
            try ground.write(to: file(id, "layers/\(Self.groundName).png"))
            let groundDark: LayerImage
            switch plan.dark {
            case .generate, .describe:
                groundDark = try LayerImage.read(file(id, "gen/\(Self.groundDarkName).png")).resized(to: 1024).opaque
            case .dim:
                groundDark = ground.dimmed(Self.dimFactor)
            case .tone(let hex):
                groundDark = ground.toned(LayerPlan.Dark.rgb(hex) ?? SIMD3(repeating: 0.1))
            case .invert:
                groundDark = ground.inverted()
            }
            try groundDark.write(to: file(id, "layers/\(Self.groundDarkName).png"))

            // a layer the plan no longer has would be packed from a stale file
            let kept = Set([Self.groundName, Self.groundDarkName] + plan.layers.flatMap { [$0.name, "\($0.name)-mono", "\($0.name)-dark"] })
            for name in (try? FileManager.default.contentsOfDirectory(atPath: file(id, "layers").path)) ?? []
            where name.hasSuffix(".png") && !kept.contains(String(name.dropLast(4))) {
                try? FileManager.default.removeItem(at: file(id, "layers/\(name)"))
            }

            var below = ground
            let groundColour = ground.meanColour
            var fits: [String: LayerFit.Fit] = [:]
            for layer in plan.layers {
                let (drawing, keyed) = try unkeyed(id, layer.name, layer)
                let box = layer.box.map { LayerBox(x0: $0.x0, y0: $0.y0, x1: $0.x1, y1: $0.y1) }
                // a keyed drawing usually keeps its place, but Codex enlarged the tortoise's head 1.65x on magenta:
                // when the drawing's own bounds miss the box, the box places it
                let outOfBox = box.map { !keyed || Self.overlap(drawing.alphaBounds(above: 0.5), $0) < 0.5 } ?? false
                let darkCopy = file(id, "layers/\(layer.name)-dark.png")
                if layer.only == .dark {
                    // the pick has nothing to fit it against: it stays where it was drawn, or goes into its box. It is
                    // not under the layers above, which are fitted against the pick
                    var fit = LayerFit.Fit(scale: 1, dx: 0, dy: 0)
                    if outOfBox, let box, let solid = drawing.alphaBounds(above: 0.5) {
                        fit = LayerFit.boxed(solid, into: box, side: LayerImage.tileSide)
                    }
                    try LayerFit.place(drawing, with: fit).write(to: file(id, "layers/\(layer.name).png"))
                    try? FileManager.default.removeItem(at: darkCopy)
                    fits[layer.name] = fit
                    say(String(format: "FIT %@/%@: only in Dark, %@, scale %.3f shift %+.0f,%+.0f", id, layer.name,
                        outOfBox ? "placed in its box" : "kept where it was drawn", fit.scale, fit.dx, fit.dy))
                    continue
                }
                var mode = LayerFit.Mode.keyed
                if let box, outOfBox { mode = .boxed(box) }
                var placement = try LayerFit.fit(drawing, concept: concept, under: below, mode: mode, soft: layer.soft)
                if case .keyed = mode, Self.atKeyedEdge(placement.fit) {
                    if let box {
                        placement = try LayerFit.fit(drawing, concept: concept, under: below, mode: .boxed(box), soft: layer.soft)
                    } else {
                        say("WARNING: \(id)/\(layer.name) fitted at the edge of its search, so the image model likely moved or resized it; "
                            + "give it a box")
                    }
                }
                if layer.match {
                    if let (image, shift) = placement.layer.matched(to: concept) {
                        placement.layer = image
                        say(String(format: "FIT %@/%@: moved onto the pick's colour, lightness %+.1f, a %+.1f, b %+.1f",
                            id, layer.name, shift.x * 100, shift.y * 100, shift.z * 100))
                    } else {
                        say("FIT \(id)/\(layer.name): too little solid inside to match the pick's colour; left as drawn")
                    }
                }
                fits[layer.name] = placement.fit
                try placement.layer.write(to: file(id, "layers/\(layer.name).png"))
                if layer.hero { try placement.layer.lifted().write(to: file(id, "layers/\(layer.name)-mono.png")) }
                // Dark's copy without the ground's colour, when Dark changes the ground's hue; dim and invert keep it
                let cleaned = plan.dark == .dim || plan.dark == .invert ? nil : placement.layer.withoutCast(of: groundColour)
                var recoloured: LayerImage?
                var colour = ""
                switch layer.dark {
                case .pick:
                    recoloured = placement.layer.recoloured(to: concept)
                    colour = "the pick's colour"
                case .tone(let hex):
                    recoloured = LayerPlan.Dark.rgb(hex).flatMap(placement.layer.recoloured(toColour:))
                    colour = hex
                case .invert, .draw, nil: break
                }
                if !colour.isEmpty, recoloured == nil {
                    say("WARNING: \(id)/\(layer.name) has too little solid inside to take \(colour); its Dark copy is made as without its dark")
                }
                if layer.only == .light {
                    // hidden in Dark, so it has no Dark copy
                    try? FileManager.default.removeItem(at: darkCopy)
                } else if case .draw = layer.dark {
                    // an edit of the same pick on the same key, so it sits where the layer's drawing sat: the layer's
                    // fit places it. The pick has no moon to search against
                    let (drawn, _) = try unkeyed(id, Self.darkName(layer.name), layer)
                    try LayerFit.place(drawn, with: placement.fit).write(to: darkCopy)
                    say("FIT \(id)/\(layer.name): Dark's copy drawn, placed as the layer")
                } else if layer.dark == .invert {
                    try (cleaned ?? placement.layer).inverted().write(to: darkCopy)
                    say("FIT \(id)/\(layer.name): Dark's copy inverted" + (cleaned == nil ? "" : ", the ground's colour taken out"))
                } else if let recoloured {
                    try recoloured.write(to: darkCopy)
                    say("FIT \(id)/\(layer.name): Dark's copy moved onto \(colour)")
                } else if let cleaned {
                    try cleaned.write(to: darkCopy)
                    say("FIT \(id)/\(layer.name): the ground's colour taken out of Dark's copy")
                } else {
                    try? FileManager.default.removeItem(at: darkCopy)
                }
                below = placement.layer.over(below)
                let f = placement.fit
                say(String(format: "FIT %@/%@: scale %.3f shift %+.0f,%+.0f", id, layer.name, f.scale, f.dx, f.dy)
                    + (layer.soft ? String(format: " opacity %.2f", f.opacity) : ""))
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(fits)
            try data.write(to: file(id, "layers/fit.json"), options: .atomic)
        }
    }

    /// A drawing in `gen/`, keyed by what it was drawn on, at the tile's size, and greyed for a grey layer. Keyed at
    /// the size it was drawn at, then resized: a resize first rings at the key's hard edge. Also whether it was keyed.
    private func unkeyed(_ id: String, _ name: String, _ layer: LayerPlan.Layer) throws -> (LayerImage, keyed: Bool) {
        var drawing = try LayerImage.read(file(id, "gen/\(name).png"))
        let drawnOn = (try? String(contentsOf: file(id, "gen/\(name).key"), encoding: .utf8))
            .flatMap { LayerPlan.Key(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? layer.key
        // a drawing with real alpha is used as it came, whatever it was asked for
        let keyed: Bool
        if drawing.hasAlpha {
            keyed = drawnOn != .clear
        } else if drawnOn == .black {
            drawing = drawing.unkeyedBlack()
            keyed = true
        } else if drawnOn == .magenta || drawing.isOnMagenta {
            drawing = drawing.unkeyedMagenta()
            keyed = true
        } else {
            say("WARNING: \(id)/\(name) came back opaque on no key; it covers what is under it")
            keyed = true
        }
        drawing = drawing.resized(to: LayerImage.tileSide)
        if layer.grey { drawing = drawing.greyed() }
        return (drawing, keyed)
    }

    // MARK: pack

    /// The package, its six renders, the plain assembly and `out/hero.png`, the image the app shows. The package and
    /// the renders are made in a hidden folder beside them and swapped in whole once both are done, so a reader sees
    /// the last build or this one, never a package half written; when ictool fails nothing is swapped.
    func pack() throws {
        let tool = ICTool.locate()
        let fm = FileManager.default
        for id in target.ids {
            let plan = try plan(id)
            let layout = target.layout(for: id)
            let package = layout.packageURL(id)
            let out = package.deletingLastPathComponent()
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            let staging = out.appending(path: ".pack-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? fm.removeItem(at: staging) }
            // ictool reads the staged package, so it keeps its own name
            let staged = staging.appending(path: package.lastPathComponent, directoryHint: .isDirectory)
            var assets: [String: URL] = [
                IconPackage.ground: file(id, "layers/\(Self.groundName).png"),
                IconPackage.groundDark: file(id, "layers/\(Self.groundDarkName).png"),
            ]
            var packed: [IconPackage.Layer] = []
            for layer in plan.layers {
                assets[IconPackage.assetName(layer.name)] = file(id, "layers/\(layer.name).png")
                if layer.hero { assets[IconPackage.assetName(layer.name, mono: true)] = file(id, "layers/\(layer.name)-mono.png") }
                let dark = file(id, "layers/\(layer.name)-dark.png")
                let hasDark = fm.fileExists(atPath: dark.path)
                if hasDark { assets[IconPackage.assetName(layer.name, dark: true)] = dark }
                packed.append(IconPackage.Layer(name: layer.name, hero: layer.hero, dark: hasDark, only: layer.only))
            }
            // Clear and Tinted want the darker ground under the light hero, which for an inverted Dark is Default's
            func luminance(_ name: String) throws -> Float {
                (try LayerImage.read(file(id, "layers/\(name).png")).meanColour * SIMD3<Float>(0.2126, 0.7152, 0.0722)).sum()
            }
            let tinted = try luminance(Self.groundName) < luminance(Self.groundDarkName) ? IconPackage.ground : IconPackage.groundDark
            try IconPackage.write(to: staged, layers: packed, assets: assets, tintedGround: tinted)

            var assembled = try LayerImage.read(file(id, "layers/\(Self.groundName).png"))
            for layer in plan.layers where layer.only != .dark {
                assembled = try LayerImage.read(file(id, "layers/\(layer.name).png")).over(assembled)
            }
            try assembled.write(to: file(id, "out/assembled.png"))

            let renders = file(id, "out/renders")
            let stagedRenders = staging.appending(path: "renders", directoryHint: .isDirectory)
            let stagedHero = staging.appending(path: "hero.png", directoryHint: .notDirectory)
            if let tool {
                try ICTool.render(staged, into: stagedRenders, tool: tool)
                try fm.copyItem(at: stagedRenders.appending(path: "Default.png"), to: stagedHero)
            } else {
                // the assembly is a square; the app shows a tile, as Icon Composer would
                try assembled.maskedToTile().write(to: stagedHero)
            }

            try AtomicFolder.replace(package, with: staged)
            if layout.kind == .store { removeOtherPackages(target.folder(id), keep: layout.package) }
            if tool != nil { try AtomicFolder.replace(renders, with: stagedRenders) } else { try? fm.removeItem(at: renders) }
            try AtomicFile.move(stagedHero, to: file(id, Self.heroPath))
            say("ICON \(package.path)")
            if tool != nil {
                say("RENDERS \(renders.path)")
                try contrast(id, plan)
                try edges(id, plan)
            } else {
                say("NO ICTOOL: the six renders are skipped; install Xcode 26 with Icon Composer and select it with xcode-select")
            }
        }
    }

    /// The image the app shows for a build, relative to its folder.
    static let heroPath = "out/hero.png"

    /// A `CONTRAST` line per appearance, each layer's contrast against what is behind it, and a `WARNING` per layer
    /// that fades into it: the eclipse's black tile vanished on a near-black Dark and the review kept it. Default
    /// and Dark judge every layer. Clear and Tinted show a dark layer as glass by design, so they judge the hero, the
    /// part lifted there; with no hero, they warn only when the whole subject fades.
    func contrast(_ id: String, _ plan: LayerPlan) throws {
        // Dark judges the layers it shows, by their Dark copies, whose shape a drawn one changes; the rest judge
        // the layers Default shows
        func outlines(dark: Bool) throws -> [LayerContrast.Outline] {
            let layers = try plan.layers.filter { $0.only != (dark ? .light : .dark) }.map { layer in
                let own = file(id, "layers/\(layer.name)-dark.png")
                let url = dark && FileManager.default.fileExists(atPath: own.path) ? own : file(id, "layers/\(layer.name).png")
                return (layer.name, try LayerImage.read(url).mask)
            }
            return LayerContrast.outlines(layers, width: LayerImage.tileSide)
        }
        let light = try outlines(dark: false)
        let dark = plan.differsByMode ? try outlines(dark: true) : light
        let hero = plan.layers.first(where: \.hero)?.name
        var fading: [String: [String]] = [:]
        var vanished: [String] = []
        for rendition in ICTool.renditions {
            let render = try LayerImage.read(file(id, "out/renders/\(rendition).png"))
            let measures = LayerContrast.measure(render, rendition == "Dark" ? dark : light)
            say("CONTRAST \(id) \(rendition): " + measures.map { m in
                "\(m.name) " + (m.contrast.map { String(Int($0.rounded())) } ?? "hidden")
            }.joined(separator: ", "))
            let mono = rendition.hasPrefix("Clear") || rendition.hasPrefix("Tinted")
            if mono, hero == nil {
                let shown = measures.filter { $0.contrast != nil }
                if !shown.isEmpty, shown.allSatisfy(\.fades) { vanished.append(rendition) }
                continue
            }
            for m in measures where m.fades && (!mono || m.name == hero) {
                let at = m.weakBox.map { ", around \($0.values.map(String.init).joined(separator: ","))" } ?? ""
                fading[m.name, default: []].append("\(rendition) (\(Int((m.weak * 100).rounded()))% of its outline\(at))")
            }
        }
        for layer in plan.layers {
            guard let places = fading[layer.name] else { continue }
            say("WARNING: \(id)/\(layer.name) fades into what is behind it, contrast under "
                + "\(Int(LayerContrast.threshold)), in " + places.joined(separator: ", "))
        }
        if !vanished.isEmpty {
            say("WARNING: \(id): every layer fades into the ground in \(vanished.joined(separator: ", ")); "
                + "mark the part that carries the idea hero")
        }
    }

    /// An `EDGE` line per layer, its outline and fill in Default against the pick's at full size, each measure at
    /// the 64 px block where Default is furthest from the pick, and a `WARNING` naming where a layer's outline is
    /// rougher, carries a band the pick's does not, its fill is mottled, or its colour is off the pick's. quiet-pick's grey tile came off the
    /// magenta key with a stepped outline, and the agent saw it at zoom and still passed it.
    func edges(_ id: String, _ plan: LayerPlan) throws {
        let layers = try plan.layers.filter { $0.only != .dark }.map { ($0.name, try LayerImage.read(file(id, "layers/\($0.name).png"))) }
        let measures = LayerEdge.measure(
            pick: try LayerImage.read(file(id, "src/tile.png")),
            render: try LayerImage.read(file(id, "out/renders/Default.png")), layers: layers)
        func pair(_ label: String, _ r: Double?, _ p: Double?, _ format: String) -> String? {
            guard let r, let p else { return nil }
            return "\(label) \(String(format: format, r)) (pick \(String(format: format, p)))"
        }
        for m in measures {
            let parts = [
                pair("outline", m.render.outline, m.pick.outline, "%.2f px"),
                pair("band", m.render.band, m.pick.band, "%+.1f"),
                pair("fill", m.render.fill, m.pick.fill, "%.2f"),
                pair("lightness", m.render.lightness, m.pick.lightness, "%.1f"),
                m.colourShift.map { String(format: "colour ΔE %.1f", $0) },
            ].compactMap { $0 }
            say("EDGE \(id) \(m.name): " + (parts.isEmpty ? "hidden" : parts.joined(separator: ", ")))
        }
        for m in measures where m.warns {
            func at(_ box: LayerBox) -> String { box.values.map(String.init).joined(separator: ",") }
            var found: [String] = []
            if let box = m.rough, let r = m.render.outline, let p = m.pick.outline {
                found.append(String(format: "its outline is rougher, %.2f px against %.2f, around ", r, p) + at(box))
            }
            if let box = m.banded, let r = m.render.band, let p = m.pick.band {
                found.append(String(format: "a %@ band runs inside its outline, %+.1f against %+.1f, around ",
                    r > p ? "lighter" : "darker", r, p) + at(box))
            }
            if let box = m.mottled, let r = m.render.fill, let p = m.pick.fill {
                found.append(String(format: "its fill is mottled, %.2f against %.2f, around ", r, p) + at(box))
            }
            if m.offColour, let shift = m.colourShift, let r = m.render.lightness, let p = m.pick.lightness {
                found.append(String(format: "its colour is off the pick's by ΔE %.1f, lightness %.1f against %.1f; "
                    + "\"match\": true on the layer takes the pick's, free", shift, r, p))
            }
            let zoom = m.rough != nil || m.banded != nil || m.mottled != nil
                ? "; zoom on each box with --stage zoom --box, or walk the outline with --stage zoom --outline \(m.name)" : ""
            say("WARNING: \(id)/\(m.name) in Default differs from the pick: " + found.joined(separator: "; ") + zoom)
        }
    }

    /// A title changed since the last build leaves its package behind; the build removes every other package
    /// before it writes this one.
    private func removeOtherPackages(_ folder: URL, keep: String) {
        let out = folder.appending(path: "out", directoryHint: .isDirectory)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? []
        where name.hasSuffix(".icon") && name != "\(keep).icon" {
            try? FileManager.default.removeItem(at: out.appending(path: name))
        }
    }

    // MARK: sheet, zoom, grid

    /// `out/review.png`: the pick, the assembly, the ground and its Dark copy, each layer, then the six renders and
    /// the compare's overlay; `out/compare.png`, the pick against Default; then the `MATCH` and `CHECK` lines.
    func sheet() throws {
        for id in target.ids {
            let plan = try plan(id)
            var top: [(label: String, image: LayerImage)] = [
                ("pick", try LayerImage.read(file(id, "src/tile.png"))),
                ("assembled", try LayerImage.read(file(id, "out/assembled.png"))),
            ]
            for name in [Self.groundName, Self.groundDarkName] {
                top.append(("layer: \(name)", try LayerImage.read(file(id, "layers/\(name).png"))))
            }
            for layer in plan.layers {
                let only = layer.only.map { $0 == .dark ? ", Dark only" : ", not in Dark" } ?? ""
                top.append(("layer: \(layer.name)\(only)", try LayerImage.read(file(id, "layers/\(layer.name).png"))))
                if case .draw = layer.dark {
                    top.append(("layer: \(layer.name) in Dark", try LayerImage.read(file(id, "layers/\(layer.name)-dark.png"))))
                }
            }
            var rows = [top]
            let renders = file(id, "out/renders")
            if FileManager.default.fileExists(atPath: renders.path) {
                rows.append(try ICTool.renditions.map { ($0, try LayerImage.read(renders.appending(path: "\($0).png"))) })
            }

            // the pick against what ships, measured: the eclipse's first build changed its crescent's shape and the
            // review still called Default the pick
            let pick = top[0].image
            let defaultRender = renders.appending(path: "Default.png")
            let hasRender = FileManager.default.fileExists(atPath: defaultRender.path)
            let label = hasRender ? "Default" : "assembled"
            let shipped = hasRender ? try LayerImage.read(defaultRender) : top[1].image
            let compared = LayerCompare.compare(pick: pick, render: shipped)
            try LayerCompare.picture(pick: pick, render: shipped, renderLabel: label, result: compared)
                .write(to: file(id, "out/compare.png"))
            let overlay = try LayerCompare.overlay(pick: pick, render: shipped, result: compared, panel: 384)
            // on the shorter row, so the sheet grows only when both rows are full
            let row = rows.count > 1 && rows[1].count < rows[0].count ? 1 : 0
            rows[row].append(("compare: pick red, \(label) cyan", overlay))

            try LayerImage.sheet(rows: rows, cell: 384).write(to: file(id, "out/review.png"))
            say("SHEET \(file(id, "out/review.png").path)")
            say(Self.matchLine(id, compared, label: label, picture: file(id, "out/compare.png")))
            if plan.differsByMode {
                // the measures compare Default with the pick, which has none of Dark's own parts
                say("CONSENT \(id): \(plan.consent ?? ""). Dark shows other parts than Default; MATCH and EDGE judge "
                    + "Default only, so judge Dark's own parts by eye in the Dark render, against the user's words")
            }
            // what must survive from the pick, re-read against the renders every round
            for check in plan.checks { say("CHECK \(id): \(check)") }
        }
    }

    /// `MATCH`: how much of the tile matches the pick, and the regions that do not, as zoom boxes.
    static func matchLine(_ id: String, _ result: LayerCompare.Result, label: String, picture: URL) -> String {
        let score = String(format: "%.1f%%", result.score * 100)
        let regions = result.regions.isEmpty ? "no part moved or changed shape"
            : "a part moved or changed shape at " + result.regions.map { $0.box.values.map(String.init).joined(separator: ",") }
                .joined(separator: " and ")
        return "MATCH \(id): \(score) of the tile matches the pick in \(label); \(regions); see \(picture.path)"
    }

    /// The pick and the renders cropped to a box, or to each quadrant, side by side.
    func zoom(_ aid: Aid) throws {
        for id in target.ids {
            let renders = file(id, "out/renders")
            guard FileManager.default.fileExists(atPath: renders.path) else {
                throw StoreError.io("no renders to zoom; ictool is missing, see `rimlight doctor`")
            }
            if let outlines = aid.outlines {
                try zoomOutlines(id, outlines, renditions: aid.renditions.isEmpty ? ["Default", "Dark"] : aid.renditions)
                continue
            }
            var images: [(label: String, image: LayerImage)] = [("pick", try LayerImage.read(file(id, "src/tile.png")))]
            for r in aid.renditions.isEmpty ? ICTool.renditions : aid.renditions {
                images.append((r, try LayerImage.read(renders.appending(path: "\(r).png")).resized(to: 1024)))
            }
            let boxes = aid.quadrants ? [[0, 0, 512, 512], [512, 0, 1024, 512], [0, 512, 512, 1024], [512, 512, 1024, 1024]]
                : [aid.box!]
            for values in boxes {
                guard let box = LayerBox(values) else { continue }
                // --scale 1 draws the crop 1:1; by default it is scaled up to at least 360 px
                let side = aid.scale.map { Int((Double(max(box.width, box.height)) * $0).rounded()) } ?? 360
                let url = file(id, "out/zoom-\(values.map(String.init).joined(separator: "-")).png")
                try LayerImage.zoom(images, box: box, minSide: side).write(to: url)
                say("ZOOM \(url.path)")
            }
        }
    }

    /// 1:1 crops along each named layer's whole outline, every layer's with none named: the pick beside the renders
    /// at the same crop, as few sheets as hold them. Quadrants at half size hid quiet-pick's stepped corner; this
    /// shows every edge at its real size. The outline under a layer above is left out, as it does not show.
    func zoomOutlines(_ id: String, _ names: [String], renditions: [String]) throws {
        let plan = try plan(id)
        let known = plan.layers.map(\.name)
        if let unknown = names.first(where: { !known.contains($0) }) {
            throw StoreError.io("the plan has no layer \"\(unknown)\"; its layers are \(known.joined(separator: ", "))")
        }
        var images: [(label: String, image: LayerImage)] = [("pick", try LayerImage.read(file(id, "src/tile.png")))]
        for r in renditions { images.append((r, try LayerImage.read(file(id, "out/renders/\(r).png")).resized(to: LayerImage.tileSide))) }
        let n = LayerImage.tileSide
        var above = [Bool](repeating: false, count: n * n)
        var boxes: [String: [LayerBox]] = [:]
        for layer in plan.layers.reversed() {
            let mask = try LayerImage.read(file(id, "layers/\(layer.name).png")).resized(to: n).mask
            boxes[layer.name] = LayerImage.outlineBoxes(mask, hidden: above, side: n)
            for i in 0..<(n * n) where mask[i] { above[i] = true }
        }
        for name in names.isEmpty ? known : names {
            let sheets = try LayerImage.cropSheets(images, boxes: boxes[name] ?? [])
            if sheets.isEmpty { say("ZOOM \(id)/\(name): no outline shows; a layer above covers it") }
            for (k, sheet) in sheets.enumerated() {
                let url = file(id, "out/zoom-outline-\(name)-\(k + 1).png")
                try sheet.write(to: url)
                say("ZOOM \(url.path)")
            }
        }
    }

    /// Part of the tile enlarged with a finer grid, for placing a clear layer's box.
    func grid(_ aid: Aid) throws {
        guard let box = aid.box else { return }
        for id in target.ids {
            let tile = try LayerImage.read(file(id, "src/tile.png"))
            let span = max(box[2] - box[0], box[3] - box[1])
            let step = span <= 128 ? 4 : span <= 256 ? 8 : 16
            let url = file(id, "src/grid-\(box.map(String.init).joined(separator: "-")).png")
            try tile.gridOverlay(step: step, labelEvery: step * 4, box: LayerBox(box)).write(to: url)
            say("GRID \(url.path)")
        }
    }
}

extension LayerImage {
    /// The image with alpha 1 everywhere: a ground is drawn edge to edge, and any alpha the image model left in it is noise.
    var opaque: LayerImage {
        var out = self
        for i in stride(from: 3, to: out.pixels.count, by: 4) { out.pixels[i] = 1 }
        return out
    }
}

extension BuildStages {
    /// The keyed search reaches 5% of scale and 52 px of shift; a fit near either went as far as it could.
    static func atKeyedEdge(_ fit: LayerFit.Fit) -> Bool {
        abs(fit.scale - 1) > 0.045 || abs(fit.dx) > 48 || abs(fit.dy) > 48
    }

    /// Intersection over union of a drawing's solid bounds and a box; 0 when the drawing has none.
    static func overlap(_ a: LayerBox?, _ b: LayerBox) -> Double {
        guard let a else { return 0 }
        let w = max(0, min(a.x1, b.x1) - max(a.x0, b.x0)), h = max(0, min(a.y1, b.y1) - max(a.y0, b.y0))
        let inter = Double(w * h)
        return inter / Double(a.width * a.height + b.width * b.height - w * h)
    }
}

extension LayerImage {
    /// The mean colour of an opaque image, sRGB 0...1.
    var meanColour: SIMD3<Float> {
        var sum = SIMD3<Float>(repeating: 0)
        for i in stride(from: 0, to: pixels.count, by: 4) { sum += SIMD3(pixels[i], pixels[i + 1], pixels[i + 2]) }
        return sum / Float(max(pixels.count / 4, 1))
    }
}
