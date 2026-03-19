import Foundation

enum AppError: LocalizedError {
    case validation(String)
    case database(String)
    case importUnsupported(String)
    case importCapture(String)
    case importNormalize(String)
    case notFound(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .validation(let message), .database(let message), .importUnsupported(let message), .importCapture(let message), .importNormalize(let message), .notFound(let message), .unknown(let message):
            return message
        }
    }
}
