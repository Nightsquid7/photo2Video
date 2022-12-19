import CoreImage
import AVFoundation
import VideoToolbox
import Combine

final class Exporter {

    var completion: ((Result<URL, Error>) -> Void)?
    var configuration: Configuration!

    private let context = CIContext()
    private var writer: AVAssetWriter!
    private let inputQueue = DispatchQueue(label: "inputQueue")

    private var input: AVAssetWriterInput!
    private var pixelAdapter: AVAssetWriterInputPixelBufferAdaptor!
    private var pixelAdapterBufferAttributes: [String: Int]!

    struct Configuration {
        let outputURL: URL
        let fileType: AVFileType
        let exportDimensions: CGSize
        let frameRate: Int

        init(outputURL: URL, fileType: AVFileType, exportDimensions: CGSize, frameRate: Int = 30) {
            self.outputURL = outputURL
            self.fileType = fileType
            self.exportDimensions = exportDimensions
            self.frameRate = frameRate
        }
    }

    func setupExporter(with configuration: Configuration) {
        do {
            if FileManager.default.contents(atPath: configuration.outputURL.path) != nil {
                print("Remove item at \(configuration.outputURL)")
                try FileManager.default.removeItem(at: configuration.outputURL)
            }
            self.writer = try AVAssetWriter(outputURL: configuration.outputURL, fileType: configuration.fileType)
        } catch {
            fatalError("Could not create AVAssetWriter with \(configuration)")
        }
        self.configuration = configuration

        input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings(with: configuration.exportDimensions))
        // TODO: Should we remove inputs here?
        writer.add(input)

        self.pixelAdapterBufferAttributes = [ kCVPixelBufferPixelFormatTypeKey as String : Int(kCMPixelFormat_32BGRA)]
        pixelAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                                sourcePixelBufferAttributes: pixelAdapterBufferAttributes)
    }

    private var pixelBuffer: CVPixelBuffer?
    func pixelBuffer(from ciImage: CIImage) -> CVPixelBuffer {
            CVPixelBufferCreate(kCFAllocatorDefault,
                                Int(ciImage.extent.width),
                                Int(ciImage.extent.height),
                                kCVPixelFormatType_32BGRA,
                                self.pixelAdapterBufferAttributes as CFDictionary,
                                &pixelBuffer)
            guard let pixelBuffer = pixelBuffer else {
                fatalError("Could not allocate pixel buffer ")
            }
            context.render(ciImage, to: pixelBuffer)

            return pixelBuffer
    }

    // create a movie from a single image with a given duration
    func createMovieFrom(photoURL: URL, seconds: Int) {
        guard let ciImage = CIImage(contentsOf: photoURL) else {
            fatalError("could not get contents of image from \(photoURL)")
        }

        let outputURL = FileManager.documentsDirectory!.appendingPathComponent("test_exported_video.mp4", isDirectory: false)

        if let _ = FileManager.default.contents(atPath: outputURL.path) {
          do {
            try FileManager.default.removeItem(at: outputURL)
          } catch {
            print("error removing item \(error.localizedDescription)")
          }
        }

        setupExporter(with: Configuration(outputURL: outputURL, fileType: .m4a, exportDimensions: ciImage.extent.size))

        writer.startWriting()
        writer.startSession(atSourceTime: CMTime.zero)

        let pixelBuffer = pixelBuffer(from: ciImage)

        let frameCount = seconds * self.configuration.frameRate
        var currentFrame = 0

        input.requestMediaDataWhenReady(on: inputQueue, using: {

            while self.input.isReadyForMoreMediaData && currentFrame < frameCount {
                let presentationTime = CMTimeMake(value: Int64(currentFrame), timescale: Int32(self.configuration.frameRate))
                self.pixelAdapter.append(pixelBuffer, withPresentationTime: presentationTime)
                print("appended pixel at \(presentationTime), currentFrameNumber \(currentFrame)")
                currentFrame += 1
            }

            if currentFrame == frameCount {
                self.input.markAsFinished()

                self.writer.finishWriting {
                    if let error = self.writer.error {
                      print("error")
                      self.completion?(.failure(error))
                      return
                    }

                  print(outputURL)
                  self.completion?(.success(outputURL))
                }
            }
        })


    }
}


extension Exporter {
    func videoSettings(with size: CGSize) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [
                kVTCompressionPropertyKey_AverageBitRate: 6_000_000,
                kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_AutoLevel
            ]
        ]

    }

    static func timesForDuration(seconds: Int, frameRate: Int) -> [CMTime] {
        var times: [CMTime] = []
        for frameCount in 0..<(seconds * frameRate) {
            times.append(CMTime(value: CMTimeValue(frameCount), timescale: 30))
        }
        return times
    }
}

extension FileManager {
  static var documentsDirectory: URL? {
    let documentsDirectory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)

    return documentsDirectory
  }
}
