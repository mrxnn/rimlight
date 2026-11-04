import Foundation
import Testing

@testable import RimlightCore

@Suite struct ImageModelsTests {
    /// Only models that take images can refine, fix and build, and only raster ones can be
    /// fitted, so the rest are left out.
    @Test func openRouterKeepsModelsThatTakeImages() {
        let reply = #"""
            {"data":[
              {"id":"b/editor","name":"Editor","architecture":{"input_modalities":["text","image"],"output_modalities":["image"]}},
              {"id":"a/text-only","name":"Text only","architecture":{"input_modalities":["text"],"output_modalities":["image"]}},
              {"id":"c/another","name":"Another","architecture":{"input_modalities":["image","text"]}},
              {"name":"No id","architecture":{"input_modalities":["image"]}},
              {"id":"d/vector","name":"Vector","architecture":{"input_modalities":["text","image"]},
               "supported_parameters":{"output_format":{"type":"enum","values":["svg"]}}},
              {"id":"e/raster","name":"Raster","architecture":{"input_modalities":["text","image"]},
               "supported_parameters":{"output_format":{"type":"enum","values":["jpeg"]}}}
            ]}
            """#
        let models = ImageModels.openRouterModels(Data(reply.utf8))
        // A vector model's SVG can't be fitted to the tile.
        #expect(models.map(\.id) == ["c/another", "b/editor", "e/raster"])
    }

    @Test func openAIHasADefaultAndOpenRouterAsks() {
        #expect(ImageModels.defaultModel(for: .openai) == "gpt-image-2.5-flare")
        #expect(ImageModels.defaultModel(for: .openrouter) == nil)
        #expect(ImageProvider.openai.defaultBaseURL?.absoluteString == "https://api.openai.com/v1")
        #expect(ImageProvider.openrouter.dialect == .openrouter)
    }
}

@Suite struct ImagePriceTests {
    /// Grok's endpoints reply, cut down: by the image, with a charge per reference.
    @Test func aPerImagePriceShowsItsRange() throws {
        let reply = #"""
            {"data":{"endpoints":[{"provider_name":"xAI","pricing":[
              {"billable":"input_image","unit":"image","cost_usd":0.01},
              {"billable":"output_image","unit":"image","cost_usd":0.04,"variant":"low_1k"},
              {"billable":"output_image","unit":"image","cost_usd":0.06,"variant":"medium_1k"}]}]}}
            """#
        let price = try #require(ImagePrice.parse(endpoints: Data(reply.utf8)))
        #expect(price.perImage == 0.04...0.06)
        #expect(price.perReference == 0.01)
        #expect(price.label == "$0.04 to $0.06 an image")
    }

    @Test func aTokenPriceIsPerMillion() throws {
        let reply = #"""
            [{"provider_name":"OpenAI","pricing":[
              {"billable":"input_image","unit":"token","cost_usd":8e-06},
              {"billable":"output_image","unit":"token","cost_usd":3e-05}]}]
            """#
        let price = try #require(ImagePrice.parse(endpoints: Data(reply.utf8)))
        #expect(price.label == "$30 per million image tokens")
        #expect(ImagePrice(perImage: 0.13...0.13).label == "$0.13 an image")
        #expect(ImagePrice.parse(endpoints: Data("[]".utf8)) == nil)
    }

    @Test func transparencyComesFromTheBackgroundValues() {
        let reply = #"""
            {"data":[
              {"id":"a/opaque","name":"Opaque","architecture":{"input_modalities":["text","image"]},
               "supported_parameters":{"background":{"type":"enum","values":["auto","opaque"]}}},
              {"id":"b/clear","name":"Clear","architecture":{"input_modalities":["image"]},
               "supported_parameters":{"background":{"type":"enum","values":["auto","transparent","opaque"]}}},
              {"id":"c/none","name":"Another","architecture":{"input_modalities":["image"]},"supported_parameters":{}}
            ]}
            """#
        let models = ImageModels.openRouterModels(Data(reply.utf8))
        #expect(models.map(\.id) == ["b/clear", "c/none", "a/opaque"])
        #expect(models.map(\.transparency) == [true, false, false])
        #expect(!ImageModels.openAIDrawsTransparency("gpt-image-2"))
        #expect(ImageModels.openAIDrawsTransparency("gpt-image-2.5-flare"))
    }
}
