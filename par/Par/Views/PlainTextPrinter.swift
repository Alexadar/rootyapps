import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// System print for a monospaced report — the tape, or an amortization schedule.
///
/// One place, for two reasons. The obvious one is that both surfaces print the same kind of thing.
/// The load-bearing one is the iPad: `UIPrintInteractionController.present(animated:completionHandler:)`
/// is documented as iPhone-only and raises `NSGenericException` on iPad, which is exactly where three
/// of the shipped screenshot captions advertise printing. Presenting from a rect on a regular width
/// is the whole fix, and it needs to exist once rather than at every call site that grows a Print
/// button later.
enum PlainTextPrinter {

    static func print(_ text: String, jobName: String) {
        #if canImport(UIKit)
        let formatter = UISimpleTextPrintFormatter(text: text)
        formatter.perPageContentInsets = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = jobName
        controller.printInfo = info
        controller.printFormatter = formatter

        // On iPad the panel is a popover and needs somewhere to point. Anchoring it to the middle of
        // the key window is unglamorous but cannot be nil, which the alternative can.
        if let window = keyWindow, window.traitCollection.userInterfaceIdiom == .pad {
            let anchor = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 1, height: 1)
            controller.present(from: anchor, in: window, animated: true, completionHandler: nil)
        } else {
            controller.present(animated: true, completionHandler: nil)
        }
        #elseif canImport(AppKit)
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 720))
        view.string = text
        view.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        let operation = NSPrintOperation(view: view)
        operation.jobTitle = jobName
        operation.run()
        #endif
    }

    #if canImport(UIKit)
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
    #endif
}
