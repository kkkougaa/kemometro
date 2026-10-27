import SwiftUI

/// 라이브 액티비티 그림을 앱 안에서 그대로 그려 보는 화면. 실제 위젯과 같은 뷰(Shared/ActivityViews)를 쓴다.
/// CI 는 `-preview` 로 이 화면을 열어 스크린샷을 찍는다. "다시 재생"으로 등장 애니메이션을 반복해 볼 수 있다.
struct DesignPreviewView: View {
    @State private var phase = 0
    @State private var later = false
    @State private var endsAt = Date().addingTimeInterval(30)
    @State private var rideStep = 1

    private var attributes: TrainActivityAttributes { DemoData.attributes }
    private var state: ActivityState { DemoData.state(phase: phase, slots: attributes.slots, endsAt: endsAt, later: later) }
    private var line: LineInfo { Lines.info(attributes.lineId) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("잠금화면") {
                    ActivityLockView(attributes: attributes, state: state)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .environment(\.colorScheme, .dark)
                        .frame(maxWidth: 360)
                }

                section("다이내믹 아일랜드 · 펼침") {
                    VStack(spacing: 8) {
                        HStack(alignment: .center) {
                            ActivityIslandParts.leading(attributes, state)
                            Spacer()
                            ActivityIslandParts.trailing(attributes, state)
                        }
                        ActivityIslandParts.bottom(attributes, state)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 360)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .environment(\.colorScheme, .dark)
                }

                section("탑승 추적 · 잠금화면") {
                    ActivityLockView(attributes: attributes, state: DemoData.rideState(step: rideStep))
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .environment(\.colorScheme, .dark)
                        .frame(maxWidth: 360)
                }

                section("탑승 추적 · 아일랜드 펼침") {
                    let rs = DemoData.rideState(step: rideStep)
                    VStack(spacing: 8) {
                        HStack(alignment: .center) {
                            ActivityIslandParts.leading(attributes, rs)
                            Spacer()
                            ActivityIslandParts.trailing(attributes, rs)
                        }
                        ActivityIslandParts.bottom(attributes, rs)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 360)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .environment(\.colorScheme, .dark)
                }

                section("환승 · 노선 선택") {
                    ActivityLockView(attributes: attributes, state: DemoData.transferState(stage: 2))
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .environment(\.colorScheme, .dark)
                        .frame(maxWidth: 360)
                }

                section("환승 · 방면 선택") {
                    ActivityLockView(attributes: attributes, state: DemoData.transferState(stage: 3))
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .environment(\.colorScheme, .dark)
                        .frame(maxWidth: 360)
                }

                section("다이내믹 아일랜드 · 컴팩트") {
                    HStack(spacing: 0) {
                        ActivityIslandParts.compactLeading(attributes, state)
                        Spacer().frame(width: 70)
                        ActivityIslandParts.compactTrailing(attributes, state)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 37)
                    .background(Color.black, in: Capsule())
                    .environment(\.colorScheme, .dark)
                }

                section("미니멀") {
                    ActivityIslandParts.minimal(attributes, state)
                        .frame(width: 37, height: 37)
                        .background(Color.black, in: Circle())
                        .environment(\.colorScheme, .dark)
                }

                HStack(spacing: 12) {
                    GlassPillButton(title: "다시 재생", systemImage: "arrow.counterclockwise", tint: line.color, prominent: true) { replay() }
                    GlassPillButton(title: later ? "처음 위치" : "열차 전진", systemImage: "tram") { withAnimation { later.toggle() } }
                    GlassPillButton(title: "다음 역", systemImage: "arrow.right") {
                        withAnimation { rideStep = (rideStep + 1) % DemoData.ridePath.count }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("디자인 미리보기")
        .onAppear { replay() }
    }

    private func section<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func replay() {
        phase = 0
        later = false
        endsAt = Date().addingTimeInterval(30)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation { phase = 1 }
        }
    }
}
