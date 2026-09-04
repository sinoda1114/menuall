import Foundation
import OSLog

enum AppLogger {
    static let lifecycle = Logger(subsystem: "com.sinoda.MenuAll", category: "lifecycle")
    static let accessibility = Logger(subsystem: "com.sinoda.MenuAll", category: "accessibility")
    static let discovery = Logger(subsystem: "com.sinoda.MenuAll", category: "discovery")
    static let action = Logger(subsystem: "com.sinoda.MenuAll", category: "action")
}
