import SwiftUI

struct HomeContentView: View {
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var routes: AppRoutes
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("给休息留一点时间").font(.title3.bold()); Spacer(); Button { routes.target = "classroom" } label: { Image(systemName: "arrow.up.right") }.accessibilityLabel("打开课堂") }
            ViewThatFits(in: .horizontal) { HStack(spacing: 12) {
                NavigationLink { GoodnightView() } label: { Label("晚安卡", systemImage: "moon.stars") }
                Spacer()
                NavigationLink { BreathingView() } label: { Label("呼吸", systemImage: "wind") }
                NavigationLink { WhiteNoiseView() } label: { Label("白噪音", systemImage: "waveform") }
            }
                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink { GoodnightView() } label: { Label("晚安卡", systemImage: "moon.stars") }
                    NavigationLink { BreathingView() } label: { Label("呼吸", systemImage: "wind") }
                    NavigationLink { WhiteNoiseView() } label: { Label("白噪音", systemImage: "waveform") }
                }
            }.font(.subheadline).buttonStyle(.bordered)
            if let daily = content.daily() {
                NavigationLink { ClassroomDetailView(item: daily) } label: {
                    HStack(spacing: 14) {
                        ContentCover(name: daily.cover).frame(width: 84)
                        VStack(alignment: .leading, spacing: 5) { Text("今日阅读").font(.caption).foregroundStyle(SleepPalette.teal); Text(daily.title).font(.headline).foregroundStyle(.primary).lineLimit(3) }
                        Spacer(minLength: 0)
                    }
                }.buttonStyle(.plain)
            }
            if let course = content.courses.first(where: \.featured) {
                NavigationLink { ClassroomDetailView(item: course) } label: {
                    HStack { Image(systemName: "play.rectangle"); Text(course.title).font(.subheadline); Spacer(); Image(systemName: "chevron.right") }.padding(.vertical, 8)
                }
            }
        }.task { await content.refresh(client: account.client) }
    }
}
