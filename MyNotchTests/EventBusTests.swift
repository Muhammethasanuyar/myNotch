import XCTest
@testable import MyNotch

@MainActor
final class EventBusTests: XCTestCase {
    private let event = NotchEvent(moduleID: "demo", title: "Hello")

    func testDeliversToEverySubscriber() {
        let bus = EventBus()
        var first: [EventBus.Message] = []
        var second: [EventBus.Message] = []
        let a = bus.subscribe { first.append($0) }
        let b = bus.subscribe { second.append($0) }

        bus.post(.popup(event))
        bus.post(.activityChanged(moduleID: "demo"))

        XCTAssertEqual(first, [.popup(event), .activityChanged(moduleID: "demo")])
        XCTAssertEqual(second, first)
        a.invalidate()
        b.invalidate()
    }

    func testInvalidatedSubscriptionStopsReceiving() {
        let bus = EventBus()
        var received: [EventBus.Message] = []
        let subscription = bus.subscribe { received.append($0) }

        bus.post(.popup(event))
        subscription.invalidate()
        bus.post(.popup(event))

        XCTAssertEqual(received.count, 1)
    }

    func testReleasedSubscriptionStopsReceiving() async throws {
        let bus = EventBus()
        var received = 0
        do {
            let subscription = bus.subscribe { _ in received += 1 }
            bus.post(.popup(event))
            _ = subscription
        }
        // Releasing the token unsubscribes on the next main-actor turn.
        try await Task.sleep(for: .milliseconds(50))
        bus.post(.popup(event))
        XCTAssertEqual(received, 1, "a released token must cancel its subscription")
    }
}
