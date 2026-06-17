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
    @State private var showFillInfo = false

    /// cm in one inch — the only constant needed to convert dimensions when the
    /// length unit is switched.
    private static let cmPerInch = 2.54

    init(oilWeightUnit: String, onApply: @escaping (Double) -> Void) {
        self.oilWeightUnit = oilWeightUnit
        self.onApply = onApply
        // Inches pair naturally with ounces; everything else defaults to cm.
        let unit: MoldLengthUnit = oilWeightUnit == "oz" ? .inches : .centimeters
        _lengthUnit = State(initialValue: unit)
        // Start from a 10 cm cube (or its inch equivalent) so the result is
        // populated the moment the sheet opens.
        let base = unit == .inches ? Self.round1(10 / Self.cmPerInch) : 10
        _dimensions = State(initialValue: MoldDimensions(length: base, width: base, diameter: base, depth: base))
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
            .warmBackground()
            .navigationTitle("Mold Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Mold Calculator")
            .onChange(of: lengthUnit) { _, newUnit in convertDimensions(to: newUnit) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                useWeightButton
            }
            .sheet(isPresented: $showFillInfo) {
                fillInfoSheet
            }
        }
    }

    private var shapeSection: some View {
        Section("Shape") {
            Picker("Shape", selection: $shape) {
                ForEach(MoldShape.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .listRowBackground(Color.cardBackground)
    }

    @ViewBuilder
    private var dimensionsSection: some View {
        Section("Dimensions") {
            HStack {
                Text("Measured in")
                Spacer()
                Picker("Unit", selection: $lengthUnit) {
                    ForEach(MoldLengthUnit.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(.primary)
            }

            switch shape {
            case .rectangular:
                dimensionField("Length", value: $dimensions.length)
                dimensionField("Width", value: $dimensions.width)
                dimensionField("Depth", value: $dimensions.depth)
            case .cylindrical:
                dimensionField("Diameter", value: $dimensions.diameter)
                dimensionField("Depth", value: $dimensions.depth)
            }
        }
        .listRowBackground(Color.cardBackground)
    }

    private func dimensionField(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(lengthUnit.rawValue)
                .foregroundStyle(.secondary)
        }
    }

    private var fillSection: some View {
        Section {
            HStack {
                Text("Fill")
                Button {
                    showFillInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
                Picker("Fill", selection: $fillMode) {
                    ForEach(MoldFillMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(.primary)
            }
        }
        .listRowBackground(Color.cardBackground)
    }

    private var resultSection: some View {
        Section {
            HStack {
                Text("Recommended oil weight")
                Spacer()
                if let weight = recommendedWeight {
                    Text("\(weight.formatted(.number.precision(.fractionLength(0...1)))) \(oilWeightUnit)")
                        .fontWeight(.semibold)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listRowBackground(Color.cardBackground)
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

    private var fillInfoSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fill")
                .font(.headline)
            Text("How full the mold is poured. Soap batter needs headroom above the oils, lye and water it "
                 + "becomes — these factors already leave the usual amount.\n\n**Standard** fills the mold "
                 + "normally. **Extra headroom** recommends a little less oil (~5–10% more empty space) for "
                 + "recipes with lots of fragrance or additives that make the batter rise.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
