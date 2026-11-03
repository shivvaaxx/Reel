import Foundation
import SafariServices

/// Receives "download this" messages from the Safari extension's toolbar button and
/// context menu, and hands the link to Reel.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let link = message?["url"] as? String
        let sent = link.map { ReelLink.send($0) } ?? false

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["ok": sent]]
        context.completeRequest(returningItems: [response])
    }
}
