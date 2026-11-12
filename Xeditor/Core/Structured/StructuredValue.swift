import Foundation

/// Ordered value tree shared by the JSON and YAML converters. Objects keep
/// their key order and numbers keep their original text, so a conversion does
/// not reorder keys or lose numeric precision.
indirect enum StructuredValue {
    case object([(String, StructuredValue)])
    case array([StructuredValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
}
