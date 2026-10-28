import SwiftUI
import UIKit

@main
struct TrainLiveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            Group {
                if LaunchFlags.preview { ContentView() } else { RootView() }
            }
                .environmentObject(ConfigStore.shared)
                .environmentObject(LocationMonitor.shared)
                .environmentObject(ActivityController.shared)
        }
    }
}

/// 지오펜스 진입으로 백그라운드에서 깨어날 때도 위치 감시자가 바로 살아 있어야 해서 여기서 만든다.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = LocationMonitor.shared
        LocationMonitor.shared.sync(places: ConfigStore.shared.config.places)
        // 라이브 액티비티 버튼은 앱 프로세스에서 인텐트로 들어온다
        RideIntentHandler.board = { placeId, trainNo in Haptics.liveActivityTap(); await ActivityController.shared.board(placeId: placeId, trainNo: trainNo) }
        RideIntentHandler.end = { placeId in Haptics.liveActivityTap(); await ActivityController.shared.endRide(placeId: placeId) }
        RideIntentHandler.chooseLine = { placeId, lineId in Haptics.liveActivityTap(); await ActivityController.shared.chooseLine(placeId: placeId, lineId: lineId) }
        RideIntentHandler.chooseDirection = { placeId, lineId, dest, updn in
            Haptics.liveActivityTap()
            await ActivityController.shared.chooseDirection(placeId: placeId, lineId: lineId, dest: dest, updn: updn)
        }
        RideIntentHandler.dismiss = { placeId in Haptics.liveActivityTap(); await ActivityController.shared.dismiss(placeId: placeId) }
        RideIntentHandler.shift = { placeId, delta in Haptics.liveActivityTap(); await ActivityController.shared.shiftTrain(placeId: placeId, delta: delta) }
        RideIntentHandler.select = { placeId, trainId in Haptics.liveActivityTap(); await ActivityController.shared.select(placeId: placeId, trainId: trainId) }
        Task { await ActivityController.shared.endLeftovers() }
        ActivityController.shared.startDemoIfNeeded()
        return true
    }
}
