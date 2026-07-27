import Foundation

/// A user-saved composition, named and recallable. Generic over the
/// composition type so the same container serves the composable popover
/// (`UserTemplate<PopoverComposition>`) and, later, the composable menu bar.
///
/// The field layout (`id`, `name`, `composition`) is deliberately identical to
/// the pre-generic `PopoverUserTemplate`, so the persisted
/// `popoverUserTemplates` JSON blob decodes unchanged.
struct UserTemplate<Composition: Codable & Equatable>: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var composition: Composition

    init(id: UUID = UUID(), name: String, composition: Composition) {
        self.id = id
        self.name = name
        self.composition = composition
    }
}
