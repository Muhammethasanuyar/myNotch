// Adapted from Lakr233/NotchDrop (MIT): copy-on-drop into a per-item directory, expiry by age,
// QuickLook previews — with the deprecated QLThumbnailImageCreate replaced by QLThumbnailGenerator
// and the store moved out of ~/Documents into Application Support.

import AppKit
import Foundation
import QuickLookThumbnailing

nonisolated enum ShelfStorageError: Error, Equatable {
    case sourceMissing(String)
    case indexUnreadable(String)
}

/// The shelf's files on disk. Everything here runs off the main actor: copies, sizes, previews.
actor ShelfStorage {
    let root: URL
    private let fileManager = FileManager()

    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyNotch", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
    }

    init(root: URL = ShelfStorage.defaultRoot) {
        self.root = root
    }

    // MARK: Index

    func loadIndex() throws -> [ShelfRecord] {
        let url = ShelfPaths.indexURL(root: root)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ShelfRecord].self, from: Data(contentsOf: url))
        } catch {
            throw ShelfStorageError.indexUnreadable(String(describing: error))
        }
    }

    func saveIndex(_ records: [ShelfRecord]) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: ShelfPaths.indexURL(root: root), options: .atomic)
    }

    // MARK: Items

    /// Copies the file (or folder) into a directory of its own and describes it. The original is
    /// never touched; the shelf holds its own copy so the item outlives the source.
    func copyIn(_ source: URL, existingNames: Set<String>) throws -> ShelfRecord {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw ShelfStorageError.sourceMissing(source.lastPathComponent)
        }
        let id = UUID()
        let directory = ShelfPaths.directory(root: root, id: id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = ShelfRules.uniqueFileName(source.lastPathComponent, existing: existingNames)
        let destination = directory.appendingPathComponent(name, isDirectory: isDirectory.boolValue)
        try fileManager.copyItem(at: source, to: destination)
        return ShelfRecord(
            id: id,
            fileName: name,
            byteCount: size(of: destination, isDirectory: isDirectory.boolValue),
            addedAt: Date(),
            isDirectory: isDirectory.boolValue,
            hasPreview: false
        )
    }

    /// Writes a 128 pt QuickLook preview beside the copy; `false` when QuickLook has none to give.
    func makePreview(for record: ShelfRecord) async -> Bool {
        let file = ShelfPaths.fileURL(root: root, record: record)
        let request = QLThumbnailGenerator.Request(fileAt: file, size: CGSize(width: 128, height: 128), scale: 2, representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return false }
        let bitmap = NSBitmapImageRep(cgImage: representation.cgImage)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: ShelfPaths.previewURL(root: root, id: record.id), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func delete(id: UUID) throws {
        let directory = ShelfPaths.directory(root: root, id: id)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    func deleteAll() throws {
        guard fileManager.fileExists(atPath: root.path) else { return }
        try fileManager.removeItem(at: root)
    }

    /// Bytes on disk of one item: the file's size, or the sum over a folder.
    func size(of url: URL, isDirectory: Bool) -> Int64 {
        guard isDirectory else {
            return (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
