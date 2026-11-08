import UIKit

/// The rest of Gita retains portrait behavior; only the score workspace rotates.
@MainActor final class ScoreOrientation: NSObject,UIApplicationDelegate {
    static var workspaceVisible = false
    func application(_ application: UIApplication,supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.workspaceVisible ? .allButUpsideDown : .portrait
    }
    static func setWorkspaceVisible(_ visible: Bool) {
        workspaceVisible = visible
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            guard let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { continue }
            root.setNeedsUpdateOfSupportedInterfaceOrientations()
            var controller = root
            while let presented = controller.presentedViewController { controller = presented }
            controller.setNeedsUpdateOfSupportedInterfaceOrientations()
            if !visible { scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) }
        }
    }
}
