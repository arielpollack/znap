import SwiftUI

/// The toolbar displayed at the top of the annotation editor, containing tool
/// buttons, a colour palette, a stroke width slider, and undo/redo/copy/save actions.
struct AnnotationToolbar: View {

    // MARK: - Bindings

    @Binding var selectedTool: AnnotationDocument.AnnotationType
    @Binding var selectedColor: AnnotationDocument.CodableColor
    @Binding var strokeWidth: CGFloat

    // MARK: - Callbacks

    var onUndo: () -> Void
    var onRedo: () -> Void
    var onCopy: () -> Void
    var onSave: () -> Void

    var canUndo: Bool
    var canRedo: Bool

    // MARK: - Zoom

    var zoomLevel: CGFloat = 1.0
    var onZoomIn: () -> Void = {}
    var onZoomOut: () -> Void = {}
    var onZoomToFit: () -> Void = {}
    var onZoomToActualSize: () -> Void = {}

    // MARK: - Tool Definitions

    /// Maps each annotation type to a system image name.
    private static let tools: [(AnnotationDocument.AnnotationType, String)] = [
        (.arrow, "arrow.up.right"),
        (.rectangle, "rectangle"),
        (.filledRectangle, "rectangle.fill"),
        (.ellipse, "circle"),
        (.line, "line.diagonal"),
        (.text, "textformat"),
        (.counter, "number.circle"),
        (.pixelate, "square.grid.3x3"),
        (.blur, "drop"),
        (.spotlight, "sun.max"),
        (.highlighter, "highlighter"),
        (.pencil, "pencil"),
        (.handwriting, "pencil.tip"),
    ]

    // MARK: - Colour Palette

    /// Preset colours offered in the toolbar.
    private static let paletteColors: [(String, AnnotationDocument.CodableColor)] = [
        ("Red",    AnnotationDocument.CodableColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)),
        ("Orange", AnnotationDocument.CodableColor(red: 1, green: 0.58, blue: 0, alpha: 1)),
        ("Yellow", AnnotationDocument.CodableColor(red: 1, green: 0.8, blue: 0, alpha: 1)),
        ("Green",  AnnotationDocument.CodableColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)),
        ("Blue",   AnnotationDocument.CodableColor(red: 0, green: 0.48, blue: 1, alpha: 1)),
        ("Purple", AnnotationDocument.CodableColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1)),
        ("White",  AnnotationDocument.CodableColor(red: 1, green: 1, blue: 1, alpha: 1)),
        ("Black",  AnnotationDocument.CodableColor(red: 0, green: 0, blue: 0, alpha: 1)),
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Row 1: Tools
            HStack(spacing: 4) {
                ForEach(Self.tools, id: \.0) { tool, icon in
                    Button {
                        selectedTool = tool
                    } label: {
                        Image(systemName: icon)
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .background(
                        selectedTool == tool
                            ? Color.accentColor.opacity(0.25)
                            : Color.clear
                    )
                    .cornerRadius(6)
                    .help(tool.rawValue)
                }

                Spacer()

                // Undo / Redo
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.plain)
                .disabled(!canUndo)
                .help("Undo (⌘Z)")

                Button(action: onRedo) {
                    Image(systemName: "arrow.uturn.forward")
                }
                .buttonStyle(.plain)
                .disabled(!canRedo)
                .help("Redo (⌘⇧Z)")

                Divider().frame(height: 20)

                // Copy / Save
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy to Clipboard (⌘C)")

                Button(action: onSave) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.plain)
                .help("Save (⌘S)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Row 2: Colors + stroke width
            HStack(spacing: 4) {
                ForEach(Self.paletteColors, id: \.0) { name, codableColor in
                    Button {
                        selectedColor = codableColor
                    } label: {
                        Circle()
                            .fill(Color(
                                red: codableColor.red,
                                green: codableColor.green,
                                blue: codableColor.blue,
                                opacity: codableColor.alpha
                            ))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        selectedColor == codableColor
                                            ? Color.primary
                                            : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(name)
                }

                ColorPicker("", selection: customColorBinding)
                    .labelsHidden()
                    .frame(width: 24)

                Divider().frame(height: 18).padding(.horizontal, 4)

                Text("Width:")
                    .font(.caption)
                Slider(value: $strokeWidth, in: 1...20, step: 1)
                    .frame(width: 80)
                Text("\(Int(strokeWidth))")
                    .font(.caption)
                    .frame(width: 20)

                Spacer()

                Divider().frame(height: 18).padding(.horizontal, 4)

                // Zoom controls
                Button(action: onZoomOut) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .help("Zoom Out (⌘−)")

                Text("\(Int(zoomLevel * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 40, alignment: .center)

                Button(action: onZoomIn) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .help("Zoom In (⌘+)")

                Button(action: onZoomToFit) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                .help("Zoom to Fit (⌘0)")

                Button(action: onZoomToActualSize) {
                    Image(systemName: "1.magnifyingglass")
                }
                .buttonStyle(.plain)
                .help("Actual Size (⌘1)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Custom Colour Binding

    /// Bridges between SwiftUI's `Color` (used by `ColorPicker`) and
    /// ``AnnotationDocument/CodableColor``.
    private var customColorBinding: Binding<Color> {
        Binding<Color>(
            get: {
                Color(
                    red: selectedColor.red,
                    green: selectedColor.green,
                    blue: selectedColor.blue,
                    opacity: selectedColor.alpha
                )
            },
            set: { newColor in
                if let nsColor = NSColor(newColor).usingColorSpace(.sRGB) {
                    selectedColor = AnnotationDocument.CodableColor(
                        red: nsColor.redComponent,
                        green: nsColor.greenComponent,
                        blue: nsColor.blueComponent,
                        alpha: nsColor.alphaComponent
                    )
                }
            }
        )
    }
}
