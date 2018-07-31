#if !swift(>=4.1.5)
public extension Collection where Element: Equatable {
    func firstIndex(of member: Element) -> Self.Index? {
        return self.index(of: member)
    }
}
#endif
