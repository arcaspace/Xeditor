import Foundation

struct DirSearchOptions {
    let directory: URL
    let query: SearchQuery
    let fileTypes: String
    let fileNameRegex: String
    let skipFolders: String
    let skipHidden: Bool
    let skipBinary: Bool
    let skipLargeFiles: Bool
    let maxFileSize: Int
    let skipSubdirectories: Bool
}

struct DirSearchHit {
    let url: URL
    let line: Int
    /// UTF-16 range inside the line, ready for `selectLine:rangeInLine:`.
    let rangeInLine: NSRange
    let preview: String
}

struct DirReplaceSummary {
    var replaced = 0
    var filesChanged = 0
    var filesScanned = 0
    var skipped: [String] = []
}

/// Directory-wide search and replace. Foundation only: it never touches
/// Scintilla, so it is safe to run on a background queue.
final class DirFinder {
    private let queue = DispatchQueue(label: "com.xeditor.dirfind", qos: .userInitiated)
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    // MARK: - Search

    func search(options: DirSearchOptions,
                hitLimit: Int = 20_000,
                onProgress: @escaping (Int, Int, Int) -> Void,
                onBatch: @escaping ([DirSearchHit]) -> Void,
                completion: @escaping (_ truncated: Bool, _ cancelled: Bool, _ error: String?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.cancelled = false
            self.lock.unlock()

            guard let regex = Self.makeRegex(query: options.query) else {
                DispatchQueue.main.async { completion(false, false, "Invalid regular expression.") }
                return
            }

            let files = Self.candidateFiles(options: options)
            let total = files.count
            var scanned = 0
            var hits: [DirSearchHit] = []
            var pending: [DirSearchHit] = []
            var truncated = false
            var wasCancelled = false

            for url in files {
                if self.isCancelled { wasCancelled = true; break }
                scanned += 1

                defer {
                    if !pending.isEmpty {
                        let batch = pending
                        pending.removeAll()
                        hits.append(contentsOf: batch)
                        DispatchQueue.main.async { onBatch(batch) }
                    }
                }

                guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { continue }
                if options.skipLargeFiles && data.count > options.maxFileSize { continue }
                if options.skipBinary && Self.looksBinary(data) { continue }
                guard let decoded = FileEncodingDetector.decode(data) else { continue }

                let text = decoded.text
                let nsText = text as NSString
                let starts = Self.lineStarts(text)
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

                for match in matches where match.range.length > 0 {
                    let lineIndex = Self.lineIndex(for: match.range.location, starts: starts)
                    let lineStart = starts[lineIndex]
                    let lineEnd = lineIndex + 1 < starts.count ? starts[lineIndex + 1] - 1 : nsText.length
                    let lineRange = NSRange(location: lineStart, length: max(0, lineEnd - lineStart))
                    let lineText = nsText.substring(with: lineRange)
                    let inLine = NSRange(location: match.range.location - lineStart, length: match.range.length)
                    pending.append(DirSearchHit(url: url,
                                                line: lineIndex + 1,
                                                rangeInLine: inLine,
                                                preview: SearchResultsModel.preview(lineText: lineText,
                                                                                   matchOffset: inLine.location)))
                    if hits.count + pending.count >= hitLimit {
                        truncated = true
                        break
                    }
                }

                if scanned % 8 == 0 || !pending.isEmpty {
                    let scannedNow = scanned
                    let hitsNow = hits.count + pending.count
                    DispatchQueue.main.async { onProgress(scannedNow, total, hitsNow) }
                }

                if truncated { break }
            }

            DispatchQueue.main.async {
                onProgress(scanned, total, hits.count)
                completion(truncated, wasCancelled, nil)
            }
        }
    }

    // MARK: - Replace

    func replaceAll(options: DirSearchOptions,
                    onProgress: @escaping (Int, Int) -> Void,
                    completion: @escaping (DirReplaceSummary, String?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.cancelled = false
            self.lock.unlock()

            guard let regex = Self.makeRegex(query: options.query) else {
                DispatchQueue.main.async { completion(DirReplaceSummary(), "Invalid regular expression.") }
                return
            }

            var summary = DirReplaceSummary()
            let files = Self.candidateFiles(options: options)
            let template = options.query.isRegex
                ? options.query.foundationReplacement
                : NSRegularExpression.escapedTemplate(for: options.query.replacement)

            for url in files {
                if self.isCancelled { break }
                summary.filesScanned += 1
                defer {
                    if summary.filesScanned % 8 == 0 {
                        let scanned = summary.filesScanned
                        let total = files.count
                        DispatchQueue.main.async { onProgress(scanned, total) }
                    }
                }

                guard FileManager.default.isWritableFile(atPath: url.path) else {
                    summary.skipped.append(url.lastPathComponent)
                    continue
                }
                guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
                    summary.skipped.append(url.lastPathComponent)
                    continue
                }
                if options.skipLargeFiles && data.count > options.maxFileSize {
                    summary.skipped.append(url.lastPathComponent)
                    continue
                }
                if options.skipBinary && Self.looksBinary(data) { continue }
                guard let decoded = FileEncodingDetector.decode(data) else { continue }

                let replaced = regex.stringByReplacingMatches(in: decoded.text,
                                                              range: NSRange(location: 0, length: (decoded.text as NSString).length),
                                                              withTemplate: template)
                guard replaced != decoded.text else { continue }
                guard let out = FileEncodingDetector.encode(replaced,
                                                            encoding: decoded.encoding,
                                                            hadBOM: decoded.hadBOM) else {
                    summary.skipped.append(url.lastPathComponent)
                    continue
                }
                do {
                    try out.write(to: url, options: .atomic)
                    summary.filesChanged += 1
                    let count = regex.numberOfMatches(in: decoded.text,
                                                      range: NSRange(location: 0, length: (decoded.text as NSString).length))
                    summary.replaced += count
                } catch {
                    summary.skipped.append(url.lastPathComponent)
                }
            }

            DispatchQueue.main.async {
                onProgress(summary.filesScanned, files.count)
                completion(summary, nil)
            }
        }
    }

    // MARK: - Filtering helpers

    static func makeRegex(query: SearchQuery) -> NSRegularExpression? {
        var pattern = query.foundationPattern
        if query.wholeWord && !query.isRegex {
            pattern = "\\b" + pattern + "\\b"
        }
        return try? NSRegularExpression(pattern: pattern, options: query.foundationOptions)
    }

    static func candidateFiles(options: DirSearchOptions) -> [URL] {
        let fm = FileManager.default
        var fileOptions: FileManager.DirectoryEnumerationOptions = []
        if options.skipHidden { fileOptions.insert(.skipsHiddenFiles) }
        if options.skipSubdirectories { fileOptions.insert(.skipsSubdirectoryDescendants) }

        let skipNames = Set(options.skipFolders
            .split(whereSeparator: { $0 == ":" || $0 == ";" })
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty })

        let nameFilter: NSRegularExpression? = options.fileNameRegex.isEmpty
            ? nil
            : try? NSRegularExpression(pattern: options.fileNameRegex,
                                       options: [.caseInsensitive])

        var files: [URL] = []
        guard let enumerator = fm.enumerator(at: options.directory,
                                             includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                             options: fileOptions) else {
            return files
        }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = values?.isDirectory ?? false
            if isDirectory {
                if skipNames.contains(url.lastPathComponent.lowercased()) {
                    enumerator.skipDescendants()
                    continue
                }
                continue
            }
            guard matchesFileTypes(url.lastPathComponent, patterns: options.fileTypes) else { continue }
            if let nameFilter {
                let name = url.lastPathComponent as NSString
                let range = NSRange(location: 0, length: name.length)
                guard nameFilter.firstMatch(in: name as String, range: range) != nil else { continue }
            }
            if options.skipHidden && url.lastPathComponent.hasPrefix(".") { continue }
            files.append(url)
        }
        return files
    }

    static func matchesFileTypes(_ name: String, patterns: String) -> Bool {
        let list = patterns
            .split(whereSeparator: { $0 == ":" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !list.isEmpty else { return true }

        let lower = name.lowercased()
        return list.contains { pattern in
            let p = pattern.lowercased()
            if p.hasPrefix("*.") {
                return lower.hasSuffix(String(p.dropFirst(1)))
            }
            if p.hasPrefix("*") {
                return lower.hasSuffix(String(p.dropFirst()))
            }
            return lower == p
        }
    }

    static func looksBinary(_ data: Data) -> Bool {
        let sample = data.prefix(8000)
        return sample.contains(0)
    }

    // MARK: - Text helpers

    /// UTF-16 offsets of each line start.
    static func lineStarts(_ text: String) -> [Int] {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 10 { starts.append(offset) }
        }
        return starts
    }

    static func lineIndex(for location: Int, starts: [Int]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= location {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}
