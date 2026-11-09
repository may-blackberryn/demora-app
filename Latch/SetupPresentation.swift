import Foundation

/// Presentation identities, not migration state. Saving a one-shot offer may
/// remove its page; the current page must not become an unrelated array index.
enum WelcomePage: Hashable {
    case rules, dayNight, changes
}

enum WelcomePages {
    static func make(offersMath: Bool, offersDayNight: Bool) -> [WelcomePage] {
        // Math is a card on Rules, never a second page or duplicated offer.
        offersDayNight ? [.rules, .dayNight, .changes] : [.rules, .changes]
    }

    static func next(after page: WelcomePage, in pages: [WelcomePage]) -> WelcomePage? {
        guard let index = pages.firstIndex(of: page), pages.indices.contains(index + 1) else { return nil }
        return pages[index + 1]
    }

    static func previous(before page: WelcomePage, in pages: [WelcomePage]) -> WelcomePage? {
        // A day/night offer can close while its page is open. Back still goes
        // to the introduction, while Continue preserves the ordinary save guard.
        if page == .dayNight { return .rules }
        guard let index = pages.firstIndex(of: page), index > 0 else { return nil }
        return pages[index - 1]
    }
}
