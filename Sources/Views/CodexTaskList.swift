import SwiftUI

struct CodexTaskList: View {
    var compact = false
    var iconOnly = false
    @ObservedObject private var tasks = CodexTaskStore.shared

    var body: some View {
        Group {
            if tasks.items.isEmpty {
                Text(iconOnly ? "—" : (tasks.unavailable ? "暂不可用" : "暂无任务"))
                    .font(.system(size: compact ? 10 : 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: compact ? 1 : 5) {
                    ForEach(tasks.items) { task in
                        HStack(spacing: compact ? 4 : 8) {
                            Image(systemName: symbol(task.status))
                                .font(.system(size: compact ? 9 : 11, weight: .semibold))
                                .foregroundStyle(color(task.status))
                                .frame(width: compact ? 10 : 14)
                            if !iconOnly {
                                Text(compact && task.title.count > 6 ? String(task.title.prefix(6)) + "…" : task.title)
                                    .font(.system(size: compact ? 10 : 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(task.status == .running ? 0.95 : 0.65))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(task.status.label)
                                    .font(.system(size: compact ? 9 : 10, weight: .medium))
                                    .foregroundStyle(color(task.status))
                                    .fixedSize()
                            }
                        }
                        .frame(height: compact ? 13 : 26)
                        .help(task.title + " · " + task.status.label)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(task.title + "，" + task.status.label)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("当前 Codex 任务，最多两个")
    }

    private func symbol(_ status: CodexTaskStatus) -> String {
        switch status {
        case .running: return "circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .interrupted: return "pause.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func color(_ status: CodexTaskStatus) -> Color {
        switch status {
        case .running: return Color(red: 0.40, green: 0.70, blue: 1.0)
        case .completed: return Color(red: 0.43, green: 0.80, blue: 0.61)
        case .interrupted: return .orange.opacity(0.8)
        case .unknown: return .white.opacity(0.45)
        }
    }
}
