import Foundation

struct LenientElement<Element: Decodable>: Decodable {
	let value: Element?

	init(from decoder: Decoder) throws {
		value = try? Element(from: decoder)
	}
}
