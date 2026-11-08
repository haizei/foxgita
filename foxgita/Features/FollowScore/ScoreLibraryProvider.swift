import Foundation

@MainActor enum ScoreLibraryProvider {
    private static var libraries: [UUID: ScoreLibrary] = [:]
    static func library(profileID: UUID) throws -> ScoreLibrary {
        if let library = libraries[profileID] { return library }
        let library = try ScoreLibrary(directory: ScoreLibrary.defaultDirectory,profileID: profileID)
        libraries[profileID] = library
        return library
    }
}
