import CoreFoundation
import Foundation

/// A decoded file together with the information needed to write it back the
/// way it came off disk (same encoding, same BOM).
struct DecodedFile {
    let text: String
    let encoding: String.Encoding
    let hadBOM: Bool
}

/// Encoding detection for files that are not open in the editor. Mirrors the
/// order EditorBridge uses when loading a document, but stays Foundation-only
/// so directory search can run off the main thread.
enum FileEncodingDetector {
    static let gb18030: String.Encoding = {
        let raw = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String.Encoding(rawValue: raw)
    }()

    static func decode(_ data: Data) -> DecodedFile? {
        var hadBOM = false
        var payload = data
        var encoding = detect(data)

        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            payload = data.dropFirst(3)
            encoding = .utf8
            hadBOM = true
        } else if data.starts(with: [0xFF, 0xFE]) {
            payload = data.dropFirst(2)
            encoding = .utf16LittleEndian
            hadBOM = true
        } else if data.starts(with: [0xFE, 0xFF]) {
            payload = data.dropFirst(2)
            encoding = .utf16BigEndian
            hadBOM = true
        }

        guard let text = String(data: payload, encoding: encoding) else { return nil }
        return DecodedFile(text: text, encoding: encoding, hadBOM: hadBOM)
    }

    static func detect(_ data: Data) -> String.Encoding {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return .utf8 }
        if data.starts(with: [0xFF, 0xFE]) { return .utf16LittleEndian }
        if data.starts(with: [0xFE, 0xFF]) { return .utf16BigEndian }

        if String(data: data, encoding: .utf8) != nil {
            return .utf8
        }
        if String(data: data, encoding: gb18030) != nil {
            return gb18030
        }
        return .isoLatin1
    }

    /// Re-encodes text for disk, restoring the BOM the original file had.
    static func encode(_ text: String, encoding: String.Encoding, hadBOM: Bool) -> Data? {
        guard var data = text.data(using: encoding) else { return nil }
        if hadBOM {
            switch encoding {
            case .utf8:
                data.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0)
            case .utf16LittleEndian:
                data.insert(contentsOf: [0xFF, 0xFE], at: 0)
            case .utf16BigEndian:
                data.insert(contentsOf: [0xFE, 0xFF], at: 0)
            default:
                break
            }
        }
        return data
    }
}
