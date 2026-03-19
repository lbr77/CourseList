import Combine
import ConfigurableKit
import Foundation

public final class MemoryKeyValueStorage: KeyValueStorage {
    public var valueUpdatePublisher: PassthroughSubject<(String, Data?), Never> { Self.valueUpdatePublisher }
    public static var valueUpdatePublisher = PassthroughSubject<(String, Data?), Never>()
    private var storage: [String: Data] = [:]

    public init() {}

    public static func printEveryValueChange() {}

    public func value(forKey key: String) -> Data? {
        storage[key]
    }

    public func setValue(_ data: Data?, forKey key: String) {
        storage[key] = data
        Self.valueUpdatePublisher.send((key, data))
    }
}
