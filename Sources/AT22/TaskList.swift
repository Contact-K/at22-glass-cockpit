import SwiftUI

// MARK: - タスク一覧

/// 計画したすべてのタスク。**画面の中央にモーダルで出す**（⇧⌘T）。
///
/// 右の欄に据えていたのを中央へ移したのは、これが「作業をしながら横目で見るもの」ではなく
/// 「手を止めて一覧を確かめるもの」だから。最上段の帯（`Cockpit.progressStrip`）が
/// 横目で見る側を担い、完了を強く畳んでいる。こちらは逆に**1件も畳まない**——
/// 畳むと完了ぶんを見返せなくなる。
///
/// 読むだけで、編集・追加・削除はできない——それは Claude Code 側の TaskCreate が担う
struct TaskPanel: View {
    let cockpit: Cockpit
    let onClose: () -> Void

    /// 絞り込みの種別。`all` なら全部、それ以外は status で絞る
    enum Filter: String, CaseIterable {
        case all
        case pending
        case inProgress
        case completed

        /// 表示文言。save/restore で値が変わると保存が初期化されないよう、
        /// ここで変えても case 名は動かさない
        var title: String {
            switch self {
            case .all: "すべて"
            case .pending: "未着手"
            case .inProgress: "進行中"
            case .completed: "完了"
            }
        }
    }

    @AppStorage("taskListFilter") private var filter = Filter.all
    @State private var hovered: String?

    private var allTasks: [RoadmapTask] { cockpit.allTasks(session: cockpit.selectedSession) }

    private var visibleTasks: [RoadmapTask] {
        allTasks.filter { task in
            switch filter {
            case .all: return true
            case .pending: return task.status == .pending
            case .inProgress: return task.status == .inProgress
            case .completed: return task.status == .completed
            }
        }
    }

    var body: some View {
        // 暗幕。押すと閉じる（Esc と同じ口）
        Color.black.opacity(0.45)
            .ignoresSafeArea()
            .onTapGesture(perform: onClose)
            .overlay { panel }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.border).frame(height: Palette.Stroke.hair)

            if visibleTasks.isEmpty {
                Spacer(minLength: Palette.Space.s6)
                Text(allTasks.isEmpty
                     ? "まだタスクが無い。Claude Code 側で TaskCreate が呼ばれると出る"
                     : "この絞り込み条件に当てはまるタスクが無い")
                    .font(.system(size: Palette.FontSize.prose, design: .monospaced))
                    .foregroundStyle(Palette.inkTertiary)
                Spacer(minLength: Palette.Space.s6)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleTasks) { task in
                            taskRow(task)
                                .contentShape(Rectangle())
                                .onHover { hovered = $0 ? task.id : nil }
                                .background(hovered == task.id
                                            ? Palette.ink.opacity(0.06) : Color.clear)
                        }
                    }
                    .padding(.horizontal, Palette.Space.s3)
                    .padding(.vertical, Palette.Space.tiny)
                }
            }

            Rectangle().fill(Palette.border).frame(height: Palette.Stroke.hair)
            Text("読み取り専用 — 編集は Claude Code 側の TaskCreate / TaskUpdate が担う")
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .foregroundStyle(Palette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Palette.Space.s3)
                .padding(.vertical, Palette.Space.s2)
        }
        .frame(width: 560)
        .frame(maxHeight: 640)
        .background(Palette.fieldSubtle)
        .clipShape(RoundedRectangle(cornerRadius: Palette.Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Palette.Radius.sm)
            .stroke(Palette.border, lineWidth: Palette.Stroke.border))
        .shadow(color: .black.opacity(0.7), radius: 30, y: 16)
        // 幕の tap が下まで抜けると、パネルを押しただけで閉じる
        .onTapGesture {}
    }

    private var header: some View {
        HStack(spacing: Palette.Space.s2) {
            Text("02")
                .font(.system(size: Palette.FontSize.label, design: .monospaced))
                .foregroundStyle(Palette.inkTertiary)
            Text("タスク一覧")
                .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                .tracking(Palette.Tracking.wider)
                .foregroundStyle(Palette.ink)
            Text("\(allTasks.count) · 完了\(allTasks.filter { $0.status == .completed }.count)")
                .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                .foregroundStyle(Palette.inkTertiary)

            Spacer(minLength: Palette.Space.s2)

            // 押し込んだ面で選択中を示す。色は使わない
            ForEach(Filter.allCases, id: \.self) { f in
                Button { filter = f } label: {
                    Text(f.title)
                        .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .foregroundStyle(filter == f ? Palette.ink : Palette.inkTertiary)
                        .background {
                            if filter == f {
                                RoundedRectangle(cornerRadius: Palette.Radius.xs)
                                    .fill(Palette.surfaceSunken)
                            }
                        }
                }
                .buttonStyle(.plain)
            }

            Button(action: onClose) {
                Text("✕")
                    .font(.system(size: Palette.FontSize.prose, design: .monospaced))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .buttonStyle(.plain)
            .padding(.leading, Palette.Space.tiny)
        }
        .padding(.horizontal, Palette.Space.s3)
        .padding(.vertical, Palette.Space.small)
    }

    /// 1行。**完了は取り消し線、進行中だけが赤**（画面の赤は「いま」を指す1系統だけ）
    private func taskRow(_ task: RoadmapTask) -> some View {
        let active = task.status == .inProgress
        let done = task.status == .completed
        return VStack(alignment: .leading, spacing: Palette.Space.hair) {
            HStack(spacing: Palette.Space.s2) {
                Text("\(task.number)")
                    .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                    .foregroundStyle(active ? Palette.accentText : Palette.inkTertiary)
                    .frame(width: 20, alignment: .leading)

                Text(task.activeForm.isEmpty ? task.subject : task.activeForm)
                    .font(.system(size: Palette.FontSize.body,
                                  weight: active ? .medium : .regular))
                    .strikethrough(done)
                    .foregroundStyle(done ? Palette.inkTertiary
                                          : (active ? Palette.ink : Palette.inkSecondary))
                    .lineLimit(1)
                    .textSelection(.enabled)

                Spacer(minLength: Palette.Space.tiny)

                if task.status != .pending {
                    Text(task.at.formatted(.dateTime.hour().minute()))
                        .font(.system(size: Palette.FontSize.label, design: .monospaced))
                        .foregroundStyle(Palette.inkDisabled)
                }
                if cockpit.selectedSession == nil {
                    Text(String(task.session.prefix(8)))
                        .font(.system(size: Palette.FontSize.label, design: .monospaced))
                        .foregroundStyle(Palette.inkDisabled)
                }
                Text(done ? "✓" : (active ? "▶" : ""))
                    .font(.system(size: Palette.FontSize.readout, design: .monospaced))
                    .foregroundStyle(active ? Palette.accentText : Palette.inkTertiary)
                    .frame(width: 12, alignment: .trailing)
            }

            if !task.detail.isEmpty, hovered == task.id {
                Text(task.detail)
                    .font(.system(size: Palette.FontSize.label, design: .monospaced))
                    .lineSpacing(1)
                    .textSelection(.enabled)
                    .foregroundStyle(Palette.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, Palette.Space.s1)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: Palette.Stroke.hair)
        }
    }
}
