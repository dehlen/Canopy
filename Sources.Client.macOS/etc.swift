import AppKit

func alert(_ error: Error, title: String = "Unexpected Error", file: StaticString = #file, line: UInt = #line) {
    print("\(file):\(line)", error)

    if let error = error as? PMKHTTPError {
        let (message, title) = error.gitHubDescription(defaultTitle: title)
        alert(message: message, title: title)
    } else {
        alert(message: error.legibleDescription, title: title)
    }
}

func alert(message: String, title: String) {
    func go() {
        let alert = NSAlert()
        alert.informativeText = message
        alert.messageText = title
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    if Thread.isMainThread {
        go()
    } else {
        DispatchQueue.main.async(execute: go)
    }
}

#if !swift(>=4.2)
extension NSStoryboardSegue.Identifier: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
    public init(unicodeScalarLiteral value: String) {
        self.init(value)
    }
    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(value)
    }
}
#endif
