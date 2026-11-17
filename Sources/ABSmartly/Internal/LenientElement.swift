import Foundation

// Decodes an array element without failing the whole array when the element is malformed.
struct LenientElement<Element: Decodable>: Decodable {
	let value: Element?

	init(from decoder: Decoder) throws {
		value = try? Element(from: decoder)
	}
}
