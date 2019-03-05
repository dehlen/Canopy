public enum APNsError: Error {
    case badToken(String)
    case reason(String)
    case fundamental(String)
}
