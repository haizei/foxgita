import SwiftUI

struct TunerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppRouter.self) private var router
    @State private var model: TunerModel
    @State private var showSettings = false
    @ScaledMetric(relativeTo: .largeTitle) private var noteSize = 80
    @ScaledMetric(relativeTo: .headline) private var targetNoteSize = 30

    init() {
        #if DEBUG
        _model = State(initialValue: TunerUITestFixture.makeModel() ?? TunerModel())
        #else
        _model = State(initialValue: TunerModel())
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        header
                        modeSelector.padding(.top, 18)
                        readout.padding(.top, 10)
                        feedback.padding(.top, 4)
                        TunerCentsScale(cents: model.displayedCents, inTune: model.intonation == .inTune, isHeld: model.isHoldingReading)
                            .opacity(model.isHoldingReading ? 0.4 : 1)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.isHoldingReading)
                            .padding(.horizontal, 8).padding(.top, 10)
                    }
                    .padding(.horizontal, 16)
                    headstock(width: max(0, min(450, geometry.size.width)))
                        .padding(.top, 10)
                }
                .padding(.top, 8).padding(.bottom, 12)
                .frame(maxWidth: 450).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(GitaTheme.bgDefault.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { await model.start() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.pause() }
        }
        .onChange(of: router.selectedTab) { _, tab in
            if tab != .tools { model.stop() }
        }
        .sheet(isPresented: $showSettings) { TunerSettingsView(model: model) }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button { model.stop(); dismiss() } label: {
                Image("TunerBack").frame(width: 44, height: 44)
            }.accessibilityLabel("返回工具").accessibilityIdentifier("tuner.back")
            Spacer(minLength: 0)
            Text("调音器").font(GitaFont.title()).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { showSettings = true } label: {
                Image("TunerSettings").frame(width: 44, height: 44)
            }.accessibilityLabel("调音设置").accessibilityIdentifier("tuner.settings")
        }
        .foregroundStyle(GitaTheme.textPrimary)
        .buttonStyle(.plain)
    }

    private var modeSelector: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Menu {
                ForEach(GuitarTuning.allCases) { tuning in
                    Button(tuning.title) { model.setTuning(tuning) }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("吉他 · 六弦").font(GitaFont.headline())
                        Image("TunerChevronDown").accessibilityHidden(true)
                    }.foregroundStyle(GitaTheme.textPrimary)
                    Text(model.tuning.summary).font(GitaFont.caption())
                        .foregroundStyle(GitaTheme.textSecondary)
                        .accessibilityIdentifier("tuner.tuning-summary")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityIdentifier("tuner.tuning")
            Toggle(isOn: Binding(get: { model.automatic }, set: model.setAutomatic)) {
                Text("自动识弦").font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
            }
            .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
            .tint(GitaTheme.brand500)
            .accessibilityIdentifier("tuner.auto")
        }.frame(minHeight: 48)
    }

    private var readout: some View {
        Text(model.target.noteName).font(.system(size: noteSize, weight: .bold))
            .lineLimit(1).minimumScaleFactor(0.5)
            .foregroundStyle(GitaTheme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 96)
            .accessibilityValue(Text("\(model.target.number) 弦，\(model.target.noteLabel)，目标 \(model.targetFrequency, specifier: "%.1f") Hz"))
            .accessibilityIdentifier("tuner.note")
    }

    private var feedbackColor: Color { model.intonation == .inTune ? GitaTheme.statusSuccessText : GitaTheme.brand500 }

    private var feedbackText: String {
        if model.status == .listening, model.isWaitingForReferenceSilence {
            return String(localized: "等待余音消退，请稍候再拨弦")
        }
        if model.isHoldingReading { return String(localized: "声音变弱，显示上一读数") }
        guard let cents = model.cents else {
            switch model.status {
            case .preparing: return String(localized: "正在准备麦克风")
            case .permissionDenied: return String(localized: "需要麦克风权限")
            case .paused, .interrupted: return String(localized: "收音已暂停")
            case .referenceTone: return String(localized: "标准音播放中")
            case .referenceDecay: return String(localized: "等待标准音余音消退")
            case .failed: return String(localized: "暂时无法收音")
            default: return model.isRecognizingString ? String(localized: "正在识别琴弦") : model.isSignalUnclear
                ? String(localized: "声音不够清晰，请重新拨弦")
                : String(localized: "等待琴弦声音")
            }
        }
        if abs(cents) > 150 { return String(localized: "偏离较大，请确认琴弦") }
        switch model.intonation {
        case .low: return String(localized: "偏低，稍微拧紧")
        case .high: return String(localized: "偏高，稍微放松")
        case .inTune: return String(localized: "已调准")
        case nil: return String(localized: "接近准确，请保持稳定")
        }
    }

    private var feedback: some View {
        VStack(spacing: 2) {
            if model.cents.map({ abs($0) > 150 }) ?? true {
                Text(feedbackText).font(GitaFont.body(.semibold))
                    .multilineTextAlignment(.center).accessibilityIdentifier("tuner.feedback")
            }
            Text(model.displayedCents.map { String(format: "%+.0f cent", $0.rounded()) } ?? "— cent")
                .font(GitaFont.callout()).monospacedDigit()
                .opacity(model.isHoldingReading ? 0.4 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.isHoldingReading)
                .accessibilityValue(feedbackText)
                .accessibilityIdentifier("tuner.cents")
            if model.status == .permissionDenied {
                Button("前往设置开启麦克风") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(GitaFont.caption()).frame(minHeight: 44)
                .foregroundStyle(GitaTheme.brand500)
                .accessibilityIdentifier("tuner.permission-settings")
            } else if [.paused, .interrupted, .failed].contains(model.status) {
                Button { Task { await model.start() } } label: {
                    VStack(spacing: 4) {
                        Text("继续调音")
                        if let error = model.errorMessage { Text(error).font(GitaFont.micro()) }
                    }
                    .font(GitaFont.caption()).frame(minHeight: 44)
                }
                .foregroundStyle(GitaTheme.brand500)
                .accessibilityIdentifier("tuner.resume")
            }
        }
        .foregroundStyle(model.cents == nil ? GitaTheme.textSecondary : feedbackColor)
        .frame(maxWidth: .infinity, minHeight: 20)
        .accessibilityElement(children: .contain)
    }

    private func headstock(width: CGFloat) -> some View {
        let diameter: CGFloat = typeSize.isAccessibilitySize && width >= 360 ? 64 : 52
        // The 300 pt asset includes 9 pt transparent side margins. Let those
        // margins share space with the controls, scaling the same way on SE.
        let imageWidth = min(300, max(0, width - 2 * (diameter + 8)) * 300 / 282)
        let imageHeight = imageWidth * 1619 / 971
        return ZStack(alignment: .topLeading) {
            Image("TunerHeadstock").resizable().scaledToFit()
                .frame(width: imageWidth, height: imageHeight)
                .position(x: width / 2, y: imageHeight / 2)
                .accessibilityHidden(true)
            ForEach([4, 5, 6, 3, 2, 1], id: \.self) { number in
                // Peg centers in the original 971 × 1619 image. Image and
                // controls share one transform, including on narrower phones.
                let pixelY: CGFloat = number == 4 || number == 3 ? 368 : (number == 5 || number == 2 ? 663 : 951)
                stringButton(number, diameter: diameter)
                    .position(x: number >= 4 ? 8 + diameter / 2 : width - 8 - diameter / 2,
                              y: pixelY * imageWidth / 971)
            }
        }
        .frame(width: width, height: imageHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tuner.headstock")
    }

    private func stringButton(_ number: Int, diameter: CGFloat) -> some View {
        let target = model.tuning.targets.first { $0.number == number }!
        let selected = model.selectedStringNumber == number
        return Button { model.selectString(number) } label: {
            Text(target.noteName)
                .font(.system(size: targetNoteSize, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.3)
                .padding(.horizontal, 4)
                .frame(width: diameter, height: diameter)
                .foregroundStyle(selected ? GitaTheme.brandOn : GitaTheme.textPrimary)
                .background(selected ? GitaTheme.brand500 : GitaTheme.bgSurface, in: Circle())
                .overlay {
                    if !selected { Circle().strokeBorder(GitaTheme.borderSubtle) }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(number) 弦，\(target.noteLabel)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("tuner.string.\(number)")
    }
}
