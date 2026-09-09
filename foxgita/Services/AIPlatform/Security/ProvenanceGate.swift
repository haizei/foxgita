enum ProvenanceGate {
    static func validate(_ ref: ResourceRef, against seen: SeenSet) throws {
        guard seen.contains(ref) else {
            throw GateRefusal.provenanceRefused(ref)
        }
    }
}
