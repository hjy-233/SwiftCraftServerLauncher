import Combine

final class SpotlightActionCenter {
    static let shared = SpotlightActionCenter()

    private let subject = PassthroughSubject<String, Never>()

    var publisher: AnyPublisher<String, Never> {
        subject.eraseToAnyPublisher()
    }

    func send(identifier: String) {
        subject.send(identifier)
    }
}
