import SwiftUI

struct AccountStateDiffView: View {
  let report: StateAccountDiff
  let before: Data?
  let after: Data?
  let changesOnly: Bool
  @State private var expanded = true
  @State private var mode: Mode = .diff
  @State private var page = 0
  private enum Mode: String, CaseIterable {
    case diff = "Diff"
    case before = "Before"
    case after = "After"
    case hex = "Hex"
  }
  private var color: Color {
    switch report.kind {
    case "create": .green
    case "delete": .red
    case "update": .orange
    default: .secondary
    }
  }
  private var title: String {
    switch report.kind {
    case "create": "Created"
    case "delete": "Deleted"
    case "update": "Updated"
    case "readonly": "Read-only"
    default: "Unchanged"
    }
  }
  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      VStack(alignment: .leading, spacing: 14) {
        Picker("State view", selection: $mode) {
          ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).labelsHidden()
        switch mode {
        case .diff:
          VStack(alignment: .leading, spacing: 16) {
            fieldDiff
            if report.dataChanged
              && !report.fields.contains(where: { $0.path.hasPrefix("data.parsed") && $0.changed })
            {
              Text("Byte changes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
              hexDiff
            }
          }
        case .before: jsonState(report.beforeState, removed: true)
        case .after: jsonState(report.afterState, removed: false)
        case .hex: hexDiff
        }
      }.padding(.top, 14)
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Label(
            title,
            systemImage: report.kind == "create"
              ? "plus.circle.fill"
              : report.kind == "delete"
                ? "minus.circle.fill" : report.changed ? "arrow.left.arrow.right" : "equal.circle"
          )
          .font(.caption.weight(.semibold)).foregroundStyle(color)
          Spacer()
          if report.lamportsDelta != "0" {
            Text(
              (report.lamportsDelta.hasPrefix("-") ? "" : "+") + report.lamportsDelta + " lamports"
            )
            .font(.caption.monospacedDigit()).foregroundStyle(
              report.lamportsDelta.hasPrefix("-") ? Color.red : Color.green)
          }
          Text(report.writable ? "Writable" : "Read-only").font(.caption2).foregroundStyle(
            .secondary)
          if report.changed {
            Text("\(report.fields.filter(\.changed).count) fields").font(.caption2).foregroundStyle(
              .secondary)
          }
        }
        Text(report.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.primary)
          .textSelection(.enabled)
      }.padding(.trailing, 5)
    }
    .tint(.secondary).padding(16)
    .background(VowDesign.surface, in: RoundedRectangle(cornerRadius: 12))
    .overlay(alignment: .leading) {
      RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.7)).frame(width: 3).padding(
        .vertical, 12)
    }
    .onAppear { expanded = report.changed }
    .onChange(of: changesOnly) { _, _ in page = 0 }
  }
  private var fieldDiff: some View {
    let fields = changesOnly ? report.fields.filter(\.changed) : report.fields
    return VStack(spacing: 0) {
      HStack {
        Text("Field").frame(maxWidth: .infinity, alignment: .leading)
        Text("− Before").foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
        Text("+ After").foregroundStyle(.green).frame(maxWidth: .infinity, alignment: .leading)
      }.font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 9)
      Divider()
      if fields.isEmpty {
        Text("No changed fields.").font(.caption).foregroundStyle(.secondary).padding(12)
      }
      ForEach(fields) { field in
        HStack(alignment: .top, spacing: 10) {
          Text(field.path.replacingOccurrences(of: "data.parsed.info.", with: "")).help(field.path)
            .foregroundStyle(.secondary).frame(
              maxWidth: .infinity, alignment: .leading)
          diffValue(field.before, changed: field.changed, removed: true).frame(
            maxWidth: .infinity, alignment: .leading)
          diffValue(field.after, changed: field.changed, removed: false).frame(
            maxWidth: .infinity, alignment: .leading)
        }.font(.system(.caption, design: .monospaced)).textSelection(.enabled)
          .padding(.horizontal, 10).padding(.vertical, 9)
          .background(field.changed ? color.opacity(0.035) : .clear)
        Divider().opacity(0.4)
      }
    }.background(.secondary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
  }
  private func diffValue(_ value: String?, changed: Bool, removed: Bool) -> some View {
    Text(value ?? "—").foregroundStyle(
      value == nil ? Color.secondary : changed ? removed ? Color.red : Color.green : Color.secondary
    )
    .padding(5).frame(maxWidth: .infinity, alignment: .leading)
    .background(
      changed && value != nil ? (removed ? Color.red : Color.green).opacity(0.08) : .clear,
      in: RoundedRectangle(cornerRadius: 4)
    )
    .accessibilityLabel(
      value.map { (changed ? removed ? "Previous: " : "New: " : "Unchanged: ") + $0 }
        ?? "Not present")
  }
  private func jsonState(_ text: String?, removed: Bool) -> some View {
    ScrollView(.horizontal) {
      Text(text ?? "Not present").font(.system(.caption, design: .monospaced)).textSelection(
        .enabled
      )
      .foregroundStyle(
        text == nil
          ? Color.secondary
          : report.kind == "create"
            ? Color.green : report.kind == "delete" ? Color.red : Color.primary
      )
      .padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }.background(.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
  }
  private var hexDiff: some View {
    let old = Array(before ?? Data())
    let new = Array(after ?? Data())
    let offsets = stride(from: 0, to: max(old.count, new.count), by: 16).filter { offset in
      !changesOnly || (0..<16).contains { byte(old, offset + $0) != byte(new, offset + $0) }
    }
    let pageCount = max(1, (offsets.count + 15) / 16)
    let current = min(page, pageCount - 1)
    let visible = Array(offsets.dropFirst(current * 16).prefix(16))
    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("\(old.count.formatted()) → \(new.count.formatted()) bytes").font(.caption)
          .monospacedDigit().foregroundStyle(.secondary)
        Spacer()
        Button {
          page = max(0, current - 1)
        } label: {
          Image(systemName: "chevron.left")
        }
        .disabled(current == 0).accessibilityLabel("Previous hex page")
        Text("\(current + 1) / \(pageCount)").font(.caption).monospacedDigit()
        Button {
          page = min(pageCount - 1, current + 1)
        } label: {
          Image(systemName: "chevron.right")
        }
        .disabled(current + 1 >= pageCount).accessibilityLabel("Next hex page")
      }.controlSize(.small)
      if offsets.isEmpty {
        Text(old == new ? "No changed bytes." : "No account data.").font(.caption).foregroundStyle(
          .secondary)
      }
      ScrollView(.horizontal) {
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 12) {
            Text("Offset").frame(width: 52, alignment: .leading)
            Text("− Before").foregroundStyle(.red).frame(width: 256, alignment: .leading)
            Text("+ After").foregroundStyle(.green).frame(width: 256, alignment: .leading)
          }.font(.caption.weight(.semibold)).padding(.bottom, 5)
          ForEach(visible, id: \.self) { offset in
            HStack(spacing: 12) {
              Text(String(format: "%06x", offset)).foregroundStyle(.secondary).frame(
                width: 52, alignment: .leading)
              hexCells(old, other: new, offset: offset, removed: true)
              hexCells(new, other: old, offset: offset, removed: false)
            }
          }
        }.font(.system(size: 10, design: .monospaced)).padding(10)
      }.background(.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
  }
  private func byte(_ data: [UInt8], _ index: Int) -> UInt8? {
    data.indices.contains(index) ? data[index] : nil
  }
  private func hexCells(_ data: [UInt8], other: [UInt8], offset: Int, removed: Bool) -> some View {
    HStack(spacing: 0) {
      ForEach(0..<16, id: \.self) { column in
        let value = byte(data, offset + column)
        let changed = value != byte(other, offset + column)
        Text(value.map { String(format: "%02x", $0) } ?? "··")
          .foregroundStyle(
            changed && value != nil ? removed ? Color.red : Color.green : Color.secondary
          )
          .frame(width: 16, height: 18)
          .background(
            changed && value != nil ? (removed ? Color.red : Color.green).opacity(0.12) : .clear)
      }
    }.textSelection(.enabled)
  }
}
