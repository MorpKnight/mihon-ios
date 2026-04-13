//
//  TabBarControllerAccessor.swift
//  Mihon IOS
//

import SwiftUI
import UIKit

/// - Note: **DEPRECATED** (Fix #6) — RootTabView no longer uses this UIKit bridge.
/// Pop-to-root on tab reselection is now handled natively via `.onChange(of: selectedTab)`.
/// This file is kept for reference and can safely be deleted in a clean-up pass.
/// Provides access to the hosting UITabBarController so we can detect re-taps on the active tab.

struct TabBarControllerAccessor: UIViewControllerRepresentable {
    let onReselect: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReselect: onReselect)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        DispatchQueue.main.async {
            context.coordinator.attachIfPossible(from: controller)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attachIfPossible(from: uiViewController)
        }
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        private let onReselect: (Int) -> Void
        private weak var tabBarController: UITabBarController?
        private var lastSelectedIndex: Int = 0

        init(onReselect: @escaping (Int) -> Void) {
            self.onReselect = onReselect
        }

        func attachIfPossible(from controller: UIViewController) {
            guard let tab = controller.tabBarController else { return }
            if tabBarController !== tab {
                tabBarController = tab
                lastSelectedIndex = tab.selectedIndex
                tab.delegate = self
            }
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            let index = tabBarController.selectedIndex
            if index == lastSelectedIndex {
                onReselect(index)
            }
            lastSelectedIndex = index
        }
    }
}

