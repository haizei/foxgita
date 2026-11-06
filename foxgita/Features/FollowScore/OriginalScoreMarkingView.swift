import SwiftUI
import UIKit

struct OriginalScorePageView: View {
    let image: UIImage
    let rows: [OriginalScoreRow]
    var numbers: [UUID: Int] = [:]
    var activeID: UUID?
    var fraction: Double = 0
    var onMark: ((OriginalScoreBox) -> Void)?
    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?

    var body: some View {
        Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            let box = row.box
                            Rectangle().fill(Color.orange.opacity(row.id == activeID ? 0.12 : 0.025))
                                .overlay(Rectangle().stroke(Color.orange, lineWidth: row.id == activeID ? 2 : 1))
                                .frame(width: geometry.size.width * box.width, height: geometry.size.height * box.height)
                                .position(x: geometry.size.width * (box.x + box.width / 2),
                                          y: geometry.size.height * (box.y + box.height / 2))
                                .id(row.id)
                            Text("\(numbers[row.id] ?? (index + 1))").font(.caption2.bold()).padding(3).background(.orange, in: Capsule())
                                .offset(x: geometry.size.width * box.x, y: geometry.size.height * box.y)
                            if row.id == activeID {
                                Rectangle().fill(.orange)
                                    .frame(width: 3, height: geometry.size.height * box.height)
                                    .position(x: geometry.size.width * (box.x + box.width * fraction),
                                              y: geometry.size.height * (box.y + box.height / 2))
                                    .accessibilityIdentifier("original.cursor")
                            }
                        }
                        if let dragStart, let dragEnd {
                            Rectangle().stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [4]))
                                .frame(width: abs(dragEnd.x - dragStart.x), height: abs(dragEnd.y - dragStart.y))
                                .position(x: (dragEnd.x + dragStart.x) / 2, y: (dragEnd.y + dragStart.y) / 2)
                        }
                    }.frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                        guard onMark != nil else { return }
                        dragStart = value.startLocation; dragEnd = value.location
                    }.onEnded { value in
                        defer { dragStart = nil; dragEnd = nil }
                        guard let onMark, geometry.size.width > 0, geometry.size.height > 0 else { return }
                        let x = max(0, min(1, min(value.startLocation.x, value.location.x) / geometry.size.width))
                        let y = max(0, min(1, min(value.startLocation.y, value.location.y) / geometry.size.height))
                        let right = max(0, min(1, max(value.startLocation.x, value.location.x) / geometry.size.width))
                        let bottom = max(0, min(1, max(value.startLocation.y, value.location.y) / geometry.size.height))
                        let box = OriginalScoreBox(x: x, y: y, width: right - x, height: bottom - y)
                        if box.isValid, box.width > 0.02, box.height > 0.01 { onMark(box) }
                    }, including: onMark == nil ? .none : .all)
                }
            }
    }
}

struct OriginalScoreMarkingView: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: OriginalScoreDraft
    let library: OriginalScoreLibrary
    let entry: ScoreHubEntry
    let settings: OriginalScoreSettings
    var sameSessionRevision = false
    @State private var pages: [UIImage] = []
    @State private var page = 0
    @State private var selected: UUID?
    @State private var error: String?
    @State private var published: OriginalScoreDocument?
    @State private var saving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField("曲名", text: $draft.document.title).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("original.title")
                Text("框住一整行谱子，再设置这一行的总拍数。支持半拍，不保证逐音对齐。")
                    .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
                metadata
                if let error { Text(error).foregroundStyle(GitaTheme.statusError).accessibilityIdentifier("original.error") }
                HStack {
                    Picker("谱页", selection: $page) {
                        ForEach(pages.indices, id: \.self) { Text("第 \($0 + 1) 页").tag($0) }
                    }
                    Spacer()
                    Button("新增谱行") { selected = nil }.accessibilityIdentifier("original.new-row")
                }
                if pages.indices.contains(page) {
                    OriginalScorePageView(image: pages[page], rows: draft.document.rows.filter { $0.page == page }, numbers: draft.document.rowNumbers,
                        activeID: selected, onMark: selected == nil ? { addRow($0) } : nil)
                        .accessibilityIdentifier("original.mark-canvas")
                }
                if selected != nil { Text("已选择谱行；在下方调整区域或拍数。新增一行请点“新增谱行”。").font(.caption) }
                rowList
                if draft.document.rows.isEmpty {
                    Text("先在谱页上框选至少一行，才能保存并跟弹。")
                        .font(.caption).foregroundStyle(GitaTheme.textSecondary)
                }
                Button("按页码与位置重新排序") { draft.document.sortRows(); draft.document.manuallyOrdered = false }
                Button("保存并跟弹") { publish() }
                    .buttonStyle(.borderedProminent).tint(GitaTheme.brand500)
                    .disabled(saving || pages.count != draft.document.pageCount || (try? draft.document.validate()) == nil)
                    .accessibilityIdentifier("original.publish")
                Text("标记自动保存为草稿。未标记的页面保留查看，不参与走线。")
                    .font(GitaFont.caption()).foregroundStyle(GitaTheme.textSecondary)
            }.padding(20)
        }
        .background(GitaTheme.bgDefault).navigationTitle("标记谱行").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭") { if saveDraft() { dismiss() } }.accessibilityIdentifier("original.mark-close")
            }
        }
        .task {
            do {
                pages = try OriginalScoreSources.pages(for: draft.document, profileID: library.profileID).map {
                    guard let image = UIImage(data: $0) else { throw OriginalScoreError.missingVersion }
                    return image
                }
            } catch { self.error = error.localizedDescription }
        }
        .onChange(of: draft.document) { _, _ in _ = saveDraft() }
        .fullScreenCover(item: $published, onDismiss: { dismiss() }) { document in
            NavigationStack {
                OriginalScorePlayerView(document: document, library: library, entry: entry, settings: settings,
                                        resumeAtRowStart: !sameSessionRevision)
            }
        }
    }

    private var metadata: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("每小节拍数", selection: $draft.document.numerator) {
                    ForEach(2...12, id: \.self) { Text("\($0)").tag($0) }
                }
                Text("/")
                Picker("拍单位", selection: $draft.document.denominator) {
                    ForEach([2, 4, 8, 16], id: \.self) { Text("\($0)").tag($0) }
                }
            }
            Stepper("\(Int(draft.document.initialBPM)) BPM", value: $draft.document.initialBPM, in: 40...200, step: 1)
            Stepper("首行起始拍位：\(draft.document.startingBeat + 1, specifier: "%.1f")",
                value: $draft.document.startingBeat, in: 0...Double(draft.document.numerator) - 0.5, step: 0.5)
        }
        .onChange(of: draft.document.numerator) { _, value in
            if draft.document.startingBeat >= Double(value) { draft.document.startingBeat = 0 }
        }
    }

    private var rowList: some View {
        VStack(spacing: 10) {
            ForEach(Array(draft.document.rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("第 \(index + 1) 行 · 第 \(row.page + 1) 页") { selected = row.id; page = row.page }
                        Spacer()
                        Button { moveRow(index, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                        Button { moveRow(index, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(index == draft.document.rows.count - 1)
                        Button("删除", role: .destructive) {
                            draft.document.rows.removeAll { $0.id == row.id }; if selected == row.id { selected = nil }
                        }
                    }.font(.caption)
                    if let i = draft.document.rows.firstIndex(where: { $0.id == row.id }) {
                        HStack {
                            Text("总拍数")
                            TextField("总拍数", value: $draft.document.rows[i].beats, format: .number)
                                .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width: 80)
                                .accessibilityIdentifier("original.beats.\(index)")
                            Button("1 小节") { draft.document.rows[i].beats = Double(draft.document.numerator) }
                            Button("＋1 小节") { draft.document.rows[i].beats += Double(draft.document.numerator) }
                        }.font(.caption)
                        if selected == row.id { boxEditor(index: i) }
                        if !row.box.isValid {
                            Text("谱行区域超出页面，请调整左、上、宽、高。")
                                .font(.caption).foregroundStyle(GitaTheme.statusError)
                        }
                        if !row.beats.isFinite || row.beats < 0.5 || !OriginalScoreDocument.isHalfBeat(row.beats)
                            || draft.document.totalBeats > OriginalScoreDocument.maximumBeats {
                            Text("请填写有效总拍数：最少 0.5 拍，按半拍递增，且不能超出可表示范围。")
                                .font(.caption).foregroundStyle(GitaTheme.statusError)
                        }
                    }
                }.padding(12).background(GitaTheme.bgSurface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func boxEditor(index: Int) -> some View {
        VStack {
            boxSlider("左", value: $draft.document.rows[index].box.x)
            boxSlider("上", value: $draft.document.rows[index].box.y)
            boxSlider("宽", value: $draft.document.rows[index].box.width)
            boxSlider("高", value: $draft.document.rows[index].box.height)
        }
    }
    private func boxSlider(_ title: String, value: Binding<Double>) -> some View {
        HStack { Text(title).font(.caption); Slider(value: value, in: 0...1) }.accessibilityLabel(title)
    }
    private func moveRow(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard draft.document.rows.indices.contains(destination) else { return }
        draft.document.rows.swapAt(index, destination)
        draft.document.manuallyOrdered = true
    }
    private func addRow(_ box: OriginalScoreBox) {
        let row = OriginalScoreRow(page: page, box: box,
            beats: draft.document.rows.last?.beats ?? Double(draft.document.numerator))
        draft.document.rows.append(row)
        // New marks stay in drawing mode; selecting a row is explicit.
        if draft.document.manuallyOrdered != true { draft.document.sortRows() }
    }
    @discardableResult private func saveDraft() -> Bool {
        guard published == nil else { return true }
        draft.updatedAt = Date()
        do { try library.save(draft: draft); error = nil; return true }
        catch { self.error = "草稿未保存：\(error.localizedDescription)"; return false }
    }
    private func publish() {
        guard !saving else { return }; saving = true
        defer { saving = false }
        do {
            let data = try OriginalScoreSources.pages(for: draft.document, profileID: library.profileID)
            guard data.allSatisfy({ UIImage(data: $0) != nil }) else { throw OriginalScoreError.missingVersion }
            guard saveDraft() else { return }
            published = try library.publish(draftID: draft.id, availablePages: data.count)
        } catch { self.error = error.localizedDescription }
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor enum OriginalScoreUITestPage {
    static var data: Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 900)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 640, height: 900))
            ("原谱跟弹 · 测试谱页" as NSString).draw(at: CGPoint(x: 30, y: 25), withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black])
            UIColor.black.setStroke()
            for row in 0..<4 {
                for line in 0..<6 {
                    let y = CGFloat(130 + row * 160 + line * 12)
                    let path = UIBezierPath(); path.move(to: CGPoint(x: 40, y: y)); path.addLine(to: CGPoint(x: 600, y: y)); path.stroke()
                }
                ("0       2       3       2       0       2" as NSString).draw(at: CGPoint(x: 60, y: 145 + row * 160), withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .regular), .foregroundColor: UIColor.black])
            }
        }
        return image.jpegData(compressionQuality: 0.9)!
    }
}
#endif
