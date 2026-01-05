//
//  AppDelegate.swift
//  Miya Health
//
//  Enables ROOK background listeners for HealthKit background delivery.
//

import UIKit
import RookSDK

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Required by ROOK to receive background delivery callbacks and upload summaries/events.
        RookBackGroundSync.shared.setBackListeners()
        RookBackGroundSync.shared.enableBackGroundForSummaries()
        RookBackGroundSync.shared.enableBackGroundForEvents()
        print("✅ AppDelegate: ROOK background listeners enabled")
        return true
    }
}


