import AVFoundation
import Foundation

struct Segment: Decodable {
    let file: String
    let start: Double
    let end: Double
    let duration: Double
}

struct SegmentFile: Decodable {
    let segments: [Segment]
}

struct ClipPlacement {
    let track: AVMutableCompositionTrack
    let start: CMTime
    let duration: CMTime
}

struct Options {
    var segments: String?
    var music: String?
    var output: String?
    var minutes: Double = 30
    var transition: Double = 1.5
}

func fail(_ message: String) -> Never {
    fputs("error: \(message)\n", stderr)
    exit(1)
}

func minTime(_ a: CMTime, _ b: CMTime) -> CMTime {
    CMTimeCompare(a, b) <= 0 ? a : b
}

func maxTime(_ a: CMTime, _ b: CMTime) -> CMTime {
    CMTimeCompare(a, b) >= 0 ? a : b
}

func parseOptions() -> Options {
    var options = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--segments":
            options.segments = args.isEmpty ? nil : args.removeFirst()
        case "--music":
            options.music = args.isEmpty ? nil : args.removeFirst()
        case "--output":
            options.output = args.isEmpty ? nil : args.removeFirst()
        case "--minutes":
            options.minutes = args.isEmpty ? 30 : (Double(args.removeFirst()) ?? 30)
        case "--transition":
            options.transition = args.isEmpty ? 1.5 : (Double(args.removeFirst()) ?? 1.5)
        default:
            fail("unknown option: \(arg)")
        }
    }
    return options
}

let options = parseOptions()
guard let segmentsPath = options.segments,
      let musicPath = options.music,
      let outputPath = options.output else {
    fail("usage: swift tools/make_youtube_from_segments_crossfade.swift --segments fixed_no_camera_ui_segments.json --music music.m4a --output youtube.mp4 [--minutes 30] [--transition 1.5]")
}

let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let segmentsURL = URL(fileURLWithPath: segmentsPath, relativeTo: cwdURL).standardizedFileURL
let baseURL = segmentsURL.deletingLastPathComponent()
let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.removeItem(at: outputURL)

let segmentData = try Data(contentsOf: segmentsURL)
let segmentFile = try JSONDecoder().decode(SegmentFile.self, from: segmentData)
let segments = segmentFile.segments.filter { $0.end > $0.start }
if segments.isEmpty {
    fail("no valid segments")
}

let targetDuration = CMTime(seconds: max(1, options.minutes * 60), preferredTimescale: 600)
let transitionDuration = CMTime(seconds: max(0, options.transition), preferredTimescale: 600)
let composition = AVMutableComposition()

guard let videoA = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
      let videoB = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
    fail("could not create video tracks")
}
let videoTracks = [videoA, videoB]

var placements: [ClipPlacement] = []
var cursor = CMTime.zero
var segmentIndex = 0
var firstTransform: CGAffineTransform?
var renderSize = CGSize(width: 1920, height: 1080)

while cursor < targetDuration {
    let segment = segments[segmentIndex % segments.count]
    let assetURL = baseURL.appendingPathComponent(segment.file)
    let asset = AVURLAsset(url: assetURL)
    guard let sourceVideo = asset.tracks(withMediaType: .video).first else {
        fail("no video track in \(segment.file)")
    }

    if firstTransform == nil {
        firstTransform = sourceVideo.preferredTransform
        let naturalSize = sourceVideo.naturalSize.applying(sourceVideo.preferredTransform)
        renderSize = CGSize(width: abs(naturalSize.width), height: abs(naturalSize.height))
        videoA.preferredTransform = sourceVideo.preferredTransform
        videoB.preferredTransform = sourceVideo.preferredTransform
    }

    let segmentStart = CMTime(seconds: segment.start, preferredTimescale: 600)
    let sourceDuration = CMTime(seconds: segment.end - segment.start, preferredTimescale: 600)
    let usableTransition = minTime(transitionDuration, CMTimeMultiplyByFloat64(sourceDuration, multiplier: 0.5))
    let insertStart = placements.isEmpty ? CMTime.zero : CMTimeSubtract(cursor, usableTransition)
    if insertStart >= targetDuration {
        break
    }

    let duration = minTime(sourceDuration, CMTimeAdd(CMTimeSubtract(targetDuration, insertStart), transitionDuration))
    let range = CMTimeRange(start: segmentStart, duration: duration)
    let track = videoTracks[placements.count % 2]
    try track.insertTimeRange(range, of: sourceVideo, at: insertStart)
    placements.append(ClipPlacement(track: track, start: insertStart, duration: duration))
    cursor = CMTimeAdd(insertStart, duration)
    segmentIndex += 1
}

guard placements.count >= 2 else {
    fail("not enough placements for crossfade timeline")
}

let musicAsset = AVURLAsset(url: URL(fileURLWithPath: musicPath))
guard let musicSourceTrack = musicAsset.tracks(withMediaType: .audio).first else {
    fail("music file has no audio track")
}
guard let musicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
    fail("could not create music track")
}

var musicCursor = CMTime.zero
while musicCursor < targetDuration {
    let remaining = targetDuration - musicCursor
    let chunkDuration = minTime(musicAsset.duration, remaining)
    try musicTrack.insertTimeRange(
        CMTimeRange(start: .zero, duration: chunkDuration),
        of: musicSourceTrack,
        at: musicCursor
    )
    musicCursor = CMTimeAdd(musicCursor, chunkDuration)
}

let audioParams = AVMutableAudioMixInputParameters(track: musicTrack)
audioParams.setVolume(0.95, at: .zero)
let fadeDuration = CMTime(seconds: min(5, max(0, targetDuration.seconds / 10)), preferredTimescale: 600)
audioParams.setVolumeRamp(
    fromStartVolume: 0.95,
    toEndVolume: 0.0,
    timeRange: CMTimeRange(start: CMTimeSubtract(targetDuration, fadeDuration), duration: fadeDuration)
)
let audioMix = AVMutableAudioMix()
audioMix.inputParameters = [audioParams]

var instructions: [AVMutableVideoCompositionInstruction] = []
for i in placements.indices {
    let current = placements[i]
    let currentEnd = CMTimeAdd(current.start, current.duration)
    let nextStart = i + 1 < placements.count ? placements[i + 1].start : targetDuration
    let passStart = i == 0 ? current.start : minTime(CMTimeAdd(current.start, transitionDuration), currentEnd)
    let passEnd = minTime(nextStart, targetDuration)

    if passEnd > passStart {
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: passStart, end: passEnd)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: current.track)
        if let firstTransform {
            layer.setTransform(firstTransform, at: passStart)
        }
        instruction.layerInstructions = [layer]
        instructions.append(instruction)
    }

    guard i + 1 < placements.count else { continue }
    let next = placements[i + 1]
    let transitionStart = next.start
    let transitionEnd = minTime(minTime(currentEnd, CMTimeAdd(next.start, transitionDuration)), targetDuration)
    if transitionEnd > transitionStart {
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: transitionStart, end: transitionEnd)

        let fromLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: current.track)
        let toLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: next.track)
        if let firstTransform {
            fromLayer.setTransform(firstTransform, at: transitionStart)
            toLayer.setTransform(firstTransform, at: transitionStart)
        }
        fromLayer.setOpacityRamp(
            fromStartOpacity: 1.0,
            toEndOpacity: 0.0,
            timeRange: CMTimeRange(start: transitionStart, end: transitionEnd)
        )
        instruction.layerInstructions = [fromLayer, toLayer]
        instructions.append(instruction)
    }
}

let videoComposition = AVMutableVideoComposition()
videoComposition.instructions = instructions
videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
videoComposition.renderSize = renderSize

guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
    fail("could not create export session")
}
export.outputURL = outputURL
export.outputFileType = .mp4
export.shouldOptimizeForNetworkUse = true
export.timeRange = CMTimeRange(start: .zero, duration: targetDuration)
export.videoComposition = videoComposition
export.audioMix = audioMix

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
