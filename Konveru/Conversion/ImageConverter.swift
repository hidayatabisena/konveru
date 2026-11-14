import Accelerate
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decodes JPEG, PNG, HEIC (and WebP for re-encoding) with ImageIO and encodes WebP
/// with the statically linked libwebp. Never overwrites: output is written to a
/// temporary file, then moved into place with an exclusive rename.
nonisolated enum ImageConverter {
    struct Output: Sendable {
        let url: URL
        let size: Int64
    }

    static let maxDimension = Int(WEBP_MAX_DIMENSION)

    @concurrent
    static func convert(
        _ source: URL,
        into directory: URL,
        baseName: String,
        options: ConversionOptions
    ) async throws -> Output {
        try convertNow(source, into: directory, baseName: baseName, options: options)
    }

    static func convertNow(
        _ source: URL,
        into directory: URL,
        baseName: String,
        options: ConversionOptions
    ) throws -> Output {
        let fileName = source.lastPathComponent
        let outputName = FileNaming.name(baseName, extension: OutputFormat.webp.fileExtension, attempt: 1)

        guard FileManager.default.isReadableFile(atPath: source.path) else {
            throw ConversionFailure(
                message: String(localized: "Couldn’t read \(fileName). Check file access, then retry."),
                details: "The file isn’t readable by Konveru: \(source.path)"
            )
        }
        guard
            let imageSource = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            CGImageSourceGetCount(imageSource) > 0,
            let image = decode(imageSource)
        else {
            throw ConversionFailure(
                message: String(localized: "Couldn’t open \(fileName) as an image. The file may be damaged."),
                details: "ImageIO couldn’t decode \(source.path)."
            )
        }
        guard image.width <= maxDimension, image.height <= maxDimension else {
            throw ConversionFailure(
                message: String(localized: "\(fileName) is too large for WebP. The limit is 16,383 pixels per side."),
                details: "Image is \(image.width) × \(image.height) pixels; WebP allows at most \(maxDimension)."
            )
        }
        try Task.checkCancellation()

        let colorSpace = workingColorSpace(for: image)
        var webp = try encode(image, colorSpace: colorSpace, options: options, fileName: fileName)

        let icc = colorSpace.name == CGColorSpace.sRGB ? nil : colorSpace.copyICCData() as Data?
        let metadata = options.keepMetadata
            ? metadataChunks(from: imageSource, width: image.width, height: image.height, removeLocation: options.removeLocation)
            : (exif: nil, xmp: nil)
        webp = try assemble(webp, icc: icc, exif: metadata.exif, xmp: metadata.xmp, fileName: fileName)
        try Task.checkCancellation()

        let url = try write(webp, into: directory, baseName: baseName, outputName: outputName)
        try verify(url, width: image.width, height: image.height)
        return Output(url: url, size: Int64(webp.count))
    }

    // MARK: Decoding

    private static func decode(_ source: CGImageSource) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        if orientation == 1 {
            return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
        // Bake EXIF orientation into the pixels; the written EXIF says "up".
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Keep RGB color spaces (Display P3 photos stay P3, with their profile embedded);
    /// convert gray, CMYK and indexed images to sRGB.
    private static func workingColorSpace(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb, space.copyICCData() != nil {
            return space
        }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    // MARK: Encoding

    private static func encode(_ image: CGImage, colorSpace: CGColorSpace, options: ConversionOptions, fileName: String) throws -> Data {
        func failure(_ details: String) -> ConversionFailure {
            ConversionFailure(message: String(localized: "Couldn’t convert \(fileName) to WebP."), details: details)
        }

        guard let format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue) // WebP wants unpremultiplied RGBA
        ) else { throw failure("Unsupported pixel format.") }

        var buffer: vImage_Buffer
        do {
            buffer = try vImage_Buffer(cgImage: image, format: format)
        } catch {
            throw failure("Couldn’t read pixels: \(error)")
        }
        defer { buffer.free() }

        var config = WebPConfig()
        guard WebPConfigPreset(&config, WEBP_PRESET_DEFAULT, Float(options.quality)) != 0 else {
            throw failure("libwebp version mismatch.")
        }
        if options.lossless {
            config.lossless = 1
            config.quality = 75
        }
        config.method = 4
        guard WebPValidateConfig(&config) != 0 else { throw failure("Invalid encoder settings.") }

        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else { throw failure("libwebp version mismatch.") }
        defer { WebPPictureFree(&picture) }
        picture.use_argb = 1
        picture.width = Int32(image.width)
        picture.height = Int32(image.height)
        guard WebPPictureImportRGBA(&picture, buffer.data.assumingMemoryBound(to: UInt8.self), Int32(buffer.rowBytes)) != 0 else {
            throw failure("Out of memory while importing pixels.")
        }

        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        picture.writer = WebPMemoryWrite
        // libwebp polls this while encoding, so Cancel interrupts large images safely.
        picture.progress_hook = { _, _ in Task.isCancelled ? 0 : 1 }

        let succeeded = withUnsafeMutablePointer(to: &writer) { writerPointer in
            picture.custom_ptr = UnsafeMutableRawPointer(writerPointer)
            return WebPEncode(&config, &picture)
        }
        guard succeeded != 0 else {
            if picture.error_code == VP8_ENC_ERROR_USER_ABORT { throw CancellationError() }
            throw failure("libwebp error \(picture.error_code.rawValue).")
        }
        return Data(bytes: writer.mem, count: writer.size)
    }

    // MARK: Metadata

    /// Serializes the source metadata (minus location, with orientation reset) through a
    /// 1×1 JPEG so ImageIO produces standard EXIF and XMP payloads for the WebP chunks.
    static func metadataChunks(from source: CGImageSource, width: Int, height: Int, removeLocation: Bool) -> (exif: Data?, xmp: Data?) {
        guard
            let original = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
            let metadata = CGImageMetadataCreateMutableCopy(original)
        else { return (nil, nil) }

        if removeLocation { removeLocationTags(from: metadata) }
        CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, 1 as CFNumber)
        CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelXDimension, width as CFNumber)
        CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelYDimension, height as CFNumber)

        let jpeg = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil),
            let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
            let pixel = context.makeImage()
        else { return (nil, nil) }
        CGImageDestinationAddImageAndMetadata(destination, pixel, metadata, nil)
        guard CGImageDestinationFinalize(destination) else { return (nil, nil) }
        return jpegMetadataSegments(jpeg as Data)
    }

    private static func removeLocationTags(from metadata: CGMutableImageMetadata) {
        let textualLocation: Set<String> = ["City", "State", "Country", "Location", "CountryCode", "LocationCreated", "LocationShown", "Sublocation"]
        var paths: [String] = []
        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, [kCGImageMetadataEnumerateRecursively: true] as CFDictionary) { path, tag in
            let name = CGImageMetadataTagCopyName(tag) as String? ?? ""
            let prefix = CGImageMetadataTagCopyPrefix(tag) as String? ?? ""
            let isTextualLocation = ["photoshop", "Iptc4xmpCore", "Iptc4xmpExt"].contains(prefix) && textualLocation.contains(name)
            if name.hasPrefix("GPS") || isTextualLocation {
                paths.append(path as String)
            }
            return true
        }
        // Remove deepest paths first so parents don't invalidate children.
        for path in paths.sorted(by: { $0.count > $1.count }) {
            CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString)
        }
    }

    static func jpegMetadataSegments(_ jpeg: Data) -> (exif: Data?, xmp: Data?) {
        let bytes = [UInt8](jpeg)
        let exifSignature = Array("Exif\0\0".utf8)
        let xmpSignature = Array("http://ns.adobe.com/xap/1.0/\0".utf8)
        var exif: Data?
        var xmp: Data?
        var index = 2 // skip SOI
        while index + 4 <= bytes.count, bytes[index] == 0xFF {
            let marker = bytes[index + 1]
            if marker == 0xDA || marker == 0xD9 { break } // start of scan / end of image
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            let end = index + 2 + length
            guard length >= 2, end <= bytes.count else { break }
            if marker == 0xE1 {
                let payload = bytes[(index + 4)..<end]
                if payload.starts(with: exifSignature) {
                    exif = Data(payload.dropFirst(exifSignature.count))
                } else if payload.starts(with: xmpSignature) {
                    xmp = Data(payload.dropFirst(xmpSignature.count))
                }
            }
            index = end
        }
        return (exif, xmp)
    }

    private static func assemble(_ webp: Data, icc: Data?, exif: Data?, xmp: Data?, fileName: String) throws -> Data {
        guard icc != nil || exif != nil || xmp != nil else { return webp }
        let failure = ConversionFailure(
            message: String(localized: "Couldn’t add metadata to \(fileName). Try again without keeping metadata."),
            details: "libwebpmux couldn’t assemble the file."
        )
        return try webp.withUnsafeBytes { raw in
            var bitstream = WebPData(bytes: raw.bindMemory(to: UInt8.self).baseAddress, size: raw.count)
            guard let mux = WebPMuxCreate(&bitstream, 1) else { throw failure }
            defer { WebPMuxDelete(mux) }

            for (fourCC, payload) in [("ICCP", icc), ("EXIF", exif), ("XMP ", xmp)] {
                guard let payload else { continue }
                let status = payload.withUnsafeBytes { chunkBytes in
                    var chunk = WebPData(bytes: chunkBytes.bindMemory(to: UInt8.self).baseAddress, size: chunkBytes.count)
                    return WebPMuxSetChunk(mux, fourCC, &chunk, 1)
                }
                guard status == WEBP_MUX_OK else { throw failure }
            }

            var assembled = WebPData()
            WebPDataInit(&assembled)
            defer { WebPDataClear(&assembled) }
            guard WebPMuxAssemble(mux, &assembled) == WEBP_MUX_OK else { throw failure }
            return Data(bytes: assembled.bytes, count: assembled.size)
        }
    }

    // MARK: Writing

    private static func write(_ data: Data, into directory: URL, baseName: String, outputName: String) throws -> URL {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporary = directory.appending(path: ".\(UUID().uuidString).konveru-partial")
            try data.write(to: temporary, options: .withoutOverwriting)
            defer { try? fileManager.removeItem(at: temporary) }

            for attempt in 1...10_000 {
                let candidate = directory.appending(path: FileNaming.name(baseName, extension: OutputFormat.webp.fileExtension, attempt: attempt))
                // RENAME_EXCL fails instead of replacing an existing file, even if one appears mid-batch.
                if renamex_np(temporary.path, candidate.path, UInt32(RENAME_EXCL)) == 0 {
                    return candidate
                }
                guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            }
            throw POSIXError(.EEXIST)
        } catch {
            throw writeFailure(error, directory: directory, outputName: outputName)
        }
    }

    static func writeFailure(_ error: Error, directory: URL, outputName: String) -> ConversionFailure {
        let nsError = error as NSError
        let posixCode = (nsError.domain == NSPOSIXErrorDomain ? nsError : nsError.userInfo[NSUnderlyingErrorKey] as? NSError)
            .flatMap { $0.domain == NSPOSIXErrorDomain ? Int32($0.code) : nil }
        let folder = directory.lastPathComponent
        let volume = volumeName(containing: directory)

        let message: String
        switch (nsError.domain, nsError.code, posixCode) {
        case (NSCocoaErrorDomain, CocoaError.fileWriteOutOfSpace.rawValue, _), (_, _, ENOSPC), (_, _, EDQUOT):
            message = String(localized: "Not enough space on “\(volume)” to write \(outputName). Free up space, then retry.")
        case (NSCocoaErrorDomain, CocoaError.fileWriteVolumeReadOnly.rawValue, _), (_, _, EROFS):
            message = String(localized: "“\(volume)” is read-only. Choose another destination, then retry.")
        case (NSCocoaErrorDomain, CocoaError.fileWriteNoPermission.rawValue, _), (_, _, EACCES), (_, _, EPERM):
            message = String(localized: "Konveru can’t save to “\(folder)”. Choose another destination or check the folder’s permissions, then retry.")
        default:
            message = String(localized: "Couldn’t save \(outputName) to “\(folder)”. Check the destination, then retry.")
        }
        return ConversionFailure(message: message, details: "\(nsError.localizedDescription)\n\(nsError)")
    }

    private static func volumeName(containing url: URL) -> String {
        var candidate = url
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.pathComponents.count > 1 {
            candidate.deleteLastPathComponent()
        }
        return (try? candidate.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "disk"
    }

    // MARK: Verification

    /// A file is Done only after it decodes again at the expected size.
    private static func verify(_ url: URL, width: Int, height: Int) throws {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
           image.width == width, image.height == height {
            return
        }
        try? FileManager.default.removeItem(at: url)
        throw ConversionFailure(
            message: String(localized: "\(url.lastPathComponent) was written but couldn’t be read back, so it was removed. Retry the conversion."),
            details: "Verification decode failed for \(url.path)."
        )
    }
}
