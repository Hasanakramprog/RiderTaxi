import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let mapsApiKey = resolveGoogleMapsApiKey()
    if !mapsApiKey.isEmpty {
      GMSServices.provideAPIKey(mapsApiKey)
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func resolveGoogleMapsApiKey() -> String {
    // 1. Check dart defines injected via --dart-define or --dart-define-from-file
    if let dartDefines = Bundle.main.infoDictionary?["DART_DEFINES"] as? String {
      let entries = dartDefines.components(separatedBy: ",")
      for entry in entries {
        if let data = Data(base64Encoded: entry),
           let decoded = String(data: data, encoding: .utf8) {
          let pair = decoded.components(separatedBy: "=")
          if pair.count >= 2 && pair[0] == "GOOGLE_MAPS_API_KEY" {
            let val = pair.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
            if !val.isEmpty { return val }
          }
        }
      }
    }

    // 2. Check system environment
    if let envKey = ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"], !envKey.isEmpty {
      return envKey
    }

    // 3. Fallback: try reading .env file from project root during local development / simulator
    let candidatePaths = [
      Bundle.main.path(forResource: ".env", ofType: nil),
      "\(Bundle.main.bundlePath)/../../../../.env"
    ]
    for path in candidatePaths.compactMap({ $0 }) {
      if let content = try? String(contentsOfFile: path, encoding: .utf8) {
        for line in content.components(separatedBy: .newlines) {
          let trimmed = line.trimmingCharacters(in: .whitespaces)
          if trimmed.hasPrefix("GOOGLE_MAPS_API_KEY=") {
            let key = trimmed.replacingOccurrences(of: "GOOGLE_MAPS_API_KEY=", with: "")
              .trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t\r\n"))
            if !key.isEmpty { return key }
          }
        }
      }
    }

    return ""
  }
}

