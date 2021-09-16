//
//  OptionalDecodableObject.swift
//  absmartly
//
//  Created by Roman Odyshew on 23.08.2021.
//

import Foundation

struct OptionalDecodableObject<Base: Decodable>: Decodable {
    public let value: Base?

    public init(from decoder: Decoder) throws {
        do {
            let container = try decoder.singleValueContainer()
            self.value = try container.decode(Base.self)
        } catch {
            self.value = nil
        }
    }
}
