public struct APNSConfiguration: Hashable {
    let topic: String
    let isProduction: Bool

    public init(topic: String, isProduction: Bool) {
        self.topic = topic
        self.isProduction = isProduction
    }
}
