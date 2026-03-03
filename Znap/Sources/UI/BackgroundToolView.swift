import SwiftUI

/// SwiftUI view providing controls for the Background Tool.
///
/// Presents a gradient preset selector, padding slider, corner radius slider,
/// shadow toggle, and aspect ratio picker. The "Apply" button invokes
/// ``BackgroundRenderer.render(screenshot:config:)`` and delivers the result
/// through the ``onApply`` closure.
struct BackgroundToolView: View {

    /// The source screenshot to render onto a background.
    let screenshot: NSImage

    /// Called with the rendered result image when the user taps "Apply".
    var onApply: ((NSImage) -> Void)?

    // MARK: - State

    @State private var selectedPreset: Int = 0
    @State private var useSolidColor: Bool = false
    @State private var solidColor: Color = .white
    @State private var padding: CGFloat = 40
    @State private var cornerRadius: CGFloat = 10
    @State private var addShadow: Bool = true
    @State private var selectedAspectRatio: BackgroundRenderer.AspectRatio = .free

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            // Preview
            previewSection

            Divider()

            // Background selector
            backgroundSection

            // Sliders
            slidersSection

            // Shadow toggle
            Toggle("Drop Shadow", isOn: $addShadow)

            // Aspect ratio
            aspectRatioSection

            Divider()

            // Apply button
            Button("Apply") {
                applyBackground()
            }
            .controlSize(.large)
            .keyboardShortcut(.return)
        }
        .padding()
        .frame(width: 320)
    }

    // MARK: - Sections

    private var previewSection: some View {
        Group {
            if let preview = renderPreview() {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Solid Color", isOn: $useSolidColor)

            if useSolidColor {
                ColorPicker("Background Color", selection: $solidColor)
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
                                            selectedPreset == index ? Color.white : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                                .onTapGesture {
                                    selectedPreset = index
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
                Slider(value: $padding, in: 0...100, step: 5)
                Text("\(Int(padding))")
                    .frame(width: 30, alignment: .trailing)
                    .monospacedDigit()
            }

            HStack {
                Text("Corners")
                Slider(value: $cornerRadius, in: 0...40, step: 2)
                Text("\(Int(cornerRadius))")
                    .frame(width: 30, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }

    private var aspectRatioSection: some View {
        Picker("Aspect Ratio", selection: $selectedAspectRatio) {
            ForEach(BackgroundRenderer.AspectRatio.allCases, id: \.self) { ratio in
                Text(ratio.label).tag(ratio)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Actions

    private func buildConfig() -> BackgroundRenderer.Config {
        var config = BackgroundRenderer.Config()

        if useSolidColor {
            config.backgroundType = .solid(NSColor(solidColor))
        } else {
            config.backgroundType = .gradient(preset: selectedPreset)
        }

        config.padding = padding
        config.cornerRadius = cornerRadius
        config.addShadow = addShadow
        config.aspectRatio = selectedAspectRatio == .free ? nil : selectedAspectRatio

        return config
    }

    private func renderPreview() -> NSImage? {
        BackgroundRenderer.render(screenshot: screenshot, config: buildConfig())
    }

    private func applyBackground() {
        guard let result = BackgroundRenderer.render(screenshot: screenshot, config: buildConfig()) else {
            return
        }
        onApply?(result)
    }
}
