import SwiftUI
import SwiftData

/// How far a batch is through its cure, and the length, which stays editable
/// like the code and the log. Only placed for a batch that cures.
struct BatchCureSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]
    @Bindable var batch: Batch

    @State private var syncTask: Task<Void, Never>?

    /// The rows this batch shows, in order. The sheet is drawn one row at a
    /// time, so each row needs to know where among them it sits.
    private enum Row {
        case process(SoapProcess)
        case recommended(CureBand)
        case status
        case usable(Date)
        case ready(Date)
        case length
    }

    private var rows: [Row] {
        var rows: [Row] = []
        if let process = SoapProcess.resolve(batch.process) {
            rows.append(.process(process))
        }
        if let band = CureBand.resolve(batch.cureBand) {
            rows.append(.recommended(band))
        }
        if batch.cureStatus != .none {
            rows.append(.status)
        }
        if let usableDate = batch.cureUsableDate {
            rows.append(.usable(usableDate))
        }
        if let readyDate = batch.cureReadyDate {
            rows.append(.ready(readyDate))
        }
        rows.append(.length)
        return rows
    }

    var body: some View {
        let rows = rows
        Section {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                rowView(row)
                    .ledgerSheetRow(position: .position(index: index, count: rows.count))
            }
        } header: {
            HoneyLedgerSectionLabel("Cure")
        } footer: {
            if AppSettings.canonical(from: settings)?.cureNotificationsEnabled != true {
                HoneyLedgerFooter("Turn on Cure Reminders in Settings to be notified when it's usable and when it's ready.")
            }
        }
        .onChange(of: batch.cureDays) {
            rescheduleReminders()
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .process(let process):
            valueRow("Process", value: process.label)
        case .recommended(let band):
            valueRow("Recommended", value: band.rangeText)
        case .status:
            // The row's first content is a stamp, which the list takes as the
            // separator's start; pin it to the leading content edge instead.
            statusRow
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        case .usable(let date):
            valueRow("Usable from", value: date.formatted(date: .abbreviated, time: .omitted))
        case .ready(let date):
            valueRow("Fully cured on", value: date.formatted(date: .abbreviated, time: .omitted))
        case .length:
            Stepper(value: $batch.cureDays, in: BatchCureLimits.days, step: 7) {
                HoneyLedgerStepperLabel(
                    title: "Length",
                    value: CureLengthText.text(days: batch.cureDays),
                    valueColor: .inkSoft
                )
            }
            .accessibilityValue(CureLengthText.text(days: batch.cureDays))
        }
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HoneyLedgerLabeledRow(title) {
            Text(value)
                .foregroundStyle(Color.inkSoft)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch batch.cureStatus {
        case .curing(_, let progress):
            VStack(alignment: .leading, spacing: 14) {
                BatchCureStatusLine(status: batch.cureStatus)
                ProgressView(value: progress)
                    .tint(Color.amber)
                    .accessibilityLabel("Cure progress")
            }
        case .ready:
            BatchCureStatusLine(status: batch.cureStatus, readyWord: String(localized: "Cured"))
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .none:
            EmptyView()
        }
    }

    /// Waits for the stepper to settle, so a run of taps reschedules once.
    private func rescheduleReminders() {
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await NotificationService.syncIfEnabled(modelContext: modelContext)
        }
    }
}
