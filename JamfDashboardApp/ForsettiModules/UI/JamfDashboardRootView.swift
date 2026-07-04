import SwiftUI

struct JamfDashboardRootView: View {
    @ObservedObject var appServices: JamfDashboardAppServices

    var body: some View {
        DashboardView(appServices: appServices)
    }
}
