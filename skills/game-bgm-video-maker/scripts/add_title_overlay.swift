import AVFoundation
import AppKit
import CoreText
import CoreGraphics
import Foundation
import QuartzCore

func fail(_ message: String) -> Never {
    fputs("error: \(message)\n", stderr)
    exit(1)
}

struct Options {
    var input: String?
    var output: String?
    var title: String = "Pokemon Pokopia"
    var subtitle: String = "Withered Wasteland (Day) Townscape"
    var overlayImage: String?
    var duration: Double = 8
}

func parseOptions() -> Options {
    var options = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--input":
            options.input = args.isEmpty ? nil : args.removeFirst()
        case "--output":
            options.output = args.isEmpty ? nil : args.removeFirst()
        case "--title":
            options.title = args.isEmpty ? options.title : args.removeFirst()
        case "--subtitle":
            options.subtitle = args.isEmpty ? options.subtitle : args.removeFirst()
        case "--overlay-image":
            options.overlayImage = args.isEmpty ? nil : args.removeFirst()
        case "--duration":
            options.duration = args.isEmpty ? options.duration : (Double(args.removeFirst()) ?? options.duration)
        default:
            fail("unknown option: \(arg)")
        }
    }
    return options
}

func makeTextLayer(
    text: String,
    fontName: String,
    fontSize: CGFloat,
    frame: CGRect,
    opacity: Float
) -> CATextLayer {
    let layer = CATextLayer()
    layer.string = text
    layer.font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
    layer.fontSize = fontSize
    layer.alignmentMode = .center
    layer.foregroundColor = CGColor(gray: 1.0, alpha: 1.0)
    layer.shadowColor = CGColor(gray: 0.0, alpha: 1.0)
    layer.shadowOpacity = 0.55
    layer.shadowOffset = CGSize(width: 0, height: -2)
    layer.shadowRadius = 8
    layer.contentsScale = 2.0
    layer.frame = frame
    layer.opacity = opacity
    return layer
}

let options = parseOptions()
guard let inputPath = options.input, let outputPath = options.output else {
    fail("usage: swift tools/add_title_overlay.swift --input input.mp4 --output output.mp4 [--overlay-image title.png] [--title ...] [--subtitle ...] [--duration 8]")
}

let inputURL = URL(fileURLWithPath: inputPath)
let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.removeItem(at: outputURL)

let asset = AVURLAsset(url: inputURL)
guard let sourceVideo = asset.tracks(withMediaType: .video).first else {
    fail("input has no video track")
}

let composition = AVMutableComposition()
guard let videoTrack = composition.addMutableTrack(
    withMediaType: .video,
    preferredTrackID: kCMPersistentTrackID_Invalid
) else {
    fail("could not create video track")
}
try videoTrack.insertTimeRange(
    CMTimeRange(start: .zero, duration: asset.duration),
    of: sourceVideo,
    at: .zero
)

if let sourceAudio = asset.tracks(withMediaType: .audio).first,
   let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
    try audioTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: asset.duration),
        of: sourceAudio,
        at: .zero
    )
}

let transform = sourceVideo.preferredTransform
let natural = sourceVideo.naturalSize.applying(transform)
let renderSize = CGSize(width: abs(natural.width), height: abs(natural.height))
videoTrack.preferredTransform = transform

let instruction = AVMutableVideoCompositionInstruction()
instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
layerInstruction.setTransform(transform, at: .zero)
instruction.layerInstructions = [layerInstruction]

let videoComposition = AVMutableVideoComposition()
videoComposition.instructions = [instruction]
videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
videoComposition.renderSize = renderSize

let parentLayer = CALayer()
let videoLayer = CALayer()
parentLayer.frame = CGRect(origin: .zero, size: renderSize)
videoLayer.frame = parentLayer.frame
parentLayer.addSublayer(videoLayer)

let panelLayer = CALayer()
panelLayer.frame = CGRect(x: 0, y: renderSize.height * 0.50, width: renderSize.width, height: renderSize.height * 0.24)
panelLayer.backgroundColor = CGColor(gray: 0.0, alpha: 0.18)
panelLayer.opacity = 1.0

let titleLayer = makeTextLayer(
    text: options.title,
    fontName: "HelveticaNeue-Medium",
    fontSize: 78,
    frame: CGRect(x: 0, y: renderSize.height * 0.62, width: renderSize.width, height: 96),
    opacity: 0
)
let subtitleLayer = makeTextLayer(
    text: options.subtitle,
    fontName: "HelveticaNeue",
    fontSize: 42,
    frame: CGRect(x: 0, y: renderSize.height * 0.55, width: renderSize.width, height: 62),
    opacity: 0
)

let titleDuration = max(2, options.duration)
let fadeIn = min(1.2, titleDuration / 4)
let fadeOut = min(1.6, titleDuration / 3)

func addOpacityAnimation(to layer: CALayer) {
    let animation = CAKeyframeAnimation(keyPath: "opacity")
    animation.beginTime = AVCoreAnimationBeginTimeAtZero
    animation.duration = titleDuration
    animation.values = [0.0, 1.0, 1.0, 0.0]
    animation.keyTimes = [
        0.0,
        NSNumber(value: fadeIn / titleDuration),
        NSNumber(value: max(0, (titleDuration - fadeOut) / titleDuration)),
        1.0,
    ]
    animation.isRemovedOnCompletion = false
    animation.fillMode = .both
    layer.add(animation, forKey: "titleOpacity")
}

if let overlayImagePath = options.overlayImage {
    let overlayURL = URL(fileURLWithPath: overlayImagePath)
    guard let image = NSImage(contentsOf: overlayURL),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail("could not read overlay image")
    }
    let overlayLayer = CALayer()
    overlayLayer.frame = parentLayer.frame
    overlayLayer.contents = cgImage
    overlayLayer.contentsGravity = .resizeAspectFill
    overlayLayer.opacity = 1.0
    addOpacityAnimation(to: overlayLayer)
    parentLayer.addSublayer(overlayLayer)
} else {
    addOpacityAnimation(to: panelLayer)
    addOpacityAnimation(to: titleLayer)
    addOpacityAnimation(to: subtitleLayer)
    parentLayer.addSublayer(panelLayer)
    parentLayer.addSublayer(titleLayer)
    parentLayer.addSublayer(subtitleLayer)
}

videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
    postProcessingAsVideoLayer: videoLayer,
    in: parentLayer
)

guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
    fail("could not create export session")
}
export.outputURL = outputURL
export.outputFileType = .mp4
export.shouldOptimizeForNetworkUse = true
export.videoComposition = videoComposition

let semaphore = DispatchSemaphore(value: 0)
export.exportAsynchronously {
    semaphore.signal()
}
semaphore.wait()

switch export.status {
case .completed:
    print(outputURL.path)
case .failed:
    fail(export.error?.localizedDescription ?? "export failed")
case .cancelled:
    fail("export cancelled")
default:
    fail("export ended with status \(export.status.rawValue)")
}
