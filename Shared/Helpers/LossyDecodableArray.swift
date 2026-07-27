import Foundation

/// Wraps a `Decodable` so a failed decode yields `nil` instead of throwing.
///
/// Used to decode an array lossily: decode `[Lossy<T>]` then `compactMap`, so a
/// single malformed element (e.g. one written by a newer app version with an
/// unknown enum case) is dropped while every valid sibling survives, instead of
/// the whole blob failing to decode. Shared by the composable popover and menu
/// bar composition models.
struct Lossy<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

extension KeyedDecodingContainer {
    /// Decodes an array at `key`, silently dropping elements that fail to
    /// decode. Missing key -> empty array. Never throws.
    func decodeLossyArray<Element: Decodable>(
        _ type: Element.Type,
        forKey key: Key
    ) -> [Element] {
        let wrapped = (try? decodeIfPresent([Lossy<Element>].self, forKey: key)) ?? []
        return wrapped.compactMap(\.value)
    }
}
