import SwiftUI
import SwiftData

/// How far a batch is through its cure, and the length, which stays editable
/// like the code and the log. Only placed for a batch that cures.
struct BatchCureSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]
    @Bindable var batch: Batch

    @State private var syncTask: Task<Void, Never>?

    var body: some View {
        Section {
            if let process = SoapProcess.resolve(batch.process) {
                LabeledContent("Process", value: process.label)
            }
            if let band = CureBand.resolve(batch.cureBand) {
                LabeledContent("Recommended", value: band.rangeText)
            }
            statusRow
            if let usableDate = batch.cureUsableDate {
                LabeledContent("Usable from", value: usableDate.formatted(date: .abbreviated, time: .omitted))
            }
            if let readyDate = batch.cureReadyDate {
                LabeledContent("Fully cured on", value: readyDate.formatted(date: .abbreviated, time: .omitted))
            }
            Stepper(value: $batch.cureDays, in: BatchCureLimits.days, step: 7) {
                LabeledContent("Length") {
                    CureLengthText.text(days: batch.cureDays)
                }
            }
            .accessibilityValue(CureLengthText.text(days: batch.cureDays))
        } header: {
            Text("Cure")
        } footer: {
            if AppSettings.canonical(from: settings)?.cureNotificationsEnabled != true {
                Text("Turn on Cure Reminders in Settings to be notified when it's usable and when it's ready.")
            }
        }
        .onChange(of: batch.cureDays) {
            rescheduleReminders()
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch batch.cureStatus {
        case .curing(_, let progress):
            ProgressView(value: progress) {
                BatchCureStatusLine(status: batch.cureStatus)
            }
        case .ready:
            BatchCureStatusLine(status: batch.cureStatus)
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
