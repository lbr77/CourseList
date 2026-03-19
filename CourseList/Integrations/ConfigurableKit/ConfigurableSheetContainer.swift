import SwiftUI
import UIKit

final class RetainedNavigationController: UINavigationController {
    var retainedObject: AnyObject?
}

struct ConfigurableSheetContainer: UIViewControllerRepresentable {
    let rootController: UIViewController

    func makeUIViewController(context: Context) -> UIViewController {
        rootController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
