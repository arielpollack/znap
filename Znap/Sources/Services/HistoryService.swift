import AppKit
import SwiftData

/// Service that manages capture history using SwiftData.
///
/// ``HistoryService`` is a singleton that provides methods to add, query, and
/// clean up capture history entries. It creates its own ``ModelContainer`` and
/// ``ModelContext`` for the ``CaptureItem`` model.
///
/// SwiftData requires macOS 14+. On earlier systems, the service is a no-op
/// (all methods return empty results or silently do nothing).
///
/// ## Usage
///
/// ```swift
/// HistoryService.shared.addCapture(type: "area", image: myImage, filePath: "/path/to/file.png")
/// let recent = HistoryService.shared.recentCaptures(limit: 10)
/// ```
final class HistoryService {
    static let shared = HistoryService()

    /// The SwiftData model container for capture items (nil on macOS < 14).
    private let modelContainer: Any?

    /// The model context used for all CRUD operations (nil on macOS < 14).
    private let modelContext: Any?

    private init() {
        if #available(macOS 14, *) {
            do {
                let schema = Schema([CaptureItem.self])
                let configuration = ModelConfiguration(
                    "ZnapHistory",
                    schema: schema,
                    isStoredInMemoryOnly: false
                )
                let container = try ModelContainer(for: schema, configurations: [configuration])
                self.modelContainer = container
                self.modelContext = ModelContext(container)
            } catch {
                NSLog("HistoryService: Failed to create ModelContainer — \(error)")
                self.modelContainer = nil
                self.modelContext = nil
            }
        } else {
            self.modelContainer = nil
            self.modelContext = nil
        }
    }

    // MARK: - Public API

    /// Adds a capture to the history.
    ///
    /// Generates a thumbnail from the image (max 120x120) and records
    /// the capture metadata. No-op on macOS < 14.
    ///
    /// - Parameters:
    ///   - type: The capture type (e.g. "area", "window", "fullscreen").
    ///   - image: The captured screenshot image.
    ///   - filePath: Optional path to the saved file on disk.
    func addCapture(type: String, image: NSImage, filePath: String? = nil) {
        guard #available(macOS 14, *) else { return }
        guard let context = modelContext as? ModelContext else { return }

        // Generate thumbnail
        let thumbnail = image.resized(to: NSSize(width: 120, height: 120))
        let thumbnailData = thumbnail.tiffRepresentation.flatMap {
            NSBitmapImageRep(data: $0)?.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        }

        // Calculate file size
        var fileSize: Int64 = 0
        if let path = filePath {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            fileSize = (attrs?[.size] as? Int64) ?? 0
        }

        let item = CaptureItem(
            captureType: type,
            filePath: filePath,
            thumbnailData: thumbnailData,
            width: Int(image.size.width),
            height: Int(image.size.height),
            fileSize: fileSize
        )

        context.insert(item)

        do {
            try context.save()
        } catch {
            NSLog("HistoryService: Failed to save capture — \(error)")
        }
    }

    /// A simple struct mirroring CaptureItem data for display on older macOS.
    struct CaptureRecord {
        let id: UUID
        let timestamp: Date
        let captureType: String
        let filePath: String?
    }

    /// Returns the most recent captures, ordered by timestamp descending.
    ///
    /// - Parameter limit: Maximum number of items to return (default 20).
    /// - Returns: An array of ``CaptureRecord`` structs.
    func recentCaptures(limit: Int = 20) -> [CaptureRecord] {
        guard #available(macOS 14, *) else { return [] }
        guard let context = modelContext as? ModelContext else { return [] }

        var descriptor = FetchDescriptor<CaptureItem>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            let items = try context.fetch(descriptor)
            return items.map { CaptureRecord(id: $0.id, timestamp: $0.timestamp, captureType: $0.captureType, filePath: $0.filePath) }
        } catch {
            NSLog("HistoryService: Failed to fetch captures — \(error)")
            return []
        }
    }

    /// Deletes capture items older than the specified number of days.
    ///
    /// - Parameter days: Items older than this many days will be removed.
    func cleanup(olderThan days: Int) {
        guard #available(macOS 14, *) else { return }
        guard let context = modelContext as? ModelContext else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = #Predicate<CaptureItem> { item in
            item.timestamp < cutoff
        }
        let descriptor = FetchDescriptor<CaptureItem>(predicate: predicate)

        do {
            let oldItems = try context.fetch(descriptor)
            for item in oldItems {
                context.delete(item)
            }
            try context.save()
        } catch {
            NSLog("HistoryService: Failed to clean up history — \(error)")
        }
    }
}
