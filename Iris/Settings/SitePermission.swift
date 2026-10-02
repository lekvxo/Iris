import SwiftData

@Model
final class SitePermission {
    @Attribute(.unique) var domain: String
    var allowsNavigation: Bool
    var blockingDisabled: Bool
    init(domain: String, allowsNavigation: Bool = false, blockingDisabled: Bool = false) {
        self.domain = domain
        self.allowsNavigation = allowsNavigation
        self.blockingDisabled = blockingDisabled
    }
}
