import SwiftUI

struct JamfDashboardRootView: View {
    @ObservedObject var appServices: ForsettiJamfProAppServices

    var body: some View {
        DashboardView(appServices: appServices)
    }
}
