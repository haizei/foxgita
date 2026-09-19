import Foundation

enum VisionPracticeError: Error, Equatable {
    case invalidURL
    case unauthorized
    case httpStatus(Int)
    case emptyContent
    case invalidJSON
    case timeout
    case transport
    case unregisteredSkill
}

typealias AIClientError = VisionPracticeError
