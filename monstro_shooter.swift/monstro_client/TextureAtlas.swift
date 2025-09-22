import Foundation
import SpriteKit
import AppKit

struct SpriteFrame {
    let name: String
    let rect: CGRect
    let pivotX: Float
    let pivotY: Float
}

class TextureAtlas {
    private var frames: [String: SpriteFrame] = [:]
    private var baseTexture: SKTexture?

    init?(atlasImagePath: String, xmlPath: String) {
        // Load the base texture
        if let imagePath = Bundle.main.path(forResource: atlasImagePath.replacingOccurrences(of: ".png", with: ""), ofType: "png"),
           let nsImage = NSImage(contentsOfFile: imagePath) {
            self.baseTexture = SKTexture(image: nsImage)
        } else {
            print("Failed to load base texture: \(atlasImagePath)")
            return nil
        }

        // Parse the XML
        guard let xmlPath = Bundle.main.path(forResource: xmlPath.replacingOccurrences(of: ".xml", with: ""), ofType: "xml"),
              let xmlData = NSData(contentsOfFile: xmlPath) else {
            print("Failed to load XML file: \(xmlPath)")
            return nil
        }

        parseXML(data: xmlData as Data)
    }

    private func parseXML(data: Data) {
        let parser = XMLParser(data: data)
        let delegate = TextureAtlasXMLDelegate()
        parser.delegate = delegate

        if parser.parse() {
            self.frames = delegate.frames
            print("Parsed \(frames.count) sprite frames")

            // Debug: print frame names
            for (name, frame) in frames {
                print("Frame: \(name) at \(frame.rect)")
            }
        } else {
            print("Failed to parse XML")
        }
    }

    func getTexture(named frameName: String) -> SKTexture? {
        guard let frame = frames[frameName],
              let baseTexture = baseTexture else {
            print("Frame '\(frameName)' not found or base texture missing")
            return nil
        }

        // Convert coordinates to normalized values (0.0 to 1.0)
        let textureSize = baseTexture.size()
        let normalizedRect = CGRect(
            x: frame.rect.origin.x / textureSize.width,
            y: (textureSize.height - frame.rect.origin.y - frame.rect.height) / textureSize.height, // Flip Y coordinate
            width: frame.rect.width / textureSize.width,
            height: frame.rect.height / textureSize.height
        )

        return SKTexture(rect: normalizedRect, in: baseTexture)
    }

    func getFrameNames() -> [String] {
        return Array(frames.keys)
    }

    func getFramesWithPrefix(_ prefix: String) -> [String] {
        return frames.keys.filter { $0.hasPrefix(prefix) }.sorted()
    }
}

class TextureAtlasXMLDelegate: NSObject, XMLParserDelegate {
    var frames: [String: SpriteFrame] = [:]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {

        if elementName == "SubTexture" {
            guard let name = attributeDict["name"],
                  let xString = attributeDict["x"],
                  let yString = attributeDict["y"],
                  let widthString = attributeDict["width"],
                  let heightString = attributeDict["height"],
                  let x = Float(xString),
                  let y = Float(yString),
                  let width = Float(widthString),
                  let height = Float(heightString) else {
                print("Failed to parse SubTexture attributes")
                return
            }

            let pivotX = Float(attributeDict["pivotX"] ?? "0") ?? 0
            let pivotY = Float(attributeDict["pivotY"] ?? "0") ?? 0

            let rect = CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
            let frame = SpriteFrame(name: name, rect: rect, pivotX: pivotX, pivotY: pivotY)

            frames[name] = frame
        }
    }
}