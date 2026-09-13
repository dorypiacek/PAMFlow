//
//  AppLog.swift
//  PAMFlow
//
//  Created by Dory on 10/06/2026.
//

import Foundation

/// Logging boundary for services and models.
protocol AppLogging {
    static func info(_ message: String)
    static func scan(_ message: String)
    static func module(_ name: String, _ message: String)
}

/// Lightweight console logger used while the app is still in local MVP form.
///
/// Centralizing log formatting makes it easier to replace `print` with OSLog
/// later without touching feature code.
enum AppLog: AppLogging {
    nonisolated static func info(_ message: String) {
        print("[PAMFlow] \(timestamp()) \(message)")
    }

    nonisolated static func scan(_ message: String) {
        print("[PAMFlow][Scan] \(timestamp()) \(message)")
    }

    nonisolated static func module(_ name: String, _ message: String) {
        print("[PAMFlow][\(name)] \(timestamp()) \(message)")
    }

    private nonisolated static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
