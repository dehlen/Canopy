import protocol Foundation.LocalizedError

public protocol TitledError: LocalizedError {
    var title: String { get }
}
