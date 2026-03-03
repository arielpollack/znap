import SwiftUI

/// SwiftUI view providing controls for the Background Tool.
///
/// Presents a gradient preset selector, padding slider, corner radius slider,
/// shadow toggle, and aspect ratio picker. Changes are applied live via the
/// bound ``BackgroundRenderer/Config``.
struct BackgroundToolView: View {

    /// The source screenshot for the preview thumbnail.
    let screenshot: NSImage

    /// Bound config — changes propagate live to the parent.
    @Binding var config: BackgroundRenderer.Config

    // MARK: - Local State

    @State private var solidColor: Color = .white

    // MARK: - Derived State

    private var useSolidColor: Binding<Bool> {
        Binding(
            get: {
                if case .solid = config.backgroundType { return true }
                return false
            },
            set: { isSolid in
                if isSolid {
                    let nsColor = NSColor(solidColor)
                    config.backgroundType = .solid(BackgroundRenderer.CodableColor(nsColor))
                } else {
                    config.backgroundType = .gradient(preset: selectedPresetIndex)
                }
            }
        )
    }

    private var selectedPresetIndex: Int {
        if case .gradient(let preset) = config.backgroundType { return preset }
        return 0
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            // Preview
            previewSection

            Divider()

            // Background selector
            backgroundSection

            // Sliders
            slidersSection

            // Shadow toggle
            Toggle("Drop Shadow", isOn: $config.addShadow)

            // Aspect ratio
            aspectRatioSection
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Sections

    private var previewSection: some View {
        Group {
            if let preview = BackgroundRenderer.render(screenshot: screenshot, config: config) {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Solid Color", isOn: useSolidColor)

            if case .solid = config.backgroundType {
                ColorPicker("Background Color", selection: solidColorBinding)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(0..<BackgroundRenderer.gradientPresets.count, id: \.self) { index in
                            let preset = BackgroundRenderer.gradientPresets[index]
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(nsColor: preset.0), Color(nsColor: preset.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 28, height: 28)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            selectedPresetIndex == index ? Color.white : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                                .onTapGesture {
                                    config.backgroundType = .gradient(preset: index)
                                }
                        }
                    }
                }
            }
        }
    }

    private var slidersSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Padding")
                Slider(value: $config.padding, in: 0...100, step: 5)
                Text("\(Int(config.padding))")
                    .frame(width: 30, alignment: .trailing)
                    .monospacedDigit()
            }

            HStack {
                Text("Corners")
                Slider(value: $config.cornerRadius, in: 0...40, step: 2)
                Text("\(Int(config.cornerRadius))")
                    .frame(width: 30, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }

    private var aspectRatioSection: some View {
        Picker("Aspect Ratio", selection: aspectRatioBinding) {
            ForEach(BackgroundRenderer.AspectRatio.allCases, id: \.self) { ratio in
                Text(ratio.label).tag(ratio)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Bindings

    private var solidColorBinding: Binding<Color> {
        Binding(
            get: {
                if case .solid(let c) = config.backgroundType {
                    return Color(red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
                }
                return solidColor
            },
            set: { newColor in
                solidColor = newColor
                let nsColor = NSColor(newColor).usingColorSpace(.sRGB) ?? NSColor(newColor)
                config.backgroundType = .solid(BackgroundRenderer.CodableColor(nsColor))
            }
        )
    }

    private var aspectRatioBinding: Binding<BackgroundRenderer.AspectRatio> {
        Binding(
            get: { config.aspectRatio ?? .free },
            set: { config.aspectRatio = $0 == .free ? nil : $0 }
        )
    }
}
