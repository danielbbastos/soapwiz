import SwiftUI

/// A self-contained calculator that turns mold dimensions into a recommended
/// total oil weight, converts it into the recipe's oil weight unit, and hands
/// the result back through `onApply`.
struct MoldCalculatorView: View {
    /// The recipe's current oil weight unit (g / oz / lb / kg). The result is
    /// converted into this unit before being applied.
    let oilWeightUnit: String
    let onApply: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var shape: MoldShape = .rectangular
    @State private var fillMode: MoldFillMode = .standard
    @State private var lengthUnit: MoldLengthUnit
    @State private var dimensions: MoldDimensions
    private let initialLengthUnit: MoldLengthUnit
    private let initialDimensions: MoldDimensions

    /// Whether anything was changed from the starting cube, which stops a swipe
    /// from closing the sheet.
    private var hasChanges: Bool {
        shape != .rectangular || fillMode != .standard
            || lengthUnit != initialLengthUnit || dimensions != initialDimensions
    }

    /// cm in one inch — the only constant needed to convert dimensions when the
    /// length unit is switched.
    private static let cmPerInch = 2.54

    init(oilWeightUnit: String, onApply: @escaping (Double) -> Void) {
        self.oilWeightUnit = oilWeightUnit
        self.onApply = onApply
        // Inches pair naturally with ounces; everything else defaults to cm.
        let unit: MoldLengthUnit = oilWeightUnit == "oz" ? .inches : .centimeters
        _lengthUnit = State(initialValue: unit)
        initialLengthUnit = unit
        // Start from a 10 cm cube (or its inch equivalent) so the result is
        // populated the moment the sheet opens.
        let base = unit == .inches ? Self.round1(10 / Self.cmPerInch) : 10
        let cube = MoldDimensions(length: base, width: base, diameter: base, depth: base)
        _dimensions = State(initialValue: cube)
        initialDimensions = cube
    }

    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    /// Recommended oil weight in the recipe's oil weight unit, or `nil` when the
    /// dimensions are incomplete or the unit isn't a mass unit.
    private var recommendedWeight: Double? {
        guard volume > 0 else { return nil }
        return MoldCalculator.oilWeight(
            shape: shape, dimensions: dimensions,
            lengthUnit: lengthUnit, fillMode: fillMode, in: oilWeightUnit
        )
    }

    private var volume: Double {
        MoldCalculator.volume(shape: shape, dimensions: dimensions)
    }

    var body: some View {
        NavigationStack {
            Form {
                shapeSection
                dimensionsSection
                fillSection
                resultSection
            }
            .environment(\.defaultMinListRowHeight, 48)
            .ledgerBackground()
            .navigationTitle("Mold Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle("Mold Calculator")
            .onChange(of: lengthUnit) { _, newUnit in convertDimensions(to: newUnit) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .safeAreaInset(edge: .bottom) {
                useWeightButton
            }
        }
    }

    private var shapeSection: some View {
        Section {
            HoneyLedgerSegmented(
                "Shape",
                selection: $shape,
                options: MoldShape.allCases.map { ($0, $0.label) }
            )
            .ledgerSheetRow(position: .only)
        } header: {
            HoneyLedgerSectionLabel("Shape")
        }
    }

    /// The unit row, then the shape's own dimensions: three for a box, two for
    /// a cylinder.
    private var dimensionsSection: some View {
        Section {
            let count = shape == .rectangular ? 4 : 3
            HStack {
                Text("Measured in")
                    .foregroundStyle(Color.ink)
                Spacer(minLength: 16)
                HoneyLedgerSegmented(
                    "Measured in",
                    selection: $lengthUnit,
                    options: MoldLengthUnit.allCases.map { ($0, $0.rawValue) }
                )
                .frame(maxWidth: 160)
            }
            // The control's own guide would start the separator under it.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            .ledgerSheetRow(position: .position(index: 0, count: count))
            switch shape {
            case .rectangular:
                dimensionField("Length", value: $dimensions.length)
                    .ledgerSheetRow(position: .position(index: 1, count: count))
                dimensionField("Width", value: $dimensions.width)
                    .ledgerSheetRow(position: .position(index: 2, count: count))
                dimensionField("Depth", value: $dimensions.depth)
                    .ledgerSheetRow(position: .position(index: 3, count: count))
            case .cylindrical:
                dimensionField("Diameter", value: $dimensions.diameter)
                    .ledgerSheetRow(position: .position(index: 1, count: count))
                dimensionField("Depth", value: $dimensions.depth)
                    .ledgerSheetRow(position: .position(index: 2, count: count))
            }
        } header: {
            HoneyLedgerSectionLabel("Dimensions")
        }
    }

    private func dimensionField(_ label: String, value: Binding<Double>) -> some View {
        HoneyLedgerField(label, unit: lengthUnit.rawValue) { focus in
            NumericTextField(prompt: "0", value: value, fractionLength: 0...2, width: 80,
                             fillsAvailableWidth: true, focus: focus)
        }
    }

    private var fillSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Text("Fill")
                        .foregroundStyle(Color.ink)
                    InfoPopoverIcon(title: "Fill", text: fillExplanation)
                }
                HoneyLedgerSegmented(
                    "Fill",
                    selection: $fillMode,
                    options: MoldFillMode.allCases.map { ($0, $0.label) }
                )
            }
            .padding(.vertical, 4)
            .ledgerSheetRow(position: .only)
        }
    }

    private var resultSection: some View {
        Section {
            HoneyLedgerLabeledRow("Recommended oil weight") {
                if let weight = recommendedWeight {
                    Text.honeyLedgerFigure(
                        weight.formatted(.number.precision(.fractionLength(0...1))),
                        unit: oilWeightUnit
                    )
                } else {
                    Text("—")
                        .foregroundStyle(Color.inkFaint)
                }
            }
            .ledgerSheetRow(position: .only)
        }
    }

    private var useWeightButton: some View {
        Button {
            if let weight = recommendedWeight {
                onApply(weight)
                dismiss()
            }
        } label: {
            Text("Use this weight")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .glassButtonStyleIOS26()
        .controlSize(.large)
        .disabled(recommendedWeight == nil)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var fillExplanation: String {
        "How full the mold is poured. Soap batter needs headroom above the oils, lye and "
        + "water it becomes — these factors already leave the usual amount.\n\n"
        + "Standard fills the mold normally. Extra headroom recommends a little less oil "
        + "(~5–10% more empty space) for recipes with lots of fragrance or additives that "
        + "make the batter rise."
    }

    /// Converts the entered dimensions into `newUnit` so switching cm ⇄ in keeps
    /// the same physical mold rather than reinterpreting the numbers.
    private func convertDimensions(to newUnit: MoldLengthUnit) {
        let factor = newUnit == .centimeters ? Self.cmPerInch : 1 / Self.cmPerInch
        dimensions.length = Self.round1(dimensions.length * factor)
        dimensions.width = Self.round1(dimensions.width * factor)
        dimensions.diameter = Self.round1(dimensions.diameter * factor)
        dimensions.depth = Self.round1(dimensions.depth * factor)
    }
}
