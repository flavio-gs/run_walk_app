import UIKit
import Flutter
import GoogleMaps
import CoreLocation
import FirebaseCore
import FirebaseFirestore
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate, FlutterStreamHandler {

    private let METHOD_CHANNEL = "run_tracker/methods"
    private let EVENT_CHANNEL = "run_tracker/events"

    private var locationManager: CLLocationManager?
    private var eventSink: FlutterEventSink?
    private var userId: String?
    private var userWeight: Double = 70.0

    private var lastLocation: CLLocation?
    private var totalDistance: Double = 0.0
    private var lastAnnouncedKm: Int = 0
    private var startTime: Date?
    private var lastFirestoreUpdate: Date?

    private let synthesizer = AVSpeechSynthesizer()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        GMSServices.provideAPIKey("AIzaSyATbAQf0FYTXOdt8y4u8F72uIIBa_QuLrM")

        let controller : FlutterViewController = window?.rootViewController as! FlutterViewController

        let methodChannel = FlutterMethodChannel(name: METHOD_CHANNEL, binaryMessenger: controller.binaryMessenger)
        methodChannel.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in

            if call.method == "startTracking" {
                if let args = call.arguments as? [String: Any],
                   let uid = args["userId"] as? String {
                    let weight = args["weight"] as? Double ?? 70.0
                    self.startTracking(userId: uid, weight: weight)
                    result(nil)
                } else {
                    result(FlutterError(code: "MISSING_ARG", message: "UserId is required", details: nil))
                }
            } else if call.method == "stopTracking" {
                self.stopTracking()
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        })

        let eventChannel = FlutterEventChannel(name: EVENT_CHANNEL, binaryMessenger: controller.binaryMessenger)
        eventChannel.setStreamHandler(self)

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func startTracking(userId: String, weight: Double) {
        self.userId = userId
        self.userWeight = weight
        self.totalDistance = 0.0
        self.lastAnnouncedKm = 0
        self.lastLocation = nil
        self.startTime = Date()
        self.lastFirestoreUpdate = nil

        if locationManager == nil {
            locationManager = CLLocationManager()
            locationManager?.delegate = self
            locationManager?.desiredAccuracy = kCLLocationAccuracyBest
            locationManager?.allowsBackgroundLocationUpdates = true
            locationManager?.pausesLocationUpdatesAutomatically = false
            locationManager?.distanceFilter = 5
        }

        locationManager?.requestAlwaysAuthorization()
        locationManager?.startUpdatingLocation()

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func stopTracking() {
        locationManager?.stopUpdatingLocation()
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        if let last = lastLocation {
            let distance = location.distance(from: last)
            if distance >= 2.0 {
                totalDistance += distance
            }
        }
        lastLocation = location

        let currentKm = Int(totalDistance / 1000)
        if currentKm > lastAnnouncedKm {
            lastAnnouncedKm = currentKm
            speakMetrics(kmCount: currentKm)
        }

        let elapsedSeconds = Date().timeIntervalSince(startTime ?? Date())
        let km = totalDistance / 1000.0
        let pace = km > 0 ? (elapsedSeconds / 60.0) / km : 0.0
        let calories = km * userWeight * 1.036

        let data: [String: Any] = [
            "latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude,
            "altitude": location.altitude, "accuracy": location.horizontalAccuracy,
            "distance_m": totalDistance, "kcal": calories, "pace_min_km": pace, "speed": location.speed
        ]

        eventSink?(data)

        let now = Date()
        if lastFirestoreUpdate == nil || now.timeIntervalSince(lastFirestoreUpdate!) > 10 {
            lastFirestoreUpdate = now
            updateFirestore(data: data)
        }
    }

    private func speakMetrics(kmCount: Int) {
        let elapsed = Int(Date().timeIntervalSince(startTime ?? Date()))
        let displayMinutes = elapsed / 60
        let displaySeconds = elapsed % 60

        let km = totalDistance / 1000.0
        let paceTotalSeconds = Int(Double(elapsed) / km)
        let paceMin = paceTotalSeconds / 60
        let paceSec = paceTotalSeconds % 60

        let calories = Int(km * userWeight * 1.036)

        let kmText = kmCount == 1 ? "1 quilômetro" : "\(kmCount) quilômetros"

        let text = "\(kmText). " +
                   "Tempo total \(displayMinutes) minutos e \(displaySeconds) segundos. " +
                   "Ritmo médio \(paceMin) minutos e \(paceSec) segundos por quilômetro. " +
                   "\(calories) calorias."

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "pt-BR")
        utterance.rate = 0.5

        synthesizer.speak(utterance)
    }

    private func updateFirestore(data: [String: Any]) {
        guard let uid = userId else { return }
        var update = data
        update["updatedAt"] = FieldValue.serverTimestamp()
        update["lat"] = data["latitude"]
        update["lng"] = data["longitude"]
        let db = Firestore.firestore()
        db.collection("users").document(uid).updateData(update)
    }
}
