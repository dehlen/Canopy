#if !swift(>=4.1.5)
public extension Collection where Element: Equatable {
    func firstIndex(of member: Element) -> Self.Index? {
        return self.index(of: member)
    }
}
#endif

public extension Sequence {
    //@inlinable
    func map<T>(_ keyPath: KeyPath<Element, T>) -> [T] {
        return map {
            $0[keyPath: keyPath]
        }
    }

    //@inlinable
    func compactMap<T>(_ keyPath: KeyPath<Element, T?>) -> [T] {
        return compactMap {
            $0[keyPath: keyPath]
        }
    }
}

import struct Foundation.Data

public extension Data {
    var xor: Data {
        return Data(map{ $0 ^ 176 })
    }
}
