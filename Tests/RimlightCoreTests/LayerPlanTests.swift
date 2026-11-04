import Foundation
import Testing

@testable import RimlightCore

/// The agent's layer plan: its check, its rounds, and the prompts made from it.
@Suite struct LayerPlanTests {
    /// The layer trial's eleven plans as the trial wrote them (`Rimlight-Research/layer-trial/plans/`).
    static let trialPlans = [
        #"{"id": "caliper", "source": "project set-028/caliper-head", "ground": {"name": "housing", "keep": "the orange device body, with its recessed display window left empty and its two round sockets left empty", "remove": "the brushed steel ruler strip along the top, the pale LCD screen inside the display window, the black button at lower left and the knurled silver knob at lower right; where the ruler strip was, continue the orange body up to the top edge"}, "dark": "generate", "layers": [{"name": "ruler", "what": "the brushed steel ruler strip with its tick marks across the top"}, {"name": "screen", "what": "the pale grey-green LCD screen glass inside the display window"}, {"name": "button", "what": "the round black button at lower left"}, {"name": "knob", "what": "the knurled knob at lower right, all plain silver steel: a brushed steel top and a silver knurled rim", "grey": true}]}"#,
        #"{"id": "dial-at-zero", "source": "blind test 7, dial-at-zero", "old": "~/Desktop/Rimlight builds/blind test 7 fixed/dial-at-zero.icon", "ground": {"name": "plate", "keep": "the indigo plate, with its eight small round holes drawn as deep, dark wells sunk into the plate", "remove": "the large white disc with its slot; continue the indigo plate where it was"}, "dark": "dim", "layers": [{"name": "disc", "what": "the large soft white disc with the narrow slot cut into its lower left edge", "box": [207, 187, 787, 753]}]}"#,
        #"{"id": "glass-pill-draining", "source": "blind test 10, glass-pill-draining", "old": "~/Desktop/Rimlight builds/blind test 10/glass-pill-draining.icon", "ground": {"name": "field", "keep": "the deep indigo field", "remove": "the tall glass capsule and the soft light around it; continue the indigo field where it was"}, "dark": "dim", "layers": [{"name": "pill", "what": "the tall glass capsule, exactly as drawn with everything inside it: its rim, its highlights, the indigo in its upper half and the warm white light filling its lower half", "box": [313, 80, 713, 940]}]}"#,
        #"{"id": "inst-dial", "source": "blind test 9, inst-dial", "ground": {"name": "plate", "keep": "the dark charcoal square plate around the dial", "remove": "the round dial: its chrome bezel ring, its black face, the ring of dots, the gold needle and its hub; continue the charcoal plate where the dial was"}, "dark": "dim", "layers": [{"name": "face", "what": "the round dial: its chrome bezel ring and its glossy black face", "without": "the dots, the needle and the hub; paint the black face where they were", "box": [14, 2, 1008, 1004]}, {"name": "dots", "what": "the ring of small glowing cream dots", "box": [96, 84, 930, 916]}, {"name": "needle", "what": "the gold needle with its round hub and the small glowing amber tip", "box": [448, 192, 806, 562]}]}"#,
        #"{"id": "keycap", "source": "project set-021/keycap-ruled-margin-cobalt", "ground": {"name": "paper", "keep": "the ruled notebook paper: cream paper with pale blue horizontal rules and one red vertical margin line near the left edge", "remove": "the blue keycap and the shadow it casts on the paper"}, "dark": "generate", "layers": [{"name": "keycap", "what": "the blue keycap, its body, sides and dished top", "without": "the two white bars on its top; paint the blue dished top where they were"}, {"name": "legend", "what": "the two white horizontal bars printed on the keycap's top"}]}"#,
        #"{"id": "notebook-corner", "source": "blind test 9, notebook-corner", "ground": {"name": "cover", "keep": "the mustard-yellow woven linen book cover", "remove": "the cream page edges and the cover's rolled edge along the top, and the dark brown elastic band down the right side; continue the linen cover up to the top edge and under the band"}, "dark": "generate", "layers": [{"name": "pages", "what": "the cream page block of the notebook's top edge: the thin strip of page edges along the top, under the cover's rolled edge, that turns down at the book's rounded top-right corner and ends there", "box": [190, 0, 1000, 230], "key": "magenta"}, {"name": "band", "what": "the dark brown elastic band running down the right side", "box": [610, 18, 882, 1024], "hero": true}]}"#,
        #"{"id": "rows-home-row", "source": "blind test 10, rows-home-row", "old": "~/Desktop/Rimlight builds/blind test 10/rows-home-row.icon", "ground": {"name": "slab", "keep": "the dark navy glass slab with its glossy rim highlights and the few faint pinpoint stars scattered over it", "remove": "the wavy glowing thread across the middle and the nine sparkling stars on it; continue the dark glass where they were"}, "dark": "dim", "layers": [{"name": "thread", "what": "the wavy glowing white thread across the middle with the eight sparkling white stars on it", "without": "the one amber star, third from the left; continue the thread where it was", "box": [40, 420, 987, 560]}, {"name": "amber", "what": "the one sparkling amber star, third from the left on the thread", "box": [262, 450, 352, 563], "hero": true}]}"#,
        #"{"id": "rows-twenty-six", "source": "blind test 7, rows-twenty-six", "old": "~/Desktop/Rimlight builds/blind test 7 fixed/rows-twenty-six.icon", "ground": {"name": "slab", "keep": "the dark navy glass slab with its glossy rim highlights", "remove": "the three rows of dots, both the dim grey ones and the bright glowing ones; continue the dark glass where they were"}, "dark": "dim", "layers": [{"name": "dots", "what": "all three rows of dots exactly as drawn: the small dim grey dots, the eight bright glowing white dots and the one glowing amber dot, each in its own place with its soft glow", "key": "black"}]}"#,
        #"{"id": "sleep-dial", "source": "style trial fixture dial (hush, sleep-timer-dial)", "old": "~/Desktop/Rimlight builds/style trial/Hardware, sleep dial.icon", "ground": {"name": "housing", "keep": "the warm off-white housing with its arc of engraved ticks and the round recessed well in its middle, left empty", "remove": "the indigo knurled dial and its amber pointer line; show the empty round well where the dial sat"}, "dark": "generate", "layers": [{"name": "knob", "what": "the round deep indigo dial with its knurled rim", "without": "the amber pointer line; paint the plain indigo top where it was", "box": [187, 187, 847, 860], "hero": true}, {"name": "pointer", "what": "the short warm amber pointer line engraved on the dial", "box": [291, 633, 380, 720]}]}"#,
        #"{"id": "sodium-lamp", "source": "blind test 9, sodium-lamp", "ground": {"name": "sky", "keep": "the night sky: the violet gradient with its small stars, and the band of distant dark hills along the horizon", "remove": "the wet road with its reflections, the streetlamp and the glow around its light; continue the sky and the distant hills, and below the horizon continue the dark hills band down to the bottom edge"}, "dark": "dim", "layers": [{"name": "road", "what": "the wet road from the horizon down to the bottom edge, with its orange and violet reflections", "without": "the streetlamp's pole; paint the road where it was", "box": [0, 560, 1024, 1024]}, {"name": "lamp", "what": "the streetlamp: its slim dark pole and its lamp head with the bright orange light", "box": [588, 0, 732, 615]}, {"name": "glow", "what": "the soft orange glow of light around the lamp head, as a soft translucent halo that fades out", "without": "the lamp head and the pole", "box": [430, 70, 850, 520], "soft": true}]}"#,
        #"{"id": "twig-perch", "source": "blind test 7, twig-perch", "old": "~/Desktop/Rimlight builds/blind test 7 fixed/twig-perch.icon", "ground": {"name": "backdrop", "keep": "the plain warm cream backdrop", "remove": "the felt bird and the felt twig with their shadows; continue the cream backdrop where they were"}, "dark": "generate", "layers": [{"name": "twig", "what": "the brown felt twig with its short stub, running off the left and right edges", "box": [20, 507, 1024, 993], "shadow": "the soft shadow the bird casts on the twig's upper side, under its body", "key": "magenta"}, {"name": "bird", "what": "the round yellow felt bird with its beak and tail", "box": [133, 173, 853, 727], "hero": true}]}"#,
    ]

    /// A trial plan in the new schema: the trial-only `id`, `source` and `old` go, the ground loses its name (it is
    /// always `ground`), `dark: keep` becomes `dim`, a layer with no key and a box was drawn on transparency and is
    /// `clear`, and a keyed layer drops its box (the trial fitted keyed layers from where they were drawn).
    static func converted(_ text: String) throws -> Data {
        var j = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        for k in ["id", "source", "old"] { j[k] = nil }
        var ground = try #require(j["ground"] as? [String: Any])
        ground["name"] = nil
        j["ground"] = ground
        if j["dark"] as? String == "keep" { j["dark"] = "dim" }
        j["layers"] = try #require(j["layers"] as? [[String: Any]]).map { layer in
            var layer = layer
            if layer["key"] == nil, layer["box"] != nil { layer["key"] = "clear" }
            if layer["key"] as? String == "magenta" { layer["box"] = nil }
            return layer
        }
        return try JSONSerialization.data(withJSONObject: j, options: [.sortedKeys])
    }

    static func plan(_ id: String) throws -> LayerPlan {
        let text = try #require(trialPlans.first { $0.contains(#""id": "\#(id)""#) })
        return try PlanFile.check(try converted(text)).plan
    }

    /// The problems `check` throws, or a recorded issue when it passes.
    static func problems(_ text: String) -> [String] {
        do {
            _ = try PlanFile.check(Data(text.utf8))
            Issue.record("no error for \(text)")
        } catch let invalid as PlanFile.Invalid {
            return invalid.problems
        } catch {
            Issue.record("unexpected \(error)")
        }
        return []
    }

    // MARK: the check

    @Test func theElevenTrialPlansCheckClean() throws {
        for text in Self.trialPlans {
            let checked = try PlanFile.check(try Self.converted(text))
            #expect(checked.warnings.isEmpty, "\(checked.warnings)")
        }
    }

    @Test func absentFieldsReadAsTheirDefaults() throws {
        let caliper = try Self.plan("caliper")
        #expect(caliper.dark == .generate)
        #expect(caliper.layers.map(\.name) == ["ruler", "screen", "button", "knob"])
        let knob = caliper.layers[3]
        #expect(knob.key == .magenta && knob.grey && !knob.soft && !knob.hero && knob.box == nil && knob.without == nil)
        let glow = try Self.plan("sodium-lamp").layers[2]
        #expect(glow.key == .clear && glow.soft && glow.box == LayerPlan.Box(430, 70, 850, 520))
        #expect(try Self.plan("twig-perch").layers[0].shadow == "the soft shadow the bird casts on the twig's upper side, under its body")
        #expect(try Self.plan("rows-twenty-six").layers[0].key == .black)
    }

    @Test func aPlanSurvivesEncodingAndWritesOnlyWhatIsSet() throws {
        let plan = try Self.plan("sodium-lamp")
        let data = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(LayerPlan.self, from: data) == plan)
        let lamp = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan.layers[1])) as? [String: Any])
        #expect(Set(lamp.keys) == ["name", "what", "key", "box"])
        // a whole number written with a point is still a box
        let box = try JSONDecoder().decode(LayerPlan.Box.self, from: Data("[1.0, 2, 3, 4]".utf8))
        #expect(box == LayerPlan.Box(1, 2, 3, 4))
    }

    @Test func everyProblemIsNamedAtOnce() {
        let bad = #"""
            {"ground": {"keep": " ", "name": "paper"}, "dark": "night",
             "layers": [{"name": "Key Cap", "what": "a", "key": "white", "box": [10, 10, 5, 2000]},
                        {"what": "b", "box": [1, 2, 3]}, {"name": "c", "box": [0.5, 0, 10, 10], "key": "clear"},
                        {"name": "ground", "what": "d", "key": "clear"}, {"name": "e", "what": "e", "soft": 1,
                         "hero": "yes", "grey": null, "match": 0, "without": 3, "shadow": ["x"]},
                        {"name": "e", "what": "f"}, 7, {"name": 4, "what": ""}]}
            """#
        let text = Self.problems(bad).joined(separator: "\n")
        #expect(text.contains("ground.keep is needed"))
        #expect(text.contains("ground.remove is needed"))
        #expect(text.contains("dark is \"generate\""))
        #expect(text.contains("layers[0] (Key Cap) name is 1 to 32 of a-z, 0-9 and -"))
        #expect(text.contains("layers[0] (Key Cap) key is \"magenta\", \"black\" or \"clear\""))
        #expect(text.contains("layers[0] (Key Cap) box [10, 10, 5, 2000] needs 0 <= x0 < x1 <= 1024"))
        #expect(text.contains("layers[1] has no name"))
        #expect(text.contains("layers[1] box is not [x0, y0, x1, y1]"))
        #expect(text.contains("layers[2] (c) has no what"))
        #expect(text.contains("layers[2] (c) box [0.5, 0, 10, 10] is not four whole numbers"))
        #expect(text.contains("layers[3] (ground) name is the ground's own"))
        #expect(text.contains("layers[3] (ground) is key \"clear\" without a box"))
        // JSON's 1 decodes as an NSNumber like true, and is still not a boolean
        #expect(text.contains("layers[4] (e) soft is true or false"))
        #expect(text.contains("layers[4] (e) hero is true or false"))
        #expect(text.contains("layers[4] (e) grey is true or false"))
        #expect(text.contains("layers[4] (e) match is true or false"))
        #expect(text.contains("layers[4] (e) without is not a string"))
        #expect(text.contains("layers[4] (e) shadow is not a string"))
        #expect(text.contains("layers[5] (e) has the same name as layers[4]"))
        #expect(text.contains("layers[6] is not an object"))
        #expect(text.contains("layers[7] name is not a string"))
        #expect(text.contains("layers[7] what is not a description"))
        #expect(Self.problems(bad).count == 22)
    }

    @Test func theWholeFileAndItsListsAreChecked() {
        #expect(Self.problems("[1, 2]") == ["it is not a JSON object"])
        #expect(Self.problems("not json") == ["it is not a JSON object"])
        #expect(Self.problems("{}") == [
            "ground is needed: an object with keep and remove",
            "dark is \"generate\" (the image model draws a night ground), \"dim\" (the ground a step darker), \"invert\" (the ground's "
                + "lightness flipped in code), {\"keep\": \"words\"} (the image model draws Dark's ground from your words) or "
                + "{\"tone\": \"#rrggbb\"} (the ground recoloured to that colour in code)",
            "layers is needed: the layers the image model draws, bottom to top",
        ])
        let ground = #""ground": {"keep": "k", "remove": "r"}"#
        #expect(Self.problems(#"{\#(ground), "dark": "dim", "layers": []}"#) == ["layers is empty: a plan draws at least one layer"])
        #expect(Self.problems(#"{\#(ground), "dark": "dim", "layers": {"name": "a"}}"#) == ["layers is not a list"])
        let nine = (1...9).map { #"{"name": "l\#($0)", "what": "w"}"# }.joined(separator: ", ")
        #expect(Self.problems(#"{\#(ground), "dark": "dim", "layers": [\#(nine)]}"#) == ["layers has 9: at most 8, one image each"])
        // the trial's third Dark is gone; the message says what replaced it
        #expect(Self.problems(#"{\#(ground), "dark": "keep", "layers": [{"name": "a", "what": "w"}]}"#)
            == [#"dark "keep" is gone: every icon gets its own Dark ground, "dim" for a ground that is dark already"#])
        #expect(Self.problems(#"{\#(ground), "dark": "dim", "layers": [{"name": "ground-dark", "what": "w"}]}"#)
            == ["layers[0] (ground-dark) name is the ground's own"])
        #expect(Self.problems(#"{\#(ground), "dark": "dim", "layers": [{"name": "dial-mono", "what": "w"}]}"#)
            == ["layers[0] (dial-mono) name ends in -mono, which a layer's Mono image takes"])
        #expect(Self.problems(#"{\#(ground), "dark": "dim", "layers": [{"name": "dial-dark", "what": "w"}]}"#)
            == ["layers[0] (dial-dark) name ends in -dark, which a layer's Dark image takes"])
        let long = String(repeating: "a", count: 33)
        #expect(Self.problems(#"{\#(ground), "dark": "dim", "layers": [{"name": "\#(long)", "what": "w"}]}"#)
            == ["layers[0] (\(long)) name is 1 to 32 of a-z, 0-9 and -"])
    }

    @Test func warningsAreKeptApartFromProblems() throws {
        let text = #"""
            {"id": "x", "ground": {"name": "paper", "keep": "k", "remove": "r"}, "dark": "generate",
             "layers": [{"name": "pages", "what": "p", "box": [0, 0, 1024, 230], "hero": true, "colour": "red"},
                        {"name": "dots", "what": "d", "key": "black", "box": [0, 0, 10, 10], "soft": true},
                        {"name": "glow", "what": "g", "soft": true, "hero": true},
                        {"name": "glass", "what": "g", "key": "clear", "box": [0, 0, 10, 10], "soft": true}]}
            """#
        let checked = try PlanFile.check(Data(text.utf8))
        #expect(checked.warnings == [
            "ground has an unknown key \"name\", kept and ignored",
            "layers[0] (pages) has an unknown key \"colour\", kept and ignored",
            "layers[2] (glow) is soft on magenta: a glow keyed off magenta gets coloured rings; key it on black",
            "2 layers are hero (pages, glow): hero marks the one main part, lifted in Clear and Tinted",
            "unknown key \"id\", kept and ignored by the build",
        ])
        #expect(checked.plan.layers.map(\.key) == [.magenta, .black, .magenta, .clear])
    }

    /// The user may want Dark in a colour of their own: the caliper's orange housing came back burnt orange from
    /// `generate`, and the user wanted matte black.
    @Test func darkTakesTheUsersWordsOrAColour() throws {
        let head = #""ground": {"keep": "k", "remove": "r"}, "layers": [{"name": "a", "what": "w"}]"#
        let words = try PlanFile.check(Data(#"{\#(head), "dark": {"keep": "the same housing in matte black plastic"}}"#.utf8))
        #expect(words.plan.dark == .describe("the same housing in matte black plastic"))
        #expect(words.plan.dark.drawn)
        let tone = try PlanFile.check(Data(##"{\##(head), "dark": {"tone": "#1c1c1e"}}"##.utf8))
        #expect(tone.plan.dark == .tone("#1c1c1e"))
        #expect(!tone.plan.dark.drawn)
        #expect(LayerPlan.Dark.rgb("#1c1c1e") == SIMD3<Float>(28, 28, 30) / 255)
        // it writes back as it came
        let data = try JSONEncoder().encode(tone.plan)
        #expect(try JSONDecoder().decode(LayerPlan.self, from: data) == tone.plan)

        #expect(Self.problems(##"{\##(head), "dark": {"keep": "k", "tone": "#000000"}}"##) == ["dark has keep or tone, not both"])
        #expect(Self.problems(#"{\#(head), "dark": {"keep": " "}}"#) == ["dark keep is the words the image model draws Dark's ground from, not empty"])
        #expect(Self.problems(#"{\#(head), "dark": {"tone": "black"}}"#) == ["dark tone is a colour written #rrggbb, such as \"#1c1c1e\""])

        let plan = words.plan
        let prompt = try #require(LayerPrompts.darkGround(plan))
        #expect(prompt.contains("dark-mode version of this app icon background: the same housing in matte black plastic."))
        #expect(LayerPrompts.darkGround(tone.plan) == nil)
        // a layer's light is asked neutral whenever Dark recolours the ground
        #expect(LayerPrompts.layer(tone.plan, tone.plan.layers[0]).contains("neutral white light"))
    }

    /// A layer's Dark copy in the pick's colour or one of the plan's own, made in code like invert.
    @Test func aLayerCanTakeThePicksColourOrAToneInDark() throws {
        let text = #"""
            {"ground": {"keep": "k", "remove": "r"}, "dark": {"tone": "#1c1c1c"},
             "layers": [{"name": "disc", "what": "the brown disc", "dark": "pick"},
                        {"name": "rim", "what": "the rim", "dark": {"tone": "#3a3a3c"}}]}
            """#
        let plan = try PlanFile.check(Data(text.utf8)).plan
        #expect(plan.layers[0].dark == .pick && plan.layers[1].dark == .tone("#3a3a3c"))
        #expect(try JSONDecoder().decode(LayerPlan.self, from: JSONEncoder().encode(plan)) == plan)
        let rim = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan.layers[1])) as? [String: Any])
        #expect(rim["dark"] as? [String: String] == ["tone": "#3a3a3c"])

        let wrong = text.replacingOccurrences(of: #""dark": "pick""#, with: #""dark": "grey""#)
        #expect(throws: (any Error).self) { try PlanFile.check(Data(wrong.utf8)) }
        let head = #""ground": {"keep": "k", "remove": "r"}, "dark": "dim""#
        #expect(Self.problems(#"{\#(head), "layers": [{"name": "a", "what": "w", "dark": {"tone": "grey"}}]}"#)
            == [##"layers[0] (a) dark tone is a colour written #rrggbb, such as "#1c1c1e""##])
    }

    /// A sky whose sun is a moon at night and whose stars only Dark has: the plan reads and keeps its consent.
    static func sky(consent: String? = "Yes, a moon and stars at night") -> String {
        #"{"ground": {"keep": "a pale blue sky", "remove": "the sun and the cloud"}, "dark": "generate", "layers": ["#
            + #"{"name": "cloud", "what": "the white cloud", "only": "light"}, "#
            + #"{"name": "sun", "what": "the yellow sun", "dark": {"draw": "a pale crescent moon"}}, "#
            + #"{"name": "stars", "what": "three small white stars at the upper left", "key": "black", "only": "dark"}]"#
            + (consent.map { #", "consent": "\#($0)"}"# } ?? "}")
    }

    @Test func aSkyCanShowOtherPartsInDarkWithTheUsersConsent() throws {
        let plan = try PlanFile.check(Data(Self.sky().utf8)).plan
        #expect(plan.differsByMode && plan.consent == "Yes, a moon and stars at night")
        #expect(plan.layers.map(\.only) == [.light, nil, .dark])
        #expect(plan.layers[1].dark == .draw("a pale crescent moon"))
        #expect(try JSONDecoder().decode(LayerPlan.self, from: JSONEncoder().encode(plan)) == plan)

        // the sun's Dark copy is an edit of the pick in the sun's place; the stars are new, in the pick's style
        let moon = LayerPrompts.layerDark(plan, plan.layers[1], words: "a pale crescent moon")
        #expect(moon.contains("dark-mode version of the yellow sun: a pale crescent moon") && moon.contains("the white cloud"))
        let stars = LayerPrompts.layer(plan, plan.layers[2])
        #expect(stars.contains("a new part for its dark-mode version: three small white stars") && stars.contains("pure black"))
        // the pick has no stars, so the sun is not asked to leave them out
        #expect(!LayerPrompts.layer(plan, plan.layers[1]).contains("stars"))

        // a plan without these layers needs no consent and draws as before
        let plain = try PlanFile.check(Data(#"{"ground": {"keep": "k", "remove": "r"}, "dark": "dim", "layers": [{"name": "a", "what": "w"}]}"#.utf8))
        #expect(!plain.plan.differsByMode && plain.plan.consent == nil)
        #expect(!String(decoding: try JSONEncoder().encode(plain.plan), as: UTF8.self).contains("consent"))
    }

    @Test func otherPartsInDarkAreRefusedWithoutConsent() throws {
        let asked = #"cloud, sun, stars make Dark show other parts than Default ("only", or "dark": {"draw": ...}). "#
            + #"That is a last resort: ask the user first, and put their reply, in their own words, in "consent""#
        #expect(Self.problems(Self.sky(consent: nil)) == [asked])
        #expect(Self.problems(Self.sky(consent: " ")) == [#"consent is the user's own words agreeing, not empty"#])

        let head = #""ground": {"keep": "k", "remove": "r"}, "dark": "dim", "consent": "yes""#
        #expect(Self.problems(#"{\#(head), "layers": [{"name": "a", "what": "w", "only": "night"}]}"#)
            == [#"layers[0] (a) only is "light" (in Default, Clear and Tinted, hidden in Dark) or "dark" (in Dark only)"#])
        #expect(Self.problems(#"{\#(head), "layers": [{"name": "a", "what": "w"}, {"name": "b", "what": "w", "only": "dark", "dark": "pick"}]}"#)
            == ["layers[1] (b) is only in Dark, so it is its own Dark image: leave out its dark"])
        #expect(Self.problems(#"{\#(head), "layers": [{"name": "a", "what": "w", "only": "light", "dark": "invert"}]}"#)
            == ["layers[0] (a) is only in Default, so it has no Dark image: leave out its dark"])
        #expect(Self.problems(#"{\#(head), "layers": [{"name": "a", "what": "w"}, {"name": "b", "what": "w", "only": "dark", "hero": true}]}"#)
            == ["layers[1] (b) is only in Dark, and hero lifts a part in Clear and Tinted, which show Default's layers"])
        #expect(Self.problems(#"{\#(head), "layers": [{"name": "a", "what": "w", "only": "dark"}]}"#)
            == ["every layer is only in Dark, so Default would show the ground alone"])
        #expect(Self.problems(#"{\#(head), "layers": [{"name": "a", "what": "w", "dark": {"draw": ""}}]}"#)
            == ["layers[0] (a) dark draw is the words the image model draws the layer's Dark copy from, not empty"])

        let unneeded = try PlanFile.check(Data(#"{\#(head), "layers": [{"name": "a", "what": "w", "dark": "pick"}]}"#.utf8))
        #expect(unneeded.warnings == [#"consent is kept, but no layer needs it: none has "only" or "dark": {"draw": ...}"#])
    }

    /// The full flip the user wanted for the eclipse: Dark's ground and a layer, each inverted in code. Free: no
    /// Dark ground to draw, and the layers' own words, which decide a redraw, are untouched.
    @Test func darkAndALayerCanBeInverted() throws {
        let text = #"""
            {"ground": {"keep": "k", "remove": "r"}, "dark": "invert",
             "layers": [{"name": "tile", "what": "the black tile", "dark": "invert"}, {"name": "dot", "what": "d"}]}
            """#
        let plan = try PlanFile.check(Data(text.utf8)).plan
        #expect(plan.dark == .invert && !plan.dark.drawn)
        #expect(LayerPrompts.darkGround(plan) == nil)
        #expect(plan.layers[0].dark == .invert && plan.layers[1].dark == nil)
        // the layer's prompt is the same as under generate, so switching costs nothing
        var generate = plan
        generate.dark = .generate
        #expect(LayerPrompts.layer(plan, plan.layers[0]) == LayerPrompts.layer(generate, generate.layers[0]))
        let data = try JSONEncoder().encode(plan)
        #expect(try JSONDecoder().decode(LayerPlan.self, from: data) == plan)
        let tile = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan.layers[0])) as? [String: Any])
        #expect(tile["dark"] as? String == "invert")

        let head = #""ground": {"keep": "k", "remove": "r"}, "dark": "dim""#
        #expect(Self.problems(#"{\#(head), "layers": [{"name": "a", "what": "w", "dark": "dim"}]}"#)
            == [Self.layerDarkChoices])
        #expect(Self.problems(#"{\#(head), "layers": [{"name": "a", "what": "w", "dark": true}]}"#)
            == [Self.layerDarkChoices])
    }

    static let layerDarkChoices = #"layers[0] (a) dark is "invert" (the layer's lightness flipped), "pick" (the layer in "#
        + ##"the pick's colour) or {"tone": "#rrggbb"} (the layer in that colour), each made in Dark's copy of the layer; "##
        + #"or, with the user's consent, {"draw": "words"} (the image model draws Dark's copy from the words)"#

    /// `match` acts in the fit, so it is free: it changes no prompt, and an absent one is false and is not written.
    @Test func matchIsAFreeFlag() throws {
        let text = #"""
            {"ground": {"keep": "k", "remove": "r"}, "dark": "dim",
             "layers": [{"name": "tile", "what": "the grey tile", "match": true}, {"name": "dot", "what": "d"}]}
            """#
        let plan = try PlanFile.check(Data(text.utf8)).plan
        #expect(plan.layers[0].match && !plan.layers[1].match)
        var plain = plan
        plain.layers[0].match = false
        #expect(LayerPrompts.layer(plan, plan.layers[0]) == LayerPrompts.layer(plain, plain.layers[0]))
        #expect(try JSONDecoder().decode(LayerPlan.self, from: JSONEncoder().encode(plan)) == plan)
        let dot = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan.layers[1])) as? [String: Any])
        #expect(dot["match"] == nil)
    }

    /// What must survive from the pick, printed by every sheet: at most eight sentences, none empty. They draw
    /// nothing, so they are not in any layer's prompt.
    @Test func checksAreAFewSentences() throws {
        let head = #""ground": {"keep": "k", "remove": "r"}, "dark": "dim", "layers": [{"name": "a", "what": "w"}]"#
        let crescent = "the crescent is widest at the upper-left corner and tapers to nothing at the top-right and bottom-left corners"
        let checked = try PlanFile.check(Data(#"{\#(head), "checks": ["\#(crescent)"]}"#.utf8))
        #expect(checked.warnings.isEmpty)
        #expect(checked.plan.checks == [crescent])
        #expect(!LayerPrompts.layer(checked.plan, checked.plan.layers[0]).contains("crescent"))
        #expect(!LayerPrompts.ground(checked.plan).contains("crescent"))
        let data = try JSONEncoder().encode(checked.plan)
        #expect(try JSONDecoder().decode(LayerPlan.self, from: data) == checked.plan)
        // absent, it is empty and not written
        let plain = try PlanFile.check(Data("{\(head)}".utf8)).plan
        #expect(plain.checks.isEmpty)
        let written = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
        #expect(written["checks"] == nil)

        let nine = (1...9).map { "\"check \($0)\"" }.joined(separator: ", ")
        #expect(Self.problems(#"{\#(head), "checks": [\#(nine)]}"#) == ["checks has 9: at most 8, the few things the pick must keep"])
        #expect(Self.problems(#"{\#(head), "checks": ["fine", " ", 3]}"#) == [
            "checks[1] is not a sentence: say what must survive from the pick",
            "checks[2] is not a sentence: say what must survive from the pick",
        ])
        #expect(Self.problems(#"{\#(head), "checks": "the crescent"}"#) == ["checks is a list of sentences, each a thing the pick must keep"])
    }

    // MARK: the store

    @Test func storingKeepsEachEarlierRound() throws {
        try withTempDir { dir in
            let folder = dir.appending(path: "build", directoryHint: .isDirectory)
            let a = Data(#"{"dark": "dim", "layers": []}"#.utf8)
            #expect(try PlanFile.store(a, in: folder) == nil)
            // the same JSON with its keys in another order and other spacing is the same plan: no round
            #expect(try PlanFile.store(Data("{ \"layers\" : [ ],\n \"dark\" : \"dim\" }\n".utf8), in: folder) == nil)
            #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "rounds").path))
            let round1 = try #require(try PlanFile.store(Data(#"{"dark": "generate"}"#.utf8), in: folder))
            #expect(round1.lastPathComponent == "plan-1.json")
            #expect(try Data(contentsOf: round1) == a + Data("\n".utf8))
            // a subject's rounds share the folder and do not count
            try Data("{}".utf8).write(to: folder.appending(path: "rounds/subject-7.json"))
            let round2 = try #require(try PlanFile.store(Data(#"{"dark": "x"}"#.utf8), in: folder))
            #expect(round2.lastPathComponent == "plan-2.json")
            let now = try String(contentsOf: folder.appending(path: "plan.json"), encoding: .utf8)
            #expect(now == "{\"dark\": \"x\"}\n")
        }
    }

    // MARK: the prompts

    // The expected strings are what lt.py's prompt_ground, prompt_dark and prompt_layer print for the trial's
    // plans, pasted. One schema change shows: the keycap's layers had no key there and were drawn on transparency;
    // here an absent key is magenta, so their expected text is lt.py's with "key": "magenta" set on the layer
    // itself. (lt.py's own redraw passed a copy, {**L, "key": "magenta"}, and its `x is not L` then listed the
    // layer among its own leave-outs; the port leaves out by name, so it never does.)

    static let keycapPaper = "the ruled notebook paper: cream paper with pale blue horizontal rules and one red vertical margin line near the left edge"

    @Test func theGroundAndDarkPromptsAreTheTrials() throws {
        #expect(LayerPrompts.ground(try Self.plan("keycap")) == "Square image. Edit Image 1. Image 1 is an app icon. Output only its background: \(Self.keycapPaper). Remove the blue keycap and the shadow it casts on the paper. Paint what lies behind them so the background carries on naturally. Fill the whole square edge to edge, the four corners included: no rounded tile shape, no border, no transparency. Keep the same colours, lighting, texture, grain and detail at the same scale and in the same place as in Image 1. No text, no watermark.")
        #expect(LayerPrompts.ground(try Self.plan("rows-twenty-six")) == "Square image. Edit Image 1. Image 1 is an app icon. Output only its background: the dark navy glass slab with its glossy rim highlights. Remove the three rows of dots, both the dim grey ones and the bright glowing ones; continue the dark glass where they were. Paint what lies behind them so the background carries on naturally. Fill the whole square edge to edge, the four corners included: no rounded tile shape, no border, no transparency. Keep the same colours, lighting, texture, grain and detail at the same scale and in the same place as in Image 1. No text, no watermark.")
        #expect(LayerPrompts.darkGround() == "Square image. Edit Image 1. Make the dark-mode version of this app icon background, the way Apple's dark appearance does: the same picture, layout, texture and scale, its colours stepped down to a deep, low-light shade of the same hues, lit areas dimmed to match, so light objects placed on it stand out. Keep it edge to edge with no tile shape, no border and no transparency. No text, no watermark.")
    }

    @Test func keycapLayerPromptsAreTheTrials() throws {
        let plan = try Self.plan("keycap")
        #expect(LayerPrompts.layer(plan, plan.layers[0]) == "Square image. Edit Image 1. Image 1 is an app icon. Output only the blue keycap, its body, sides and dished top, alone on a flat, solid, pure magenta (#FF00FF) background that fills everything around it, with no shadow, glow or gradient on the magenta. Keep it exactly as drawn in Image 1: the same position in the square, the same size, perspective, colours, lighting, texture and detail. Draw it complete, including any part another object covers in Image 1. Leave out the two white bars on its top; paint the blue dished top where they were. Light it with neutral white light: no colour cast or reflection from the background around it, since the background changes colour in dark mode. Leave out the background (\(Self.keycapPaper)) and the two white horizontal bars printed on the keycap's top. No text, no watermark.")
        #expect(LayerPrompts.layer(plan, plan.layers[1]) == "Square image. Edit Image 1. Image 1 is an app icon. Output only the two white horizontal bars printed on the keycap's top, alone on a flat, solid, pure magenta (#FF00FF) background that fills everything around it, with no shadow, glow or gradient on the magenta. Keep it exactly as drawn in Image 1: the same position in the square, the same size, perspective, colours, lighting, texture and detail. Draw it complete, including any part another object covers in Image 1. Light it with neutral white light: no colour cast or reflection from the background around it, since the background changes colour in dark mode. Leave out the background (\(Self.keycapPaper)) and the blue keycap, its body, sides and dished top. No text, no watermark.")
        // lt.py's keycap as the trial drew it, with no key: the transparency wording, here `clear`
        #expect(LayerPrompts.layer(plan, plan.layers[0], key: .clear) == "Square image. Edit Image 1. Image 1 is an app icon. Output only the blue keycap, its body, sides and dished top, alone on a fully transparent background (real alpha channel, no backdrop, no checkerboard, no cast shadow). Keep it exactly as drawn in Image 1: the same position in the square, the same size, perspective, colours, lighting, texture and detail. Draw it complete, including any part another object covers in Image 1. Leave out the two white bars on its top; paint the blue dished top where they were. Light it with neutral white light: no colour cast or reflection from the background around it, since the background changes colour in dark mode. Leave out the background (\(Self.keycapPaper)) and the two white horizontal bars printed on the keycap's top. No text, no watermark. Everything around it must be real transparent pixels, alpha zero, even where it runs to the edge of the square; never paint a grey and white checkerboard. Output a PNG with transparency.")
    }

    @Test func blackAndShadowPromptsAreTheTrials() throws {
        let rows = try Self.plan("rows-twenty-six")
        // dark is dim: no neutral-light sentence
        #expect(LayerPrompts.layer(rows, rows.layers[0]) == "Square image. Edit Image 1. Image 1 is an app icon. Output only all three rows of dots exactly as drawn: the small dim grey dots, the eight bright glowing white dots and the one glowing amber dot, each in its own place with its soft glow, alone on a flat, solid, pure black (#000000) background that fills everything around it. Keep it exactly as drawn in Image 1: the same position in the square, the same size, perspective, colours, lighting, texture and detail. Draw it complete, including any part another object covers in Image 1. Leave out the background (the dark navy glass slab with its glossy rim highlights). No text, no watermark.")
        let twig = try Self.plan("twig-perch")
        #expect(LayerPrompts.layer(twig, twig.layers[0]) == "Square image. Edit Image 1. Image 1 is an app icon. Output only the brown felt twig with its short stub, running off the left and right edges, alone on a flat, solid, pure magenta (#FF00FF) background that fills everything around it, with no shadow, glow or gradient on the magenta. Keep it exactly as drawn in Image 1: the same position in the square, the same size, perspective, colours, lighting, texture and detail. Draw it complete, including any part another object covers in Image 1. Keep the soft shadow the bird casts on the twig's upper side, under its body exactly as in Image 1, drawn on this part. Light it with neutral white light: no colour cast or reflection from the background around it, since the background changes colour in dark mode. Leave out the background (the plain warm cream backdrop) and the round yellow felt bird with its beak and tail. No text, no watermark.")
    }

    @Test func aClearLayerRedrawnOnMagentaKeepsItsOwnWords() throws {
        let lamp = try Self.plan("sodium-lamp")
        let glow = lamp.layers[2]
        #expect(glow.key == .clear)
        let clear = LayerPrompts.layer(lamp, glow)
        let magenta = LayerPrompts.layer(lamp, glow, key: .magenta)
        #expect(clear.hasSuffix("Output a PNG with transparency."))
        #expect(magenta.hasSuffix("with its orange and violet reflections; the streetlamp: its slim dark pole and its lamp head with the bright orange light. No text, no watermark."))
        #expect(magenta.contains("pure magenta (#FF00FF)"))
        #expect(!magenta.contains("transparen"))
    }
}
