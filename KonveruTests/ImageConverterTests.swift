import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Konveru

/// Exercises the real encoder against real files written to a temporary folder.
@Suite(.serialized)
struct ImageConverterTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "KonveruTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: Fixtures

    static func makeImage(width: Int, height: Int, alpha: Bool, noise: Bool = false) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue
        )!
        if noise, let data = context.data {
            let bytes = data.assumingMemoryBound(to: UInt8.self)
            var seed: UInt32 = 12345
            for i in 0..<(context.bytesPerRow * height) {
                seed = seed &* 1_103_515_245 &+ 12345
                bytes[i] = UInt8(truncatingIfNeeded: seed >> 16)
            }
        } else {
            context.setFillColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            context.setFillColor(red: 0.1, green: 0.4, blue: 0.9, alpha: alpha ? 0.5 : 1)
            context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height / 2))
        }
        return context.makeImage()!
    }

    @discardableResult
    func writeFixture(_ name: String, type: UTType, image: CGImage, properties: [CFString: Any] = [:], in folder: URL? = nil) throws -> URL {
        let url = (folder ?? root).appending(path: name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    static let gpsProperties: [CFString: Any] = [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 7.94, kCGImagePropertyGPSLatitudeRef: "S",
            kCGImagePropertyGPSLongitude: 112.95, kCGImagePropertyGPSLongitudeRef: "E",
        ],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "Konveru Test Lens"],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "KonveruCam"],
    ]

    func properties(of url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.webP.identifier)
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    func webPChunks(_ url: URL) throws -> Set<String> {
        let bytes = try [UInt8](Data(contentsOf: url))
        var chunks = Set<String>()
        var offset = 12
        while offset + 8 <= bytes.count {
            chunks.insert(String(decoding: bytes[offset..<offset + 4], as: UTF8.self))
            let size = Int(bytes[offset + 4]) | Int(bytes[offset + 5]) << 8 | Int(bytes[offset + 6]) << 16 | Int(bytes[offset + 7]) << 24
            offset += 8 + size + (size & 1)
        }
        return chunks
    }

    // MARK: Conversions

    @Test func jpegWithLocationIsRotatedAndStripped() throws {
        let source = try writeFixture("Pasar Baru 01.jpg", type: .jpeg, image: Self.makeImage(width: 400, height: 200, alpha: false), properties: Self.gpsProperties)
        let output = try ImageConverter.convertNow(source, into: root.appending(path: "Konveru"), baseName: "Pasar Baru 01", options: ConversionOptions())

        #expect(output.url.lastPathComponent == "Pasar Baru 01.webp")
        #expect(output.size > 0)
        let props = try properties(of: output.url)
        // Orientation 6 is baked in: 400×200 becomes 200×400 and EXIF says "up".
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 200)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 400)
        #expect((props[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFMake] as? String == "KonveruCam")
        #expect(try webPChunks(output.url).contains("EXIF"))
        // The source is untouched.
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func keepingLocationKeepsGPS() throws {
        let source = try writeFixture("gps.jpg", type: .jpeg, image: Self.makeImage(width: 64, height: 64, alpha: false), properties: Self.gpsProperties)
        var options = ConversionOptions()
        options.removeLocation = false
        let output = try ImageConverter.convertNow(source, into: root, baseName: "gps", options: options)
        let gps = try properties(of: output.url)[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        #expect((gps?[kCGImagePropertyGPSLatitude] as? Double).map { abs($0 - 7.94) < 0.01 } == true)
    }

    @Test func droppingMetadataWritesNoExif() throws {
        let source = try writeFixture("plain.jpg", type: .jpeg, image: Self.makeImage(width: 64, height: 64, alpha: false), properties: Self.gpsProperties)
        var options = ConversionOptions()
        options.keepMetadata = false
        let output = try ImageConverter.convertNow(source, into: root, baseName: "plain", options: options)
        let chunks = try webPChunks(output.url)
        #expect(!chunks.contains("EXIF"))
        #expect(!chunks.contains("XMP "))
    }

    @Test func transparentPNGKeepsAlpha() throws {
        let source = try writeFixture("logo-mark.png", type: .png, image: Self.makeImage(width: 128, height: 96, alpha: true))
        for lossless in [false, true] {
            var options = ConversionOptions()
            options.lossless = lossless
            let output = try ImageConverter.convertNow(source, into: root.appending(path: lossless ? "lossless" : "lossy"), baseName: "logo-mark", options: options)
            let props = try properties(of: output.url)
            #expect(props[kCGImagePropertyHasAlpha] as? Bool == true)
            #expect(props[kCGImagePropertyPixelWidth] as? Int == 128)
            #expect(try webPChunks(output.url).contains(lossless ? "VP8L" : "ALPH"))
        }
    }

    @Test func losslessIsPixelExactForOpaqueImage() throws {
        let image = Self.makeImage(width: 32, height: 32, alpha: false)
        let source = try writeFixture("exact.png", type: .png, image: image)
        var options = ConversionOptions()
        options.lossless = true
        let output = try ImageConverter.convertNow(source, into: root, baseName: "exact", options: options)

        func pixels(_ url: URL) throws -> [UInt8] {
            let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let decoded = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
            var buffer = [UInt8](repeating: 0, count: 32 * 32 * 4)
            let context = CGContext(data: &buffer, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.draw(decoded, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            return buffer
        }
        #expect(try pixels(output.url) == pixels(source))
    }

    @Test func heicConverts() throws {
        guard (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains(UTType.heic.identifier) == true else { return }
        let source = try writeFixture("IMG_2041.heic", type: .heic, image: Self.makeImage(width: 300, height: 200, alpha: false), properties: Self.gpsProperties)
        let output = try ImageConverter.convertNow(source, into: root, baseName: "IMG_2041", options: ConversionOptions())
        let props = try properties(of: output.url)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 200)
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func displayP3ProfileIsEmbedded() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: p3, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let source = try writeFixture("p3.png", type: .png, image: context.makeImage()!)
        let output = try ImageConverter.convertNow(source, into: root, baseName: "p3", options: ConversionOptions())
        #expect(try webPChunks(output.url).contains("ICCP"))
        let profile = try properties(of: output.url)[kCGImagePropertyProfileName] as? String
        #expect(profile?.contains("P3") == true)
    }

    // MARK: Names and collisions

    @Test func existingOutputsAreNeverOverwritten() throws {
        let source = try writeFixture("IMG_2044.jpg", type: .jpeg, image: Self.makeImage(width: 32, height: 32, alpha: false))
        let existing = root.appending(path: "IMG_2044.webp")
        try Data("keep me".utf8).write(to: existing)

        let first = try ImageConverter.convertNow(source, into: root, baseName: "IMG_2044", options: ConversionOptions())
        let second = try ImageConverter.convertNow(source, into: root, baseName: "IMG_2044", options: ConversionOptions())
        #expect(first.url.lastPathComponent == "IMG_2044 2.webp")
        #expect(second.url.lastPathComponent == "IMG_2044 3.webp")
        #expect(try String(contentsOf: existing, encoding: .utf8) == "keep me")
        // No partial files are left behind.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".konveru-partial") }
        #expect(leftovers.isEmpty)
    }

    @Test func unicodeNamesArePreserved() throws {
        let source = try writeFixture("Pantai – senja 日本.png", type: .png, image: Self.makeImage(width: 16, height: 16, alpha: false))
        let output = try ImageConverter.convertNow(source, into: root, baseName: "Pantai – senja 日本", options: ConversionOptions())
        #expect(output.url.lastPathComponent == "Pantai – senja 日本.webp")
    }

    @Test func queuePredictsCollisionsBetweenItems() async throws {
        let a = root.appending(path: "A", directoryHint: .isDirectory)
        let b = root.appending(path: "A/sub", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        try writeFixture("IMG_1.jpg", type: .jpeg, image: Self.makeImage(width: 8, height: 8, alpha: false), in: a)
        try writeFixture("IMG_1.png", type: .png, image: Self.makeImage(width: 8, height: 8, alpha: false), in: b)
        try Data("hello".utf8).write(to: a.appending(path: "notes.txt"))

        let scan = await FileScanner.scan([a])
        #expect(scan.items.count == 2)
        #expect(scan.notices.first?.skippedNames == ["notes.txt"])

        let defaults = try #require(UserDefaults(suiteName: "KonveruTests-\(UUID().uuidString)"))
        let settings = ConversionSettings(defaults: defaults)
        settings.keepFolderStructure = false
        let queue = ConversionQueue(settings: settings)
        queue.add([a])
        for _ in 0..<100 where queue.items.isEmpty { try await Task.sleep(for: .milliseconds(20)) }

        #expect(queue.destinationRoot?.lastPathComponent == "Konveru")
        let names = Set(queue.outputNames.values)
        #expect(names == ["IMG_1.webp", "IMG_1 2.webp"])

        settings.keepFolderStructure = true
        #expect(Set(queue.outputNames.values) == ["IMG_1.webp"])
    }

    @Test func folderWithoutImagesIsReported() async throws {
        let folder = root.appending(path: "Videos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([0, 1, 2]).write(to: folder.appending(path: "clip.mov"))
        try Data([0, 1, 2]).write(to: folder.appending(path: "shot.cr2"))
        let scan = await FileScanner.scan([folder])
        #expect(scan.items.isEmpty)
        let notice = try #require(scan.notices.first)
        #expect(notice.folderHadNoImages)
        #expect(Set(notice.skippedKinds) == ["MOV", "RAW"])
    }

    // MARK: Failures

    @Test func corruptFileFailsWithActionableMessage() throws {
        let source = root.appending(path: "broken.jpg")
        try Data((0..<2048).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: source)
        #expect {
            try ImageConverter.convertNow(source, into: root, baseName: "broken", options: ConversionOptions())
        } throws: { error in
            (error as? ConversionFailure)?.message.contains("may be damaged") == true
        }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "broken.webp").path))
    }

    @Test func unreadableFileFails() throws {
        let source = try writeFixture("locked.png", type: .png, image: Self.makeImage(width: 8, height: 8, alpha: false))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: source.path) }
        #expect {
            try ImageConverter.convertNow(source, into: root, baseName: "locked", options: ConversionOptions())
        } throws: { error in
            (error as? ConversionFailure)?.message == "Couldn’t read locked.png. Check file access, then retry."
        }
    }

    @Test func readOnlyDestinationFails() throws {
        let source = try writeFixture("ok.png", type: .png, image: Self.makeImage(width: 8, height: 8, alpha: false))
        let destination = root.appending(path: "ReadOnly", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: destination.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path) }
        #expect {
            try ImageConverter.convertNow(source, into: destination, baseName: "ok", options: ConversionOptions())
        } throws: { error in
            (error as? ConversionFailure)?.message.contains("can’t save to “ReadOnly”") == true
        }
    }

    @Test func outOfSpaceMessageNamesVolume() {
        let failure = ImageConverter.writeFailure(CocoaError(.fileWriteOutOfSpace), directory: root, outputName: "Sunrise Bromo.webp")
        #expect(failure.message.hasPrefix("Not enough space on “"))
        #expect(failure.message.hasSuffix("to write Sunrise Bromo.webp. Free up space, then retry."))
    }

    @Test func cancellationStopsEncodingAndLeavesNoFiles() async throws {
        let source = try writeFixture("big.png", type: .png, image: Self.makeImage(width: 4000, height: 4000, alpha: false, noise: true))
        let destination = root.appending(path: "cancel", directoryHint: .isDirectory)
        var options = ConversionOptions()
        options.lossless = true
        let task = Task {
            try await ImageConverter.convert(source, into: destination, baseName: "big", options: options)
        }
        try await Task.sleep(for: .milliseconds(400))
        task.cancel()
        let started = ContinuousClock.now
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ContinuousClock.now - started < .seconds(3))
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []
        #expect(contents.isEmpty)
    }
}
