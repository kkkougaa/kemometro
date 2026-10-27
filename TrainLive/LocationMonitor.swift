import Combine
import CoreLocation
import Foundation

/// 역마다 원형 지오펜스를 걸어 두고, 들어오면 ActivityController 를 깨운다.
/// 지오펜스는 앱이 꺼져 있어도 iOS 가 감시하고, 진입 시 앱을 백그라운드로 띄워 delegate 를 부른다.
final class LocationMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationMonitor()

    let manager = CLLocationManager()
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var lastEvent: String = ""
    @Published var lastLocation: CLLocation?

    private var oneShot: ((CLLocation?) -> Void)?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
        authorization = manager.authorizationStatus
    }

    func requestAlways() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestAlwaysAuthorization()
        }
    }

    /// 설정된 역에 맞춰 지오펜스를 다시 건다(없어진 건 풀고, 새 건 추가).
    func sync(places: [Place]) {
        let wanted = places.filter { $0.enabled }
        let wantedIds = Set(wanted.map { $0.id.uuidString })
        for region in manager.monitoredRegions where !wantedIds.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        for p in wanted {
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude),
                                          radius: max(100, min(p.radius, 5000)),
                                          identifier: p.id.uuidString)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            if let existing = manager.monitoredRegions.first(where: { $0.identifier == p.id.uuidString }) as? CLCircularRegion,
               existing.center.latitude == region.center.latitude,
               existing.center.longitude == region.center.longitude,
               existing.radius == region.radius {
                continue
            }
            manager.startMonitoring(for: region)
        }
    }

    /// 라이브 액티비티를 띄워 둔 동안 앱이 백그라운드에서 잠들지 않게 위치 업데이트를 켠다.
    /// (지오펜스로 깨어난 실행은 30초쯤이면 끊기는데, 3분 동안 5초마다 갱신하려면 깨어 있어야 한다)
    private var keepAliveCount = 0
    func beginKeepAlive() {
        keepAliveCount += 1
        guard keepAliveCount == 1 else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = false
        manager.pausesLocationUpdatesAutomatically = false
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.startUpdatingLocation()
    }
    func endKeepAlive() {
        keepAliveCount = max(0, keepAliveCount - 1)
        guard keepAliveCount == 0 else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
    }

    /// 설정 화면에서 "현재 위치로" 버튼용
    func requestOneShot(_ done: @escaping (CLLocation?) -> Void) {
        oneShot = done
        manager.requestLocation()
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedWhenInUse {
            // 처음 허용 직후 "항상"으로 올리기
            manager.requestAlwaysAuthorization()
        }
        if authorization == .authorizedAlways || authorization == .authorizedWhenInUse {
            Task { @MainActor in self.sync(places: ConfigStore.shared.config.places) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        lastEvent = "진입 \(Date().formatted(date: .omitted, time: .shortened))"
        let id = region.identifier
        Task { @MainActor in await ActivityController.shared.trigger(placeId: id, reason: "지오펜스") }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        lastEvent = "지오펜스 실패: \(error.localizedDescription)"
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
        if let cb = oneShot { oneShot = nil; cb(locations.last) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let cb = oneShot { oneShot = nil; cb(nil) }
    }
}
