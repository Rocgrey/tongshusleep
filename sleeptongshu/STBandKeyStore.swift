// Adapted from cobanov/freeband, commit f677838def2c3dcfc24d0929de492e391d977f14 (MIT).
// Copyright (c) 2026 Mert Cobanov. See FREEBAND-NOTICE.txt.
import Foundation
import Security
import SQLite3

/// One device entry from Mi Fitness's VirtualDevice_registerList.
struct STBandBandKey: Equatable {
    let name: String
    let mac: String?
    let hex: String

    /// Never shows the key itself, only its last four characters.
    var masked: String { String(repeating: "•", count: 8) + hex.suffix(4) }

    var data: Data {
        var out = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            out.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        return out
    }
}

enum STBandKeyLoader {
    enum Failure: LocalizedError {
        case noManifest, unreadable(String), noKeys(String)

        var errorDescription: String? {
            switch self {
            case .noManifest: return String(localized: "No VirtualDevice_registerList/manifest.sqlite in the chosen folder.")
            case .unreadable(let why): return String(localized: "Couldn't read manifest.sqlite: \(why)")
            case .noKeys(let diagnostics): return String(localized: "No encryptKey found. Details: \(diagnostics)")
            }
        }
    }

    /// Accepts the Mi Fitness folder (or any folder above the manifest, or the manifest itself)
    /// and returns every device key found in the registerList_* entries.
    static func load(from url: URL) throws -> [STBandBandKey] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var manifests: [URL] = []
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])
            var visited = 0
            while let file = walker?.nextObject() as? URL {
                visited += 1
                guard visited <= 20_000, manifests.count < 32 else { break }
                if (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    walker?.skipDescendants(); continue
                }
                if file.lastPathComponent == "manifest.sqlite",
                   file.deletingLastPathComponent().lastPathComponent == "VirtualDevice_registerList" {
                    manifests.append(file)
                }
            }
        } else if url.lastPathComponent == "manifest.sqlite" {
            manifests = [url]
        }
        guard !manifests.isEmpty else { throw Failure.noManifest }

        var keys: [STBandBandKey] = []
        var diagnostics: [String] = []
        for manifest in manifests {
            let (found, notes) = try readManifest(manifest)
            diagnostics.append(notes)
            for key in found where !keys.contains(key) {
                keys.append(key)
            }
        }
        guard !keys.isEmpty else {
            throw Failure.noKeys("\(manifests.count) manifest; " + diagnostics.joined(separator: " | "))
        }
        return keys
    }

    /// The manifest is a YYKVStorage cache: a value sits in `inline_data`, or, when it is large,
    /// in `data/<filename>` next to manifest.sqlite. The entry name carries the Xiaomi server
    /// region (registerList_de, registerList_sg, ...). The database is copied with its WAL files
    /// to a temporary folder before it is opened. Diagnostics never contain key material.
    private static func readManifest(_ manifest: URL) throws -> ([STBandBandKey], String) {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: manifest.path + suffix)
            if fm.fileExists(atPath: source.path) {
                let attributes = try fm.attributesOfItem(atPath: source.path)
                guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 32_000_000,
                      attributes[.type] as? FileAttributeType == .typeRegular else { throw Failure.noManifest }
                try fm.copyItem(at: source, to: work.appendingPathComponent("manifest.sqlite" + suffix))
            }
        }

        var db: OpaquePointer?
        guard sqlite3_open(work.appendingPathComponent("manifest.sqlite").path, &db) == SQLITE_OK else {
            throw Failure.unreadable(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_close(db) }

        func rows(_ sql: String) throws -> [[Any?]] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw Failure.unreadable(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            var out: [[Any?]] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                out.append((0..<sqlite3_column_count(statement)).map { i -> Any? in
                    switch sqlite3_column_type(statement, i) {
                    case SQLITE_TEXT: return String(cString: sqlite3_column_text(statement, i))
                    case SQLITE_BLOB:
                        guard let bytes = sqlite3_column_blob(statement, i) else { return Data() }
                        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, i)))
                    case SQLITE_INTEGER: return Int(sqlite3_column_int64(statement, i))
                    default: return nil
                    }
                })
            }
            return out
        }

        let entries = try rows("select key, inline_data, filename from manifest where key like 'registerList%'")
        guard !entries.isEmpty else {
            let names = try rows("select key from manifest limit 15").compactMap { $0[0] as? String }
            return ([], "no registerList entry; entries: \(names)")
        }

        var keys: [STBandBandKey] = []
        var notes: [String] = []
        for entry in entries {
            let name = entry[0] as? String ?? "?"
            var blob = entry[1] as? Data ?? Data()
            var source = "inline \(blob.count)B"
            if blob.isEmpty, let file = entry[2] as? String, !file.isEmpty {
                guard file == URL(fileURLWithPath: file).lastPathComponent, file != ".", file != ".." else { continue }
                let path = manifest.deletingLastPathComponent().appendingPathComponent("data").appendingPathComponent(file)
                let attributes = try fm.attributesOfItem(atPath: path.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 32_000_000 else { continue }
                blob = (try? Data(contentsOf: path)) ?? Data()
                source = "data/ file \(blob.count)B"
            }
            let found = parseRegisterList(blob)
            keys += found
            notes.append("\(name): \(source), bplist=\(blob.starts(with: Data("bplist".utf8))), key=\(found.count)")
        }
        return (keys, notes.joined(separator: "; "))
    }

    /// Finds device dictionaries with an encryptKey in a keyed archive (custom class objects or
    /// NSDictionary), a plain plist, or JSON.
    static func parseRegisterList(_ blob: Data) -> [STBandBandKey] {
        guard blob.count <= 32_000_000 else { return [] }
        let root = (try? PropertyListSerialization.propertyList(from: blob, format: nil))
            ?? (try? JSONSerialization.jsonObject(with: blob))
        guard let root else { return [] }

        let objects = (root as? [String: Any])?["$objects"] as? [Any]
        func deref(_ value: Any?) -> Any? {
            guard let value else { return nil }
            if let objects, let index = uidIndex(value) {
                guard index >= 0, index < objects.count, (objects[index] as? String) != "$null" else { return nil }
                return objects[index]
            }
            return value
        }
        func text(_ value: Any?, depth: Int = 0) -> String? {
            guard depth < 32 else { return nil }
            switch deref(value) {
            case let s as String: return s
            case let d as Data: return d.map { String(format: "%02x", $0) }.joined()
            case let wrapped as [String: Any]:
                return text(wrapped["NS.string"], depth: depth + 1) ?? text(wrapped["NS.bytes"], depth: depth + 1) ?? text(wrapped["NS.data"], depth: depth + 1)
            default: return nil
            }
        }

        var dictionaries: [[String: Any]] = []
        if let objects {
            for case let object as [String: Any] in objects {
                if let names = object["NS.keys"] as? [Any], let values = object["NS.objects"] as? [Any] {
                    var dict: [String: Any] = [:]
                    for (name, value) in zip(names, values) {
                        if let name = text(name) { dict[name] = value }
                    }
                    dictionaries.append(dict)
                } else {
                    dictionaries.append(object)
                }
            }
        } else {
            func walk(_ node: Any) {
                if let dict = node as? [String: Any] {
                    dictionaries.append(dict)
                    dict.values.forEach(walk)
                } else if let list = node as? [Any] {
                    list.forEach(walk)
                }
            }
            walk(root)
        }

        var keys: [STBandBandKey] = []
        for dict in dictionaries {
            guard let field = dict.keys.first(where: { $0.lowercased().replacingOccurrences(of: "_", with: "") == "encryptkey" }),
                  var hex = text(dict[field])?.lowercased() else { continue }
            if hex.hasPrefix("0x") { hex.removeFirst(2) }
            guard hex.count == 32, hex.allSatisfy(\.isHexDigit) else { continue }
            let key = STBandBandKey(name: text(dict["name"]) ?? text(dict["deviceName"]) ?? "(isimsiz)",
                              mac: text(dict["mac"]) ?? text(dict["randomMac"]) ?? text(dict["bleMac"]),
                              hex: hex)
            if !keys.contains(key) { keys.append(key) }
        }
        return keys
    }

    /// NSKeyedArchiver references are CFKeyedArchiverUID values, which Swift only exposes
    /// through their description: "<CFKeyedArchiverUID 0x…>{value = 12}".
    private static func uidIndex(_ value: Any) -> Int? {
        let text = String(describing: value)
        guard text.contains("CFKeyedArchiverUID"),
              let range = text.range(of: #"value = (\d+)"#, options: .regularExpression) else { return nil }
        return Int(text[range].dropFirst("value = ".count))
    }
}
