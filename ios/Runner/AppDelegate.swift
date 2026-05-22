import UIKit
import Flutter
import GoogleMaps
import CoreLocation
import FirebaseCore
import FirebaseFirestore

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate, FlutterStreamHandler {

    private let METHOD_CHANNEL = "run_tracker/methods"
    private let EVENT_CHANNEL = "run_tracker/events"

    private var locationManager: CLLocationManager?
    private var eventSink: FlutterEventSink?
    private var userId: String?

    private var lastLocation: CLLocation?
    private var totalDistance: Double = 0.0
    private var startTime: Date?
    private var lastFirestoreUpdate: Date?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // O Firebase já é inicializado pelo plugin Flutter, mas garantimos acesso nativo
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        GMSServices.provideAPIKey("AIzaSyATbAQf0FYTXOdt8y4u8F72uIIBa_QuLrM")

        let controller : FlutterViewController = window?.rootViewController as! FlutterViewController

        // 🔹 Method Channel (Comandos start/stop)
        let methodChannel = FlutterMethodChannel(name: METHOD_CHANNEL, binaryMessenger: controller.binaryMessenger)
        methodChannel.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in

            if call.method == "startTracking" {
                if let args = call.arguments as? [String: Any],
                   let uid = args["userId"] as? String {
                    self.startTracking(userId: uid)
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

        // 🔹 Event Channel (Stream de dados GPS para UI)
        let eventChannel = FlutterEventChannel(name: EVENT_CHANNEL, binaryMessenger: controller.binaryMessenger)
        eventChannel.setStreamHandler(self)

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func startTracking(userId: String) {
        self.userId = userId
        self.totalDistance = 0.0
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
    }

    private func stopTracking() {
        locationManager?.stopUpdatingLocation()
    }

    // 🔹 FlutterStreamHandler Impl
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    // 🔹 CLLocationManagerDelegate (Onde a mágica acontece)
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // 1. Calcular distância acumulada
        if let last = lastLocation {
            let distance = location.distance(from: last)
            if distance >= 2.0 { // Filtro para evitar drift (pequenos pulos do GPS)
                totalDistance += distance
            }
        }
        lastLocation = location

        // 2. Calcular métricas básicas
        let elapsedMinutes = Date().timeIntervalSince(startTime ?? Date()) / 60.0
        let km = totalDistance / 1000.0
        let pace = km > 0 ? elapsedMinutes / km : 0.0
        let calories = totalDistance / 15.0

        // 3. Criar pacote de dados
        let data: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "distance_m": totalDistance,
            "kcal": calories,
            "pace_min_km": pace,
            "speed": location.speed
        ]

        // 4. Enviar para a interface do Flutter
        eventSink?(data)

        // 5. Atualizar Firestore Nativo (Live Tracking em Background) a cada 10s
        let now = Date()
        if lastFirestoreUpdate == nil || now.timeIntervalSince(lastFirestoreUpdate!) > 10 {
            lastFirestoreUpdate = now
            updateFirestore(data: data)
        }
    }

    private func updateFirestore(data: [String: Any]) {
        guard let uid = userId else { return }

        var update = data
        update["updatedAt"] = FieldValue.serverTimestamp()
        update["lat"] = data["latitude"]
        update["lng"] = data["longitude"]

        let db = Firestore.firestore()
        db.collection("users").document(uid).updateData(update) { error in
            if let error = error {
                print("❌ [iOS Native] Erro Firestore: \(error.localizedDescription)")
            }
        }
    }
}
