import SwiftUI

extension View {
    func proRestoreAlert(_ model: ProRestoreModel) -> some View {
        alert(
            model.alert?.title ?? "",
            isPresented: Binding(
                get: { model.alert != nil },
                set: { if !$0 { model.alert = nil } }
            ),
            presenting: model.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }
}

/// The sheet that sells SoapWiz Pro, and thanks the user once it is theirs.
struct ProUpgradeView: View {
    @Environment(ProStore.self) private var proStore
    @Environment(StoreHost.self) private var storeHost
    @Environment(ProUpgradePresenter.self) private var presenter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let reason: ProUpgradeReason?

    @State private var restoreModel = ProRestoreModel()
    @State private var didPurchase = false
    @State private var containerWidth: CGFloat = 0

    /// Decided by the sheet's own width: a form sheet on iPad reports a
    /// compact size class, so the size class can't tell it from a phone.
    private var usesGrid: Bool { ProUpgradeLayout.usesGrid(width: containerWidth) }
    private var scrolls: Bool { !usesGrid || dynamicTypeSize.isAccessibilitySize }
    private var padding: CGFloat { usesGrid ? 28 : 20 }
    private var showsThankYou: Bool { didPurchase || proStore.isPro }

    var body: some View {
        Group {
            if showsThankYou {
                thankYou
            } else {
                upgrade
            }
        }
        .id(usesGrid)
        // Hidden, not removed, until the width is known: the first frame would
        // otherwise flash the phone layout, and the fitted sheet still needs
        // the content to measure.
        .opacity(containerWidth > 0 ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: scrolls ? .infinity : nil)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .presentationBackground { HoneyLedgerPaper() }
        .presentationSizing(.form.fitted(horizontal: false, vertical: true))
        .proRestoreAlert(restoreModel)
        .task {
            proStore.clearFailure()
            await proStore.loadPrice()
        }
    }

    private var thankYou: some View {
        let view = ProThankYouView(
            syncOutcome: ProSyncOutcome(prefersOffline: storeHost.prefersOffline),
            onDone: { presenter.dismiss() },
            onGoToSettings: { presenter.dismissToSettings() }
        )
        return Group {
            if scrolls {
                ScrollView { view.padding(padding) }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollClipDisabled()
            } else {
                view.padding(padding)
            }
        }
    }

    private var upgrade: some View {
        VStack(spacing: 16) {
            if scrolls {
                ScrollView { top.padding([.horizontal, .top], padding) }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollClipDisabled()
                Spacer(minLength: 0)
                bottom.padding([.horizontal, .bottom], padding)
            } else {
                top
                bottom
            }
        }
        .padding(scrolls ? 0 : padding)
    }

    private var top: some View {
        VStack(alignment: .leading, spacing: 16) {
            HoneyLedgerDiamondRule()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SoapWiz Pro")
                        .font(.largeTitle.weight(.semibold))
                        .fontDesign(.serif)
                        .foregroundStyle(Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("One payment, no subscription.")
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSoft)
                }
                Spacer(minLength: 8)
                Button {
                    presenter.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.inkSoft)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close")
            }
            if let reason {
                ProReasonBox(message: reason.message)
            }
            if usesGrid {
                ProBenefitsGrid(benefits: ProBenefit.paid + [ProBenefit.alwaysFree])
            } else {
                ProBenefitsList(benefits: ProBenefit.paid)
                Text(ProBenefit.alwaysFreeNote + " stay free.")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
            }
        }
    }

    private var bottom: some View {
        VStack(spacing: 12) {
            switch proStore.purchaseState {
            case .pending:
                ProPendingBox()
            case .failed:
                ProFailedBox()
            case .idle, .purchasing:
                EmptyView()
            }
            if proStore.priceLoadFailed, proStore.displayPrice == nil {
                HStack {
                    Text("Couldn’t load the price. Check your connection.")
                        .font(.footnote)
                        .foregroundStyle(Color.inkSoft)
                    Spacer(minLength: 8)
                    Button("Try again") {
                        Task { await proStore.loadPrice() }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.amberText)
                }
            }
            Button {
                Task {
                    if await proStore.purchase() == .purchased { didPurchase = true }
                }
            } label: {
                purchaseLabel
            }
            .buttonStyle(.honeyLedgerPrimary)
            .disabled(!ProUpgradeButton.isEnabled(
                price: proStore.displayPrice,
                state: proStore.purchaseState,
                isRestoring: restoreModel.isRestoring
            ))
            Button {
                Task { await restoreModel.restore(using: proStore, announcesSuccess: false) }
            } label: {
                if restoreModel.isRestoring {
                    ProgressView()
                } else {
                    Text("Restore purchases")
                }
            }
            .foregroundStyle(Color.amberText)
            .disabled(!ProUpgradeButton.canRestore(
                isRestoring: restoreModel.isRestoring,
                state: proStore.purchaseState
            ))
        }
    }

    @ViewBuilder
    private var purchaseLabel: some View {
        let title = ProUpgradeButton.title(price: proStore.displayPrice, state: proStore.purchaseState)
        if proStore.purchaseState == .purchasing {
            ProgressView()
        } else if proStore.displayPrice == nil, !proStore.priceLoadFailed {
            HStack(spacing: 8) {
                Text(title)
                ProgressView()
            }
        } else {
            Text(title)
        }
    }
}
