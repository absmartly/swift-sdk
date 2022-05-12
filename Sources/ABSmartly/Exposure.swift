import Foundation

public class Exposure: Encodable, Equatable {
	let id: Int
	let name: String
	let unit: String?
	let variant: Int
	let exposedAt: Int64
	let assigned: Bool
	let eligible: Bool
	let overridden: Bool
	let fullOn: Bool
	let custom: Bool
	let audienceMismatch: Bool

	init(
		_ id: Int, _ name: String, _ unit: String?, _ variant: Int, _ exposedAt: Int64, _ assigned: Bool,
		_ eligible: Bool, _ overridden: Bool, _ fullOn: Bool, _ custom: Bool, _ audienceMismatch: Bool
	) {
		self.id = id
		self.name = name
		self.unit = unit
		self.variant = variant
		self.exposedAt = exposedAt
		self.assigned = assigned
		self.eligible = eligible
		self.overridden = overridden
		self.fullOn = fullOn
		self.custom = custom
		self.audienceMismatch = audienceMismatch
	}

	public static func == (lhs: Exposure, rhs: Exposure) -> Bool {
		return lhs.id == rhs.id && lhs.name == rhs.name && lhs.unit == rhs.unit && lhs.variant == rhs.variant
			&& lhs.exposedAt == rhs.exposedAt && lhs.assigned == rhs.assigned && lhs.eligible == rhs.eligible
			&& lhs.overridden == rhs.overridden && lhs.fullOn == rhs.fullOn && lhs.custom == rhs.custom
			&& lhs.audienceMismatch == rhs.audienceMismatch
	}
}
