import Foundation

extension DispatchQueue {
    func syncThrowing<T>(_ block: () throws -> T) throws -> T {
        var result: Result<T, Error>!
        sync {
            result = Result { try block() }
        }
        return try result.get()
    }
}

