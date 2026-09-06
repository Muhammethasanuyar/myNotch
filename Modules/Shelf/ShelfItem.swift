// Adapted from Lakr233/NotchDrop (MIT): the per-item copy directory and the Transferable export
// of TrayDrop+DropItem.swift. Previews live beside the copy as files here, not inside the model.

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// What the shelf remembers about a file, as written to `index.json`.
nonisolated struct ShelfRecord: Codable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let byteCount: Int64
    let addedAt: Date
    let isDirectory: Bool
    var hasPreview: Bool
}

/// Where the shelf keeps things: one directory per item under the root, the copy inside it under
/// its own name, the preview beside it.
nonisolated enum ShelfPaths {
    static let indexName = "index.json"
    static let previewName = "preview.png"

    static func directory(root: URL, id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func fileURL(root: URL, record: ShelfRecord) -> URL {
        directory(root: root, id: record.id).appendingPathComponent(record.fileName, isDirectory: record.isDirectory)
    }

    static func previewURL(root: URL, id: UUID) -> URL {
        directory(root: root, id: id).appendingPathComponent(previewName)
    }

    static func indexURL(root: URL) -> URL {
        root.appendingPathComponent(indexName)
    }
}

/// A file on the shelf, with the URLs of its copy resolved against the store's root.
nonisolated struct ShelfItem: Identifiable, Hashable, Sendable {
    let record: ShelfRecord
    let fileURL: URL
    let previewURL: URL?

    var id: UUID { record.id }
    var fileName: String { record.fileName }

    init(record: ShelfRecord, root: URL) {
        self.record = record
        fileURL = ShelfPaths.fileURL(root: root, record: record)
        previewURL = record.hasPreview ? ShelfPaths.previewURL(root: root, id: record.id) : nil
    }
}

/// Dragging an item out hands the copy itself over; Finder and other apps copy from it.
nonisolated extension ShelfItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .item) { item in
            SentTransferredFile(item.fileURL, allowAccessingOriginalFile: true)
        }
    }
}
