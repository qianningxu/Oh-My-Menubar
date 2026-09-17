import AppKit
import Common
import Foundation
import SwiftUI

let workspaceSidebarNoteEditorHeight: CGFloat = 240
let workspaceSidebarNoteEditorInset: CGFloat = standardGap * 6
let workspaceSidebarMarkdownDividerAttribute = NSAttributedString.Key("WorkspaceSidebarMarkdownDivider")

let defaultWorkspaceSidebarTasksURL = URL(
    filePath: "/Users/side/Documents/now/my_app/self/self_ob/Others/Tasks",
    directoryHint: .isDirectory,
)

struct WorkspaceSidebarTaskFolder: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct WorkspaceSidebarTaskDocument: Identifiable, Equatable {
    let url: URL
    let folderName: String
    let title: String
    let displayOrder: Int?
    let estimatedHours: String?
    let actualHours: String?
    let frontmatterPrefix: String
    var body: String

    var id: URL { url }
    var locationTitle: String { "\(folderName) | \(title)" }
    var hoursSummary: String { "\(estimatedHours ?? "—")/\(actualHours ?? "—")h" }
}

enum WorkspaceSidebarTaskFile {
    static func folders(
        at rootURL: URL,
        fileManager: FileManager = .default
    ) -> [WorkspaceSidebarTaskFolder] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard url.lastPathComponent.caseInsensitiveCompare("archived") != .orderedSame,
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isDirectory == true,
                  values.isHidden != true
            else { return nil }
            return WorkspaceSidebarTaskFolder(url: url)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func tasks(
        in folder: WorkspaceSidebarTaskFolder,
        fileManager: FileManager = .default
    ) -> [WorkspaceSidebarTaskDocument] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: folder.url,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url -> WorkspaceSidebarTaskDocument? in
            guard url.pathExtension.caseInsensitiveCompare("md") == .orderedSame,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey]),
                  values.isRegularFile == true,
                  values.isHidden != true,
                  let document = load(url: url),
                  !isCompleted(frontmatterPrefix: document.frontmatterPrefix)
            else { return nil }
            return document
        }
        .sorted {
            switch ($0.displayOrder, $1.displayOrder) {
                case let (lhs?, rhs?) where lhs != rhs:
                    return lhs < rhs
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    static func load(url: URL) -> WorkspaceSidebarTaskDocument? {
        guard let data = try? Data(contentsOf: url),
              let contents = String(data: data, encoding: .utf8)
        else { return nil }

        let split = splitFrontmatter(from: contents)
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        return WorkspaceSidebarTaskDocument(
            url: url,
            folderName: url.deletingLastPathComponent().lastPathComponent,
            title: metadataValue(named: "title", in: split.prefix).map(unquote) ?? fallbackTitle,
            displayOrder: metadataValue(named: "display_order", in: split.prefix).flatMap(Int.init),
            estimatedHours: metadataValue(named: "estimated", in: split.prefix).map(unquote),
            actualHours: metadataValue(named: "actual", in: split.prefix).map(unquote),
            frontmatterPrefix: split.prefix,
            body: split.body
        )
    }

    static func save(_ document: WorkspaceSidebarTaskDocument) throws {
        let contents = document.frontmatterPrefix + document.body
        try Data(contents.utf8).write(to: document.url, options: .atomic)
    }

    static func isCompleted(frontmatterPrefix: String) -> Bool {
        guard let value = metadataValue(named: "completed", in: frontmatterPrefix) else { return false }
        return unquote(value).caseInsensitiveCompare("true") == .orderedSame
    }

    static func splitFrontmatter(from contents: String) -> (prefix: String, body: String) {
        let newline: String
        if contents.hasPrefix("---\r\n") {
            newline = "\r\n"
        } else if contents.hasPrefix("---\n") {
            newline = "\n"
        } else {
            return ("", contents)
        }

        let closingMarker = newline + "---" + newline
        let searchStart = contents.index(contents.startIndex, offsetBy: 3 + newline.count)
        if let range = contents.range(of: closingMarker, range: searchStart ..< contents.endIndex) {
            return (String(contents[..<range.upperBound]), String(contents[range.upperBound...]))
        }

        let closingAtEnd = newline + "---"
        if contents[searchStart...].hasSuffix(closingAtEnd) {
            return (contents, "")
        }
        return ("", contents)
    }

    private static func metadataValue(named key: String, in frontmatterPrefix: String) -> String? {
        for line in frontmatterPrefix.split(whereSeparator: \ .isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == key
            else { continue }
            return parts[1].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"" || first == "'" && last == "'")
        else { return value }
        return String(value.dropFirst().dropLast())
    }
}

private struct WorkspaceSidebarTaskSelectionEnvelope: Codable {
    let version: Int
    var selectedPaths: [String: String]
}

private final class WorkspaceSidebarTaskPathWatcher {
    private let source: DispatchSourceFileSystemObject
    private let fd: Int32

    init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler {
            MainActor.checkIsolated { onChange() }
        }
        source.setCancelHandler { [fd] in close(fd) }
        source.activate()
    }

    deinit {
        source.cancel()
    }
}

private final class WorkspaceSidebarTaskWatcherPair {
    let file: WorkspaceSidebarTaskPathWatcher?
    let folder: WorkspaceSidebarTaskPathWatcher?

    init(file: WorkspaceSidebarTaskPathWatcher?, folder: WorkspaceSidebarTaskPathWatcher?) {
        self.file = file
        self.folder = folder
    }
}

@MainActor
final class WorkspaceSidebarTodoStore: ObservableObject {
    static let shared = WorkspaceSidebarTodoStore()

    @Published private(set) var documents: [String: WorkspaceSidebarTaskDocument] = [:]
    @Published private(set) var errors: [String: String] = [:]

    let tasksRootURL: URL
    private(set) var selectedPaths: [String: String] = [:]

    private let storageURL: URL
    private let fileManager: FileManager
    private var restoredWidgetIDs: Set<String> = []
    private var watchers: [String: WorkspaceSidebarTaskWatcherPair] = [:]
    private var refreshTasks: [String: Task<Void, Never>] = [:]

    init(
        tasksRootURL: URL = defaultWorkspaceSidebarTasksURL,
        storageURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.tasksRootURL = tasksRootURL
        self.fileManager = fileManager
        self.storageURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)
        loadSelections()
    }

    func folders() -> [WorkspaceSidebarTaskFolder] {
        WorkspaceSidebarTaskFile.folders(at: tasksRootURL, fileManager: fileManager)
    }

    func tasks(in folder: WorkspaceSidebarTaskFolder) -> [WorkspaceSidebarTaskDocument] {
        WorkspaceSidebarTaskFile.tasks(in: folder, fileManager: fileManager)
    }

    func restoreSelection(for widgetID: String) {
        guard restoredWidgetIDs.insert(widgetID).inserted else { return }
        guard let path = selectedPaths[widgetID] else { return }
        selectTask(at: URL(filePath: path), widgetID: widgetID, persistSelection: false)
    }

    func document(for widgetID: String) -> WorkspaceSidebarTaskDocument? {
        documents[widgetID]
    }

    func selectTask(_ task: WorkspaceSidebarTaskDocument, widgetID: String) {
        selectTask(at: task.url, widgetID: widgetID, persistSelection: true)
    }

    func updateBody(_ body: String, widgetID: String) {
        guard var document = documents[widgetID] else { return }
        document.body = body
        documents[widgetID] = document
        do {
            try WorkspaceSidebarTaskFile.save(document)
            errors.removeValue(forKey: widgetID)
        } catch {
            errors[widgetID] = "Couldn’t save this note."
        }
    }

    func refreshSelection(for widgetID: String) {
        guard let document = documents[widgetID] else { return }
        guard let refreshed = WorkspaceSidebarTaskFile.load(url: document.url),
              !WorkspaceSidebarTaskFile.isCompleted(frontmatterPrefix: refreshed.frontmatterPrefix)
        else {
            clearSelection(widgetID: widgetID)
            return
        }
        if refreshed != document {
            documents[widgetID] = refreshed
        }
        installWatchers(for: refreshed.url, widgetID: widgetID)
    }

    private func selectTask(at url: URL, widgetID: String, persistSelection: Bool) {
        guard url.path.hasPrefix(tasksRootURL.path + "/"),
              !url.pathComponents.dropFirst(tasksRootURL.pathComponents.count).contains(where: {
                  $0.caseInsensitiveCompare("archived") == .orderedSame
              }),
              let document = WorkspaceSidebarTaskFile.load(url: url),
              !WorkspaceSidebarTaskFile.isCompleted(frontmatterPrefix: document.frontmatterPrefix)
        else {
            clearSelection(widgetID: widgetID)
            return
        }
        documents[widgetID] = document
        selectedPaths[widgetID] = url.path
        errors.removeValue(forKey: widgetID)
        if persistSelection { persistSelections() }
        installWatchers(for: url, widgetID: widgetID)
    }

    private func clearSelection(widgetID: String) {
        documents.removeValue(forKey: widgetID)
        selectedPaths.removeValue(forKey: widgetID)
        errors.removeValue(forKey: widgetID)
        watchers.removeValue(forKey: widgetID)
        refreshTasks[widgetID]?.cancel()
        refreshTasks.removeValue(forKey: widgetID)
        persistSelections()
    }

    private func installWatchers(for url: URL, widgetID: String) {
        watchers.removeValue(forKey: widgetID)
        let onChange: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.refreshTasks[widgetID]?.cancel()
            self.refreshTasks[widgetID] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                self?.refreshSelection(for: widgetID)
            }
        }
        watchers[widgetID] = WorkspaceSidebarTaskWatcherPair(
            file: WorkspaceSidebarTaskPathWatcher(url: url, onChange: onChange),
            folder: WorkspaceSidebarTaskPathWatcher(url: url.deletingLastPathComponent(), onChange: onChange)
        )
    }

    private func loadSelections() {
        guard let data = try? Data(contentsOf: storageURL),
              let envelope = try? JSONDecoder().decode(WorkspaceSidebarTaskSelectionEnvelope.self, from: data),
              envelope.version == 1
        else {
            selectedPaths = [:]
            return
        }
        selectedPaths = envelope.selectedPaths
    }

    private func persistSelections() {
        do {
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let envelope = WorkspaceSidebarTaskSelectionEnvelope(version: 1, selectedPaths: selectedPaths)
            try JSONEncoder.winMuxDefault.encode(envelope).write(to: storageURL, options: .atomic)
        } catch {
            // Selection persistence is best effort and must not interrupt editing.
        }
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(component: "Library/Application Support")
        return appSupport
            .appending(component: winMuxAppName, directoryHint: .isDirectory)
            .appending(component: "sidebar-task-note-selection.json", directoryHint: .notDirectory)
    }
}

struct WorkspaceSidebarTodoListWidget: View {
    let id: String
    let sectionWidth: CGFloat
    let isCompact: Bool

    @ObservedObject private var store = WorkspaceSidebarTodoStore.shared
    @State private var pickerFolder: WorkspaceSidebarTaskFolder?
    @State private var isChoosingTask = false

    var body: some View {
        Group {
            if isCompact {
                Image(systemName: "note.text")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(workspaceSidebarWidgetContent(.primary))
                    .frame(width: sectionWidth, height: 52)
                    .background(WorkspaceSidebarStatusCardBackground())
                    .accessibilityLabel("Task note")
            } else {
                expandedContent
                    .frame(width: sectionWidth, height: workspaceSidebarNoteEditorHeight)
                    .background(WorkspaceSidebarStatusCardBackground())
            }
        }
        .id(id)
        .padding(.bottom, standardGap * 2)
        .onAppear { store.restoreSelection(for: id) }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if isChoosingTask || store.document(for: id) == nil {
            WorkspaceSidebarTaskPicker(
                folders: store.folders(),
                selectedFolder: $pickerFolder,
                tasks: pickerFolder.map(store.tasks) ?? [],
                onSelectFolder: selectFolder,
                onSelectTask: selectTask
            )
        } else if let document = store.document(for: id) {
            VStack(spacing: standardGap * 0) {
                VStack(alignment: .leading, spacing: standardGap * 0.5) {
                    HStack(spacing: standardGap * 3) {
                        Text(document.locationTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(workspaceSidebarWidgetContent(.primary))
                            .lineLimit(1)
                            .layoutPriority(1)
                        Spacer(minLength: 2)
                        Button {
                            pickerFolder = nil
                            isChoosingTask = true
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(workspaceSidebarWidgetContent(.primary))
                        .accessibilityLabel("Switch task note")
                    }

                    Text(document.hoursSummary)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                        .lineLimit(1)
                }
                .padding(.leading, workspaceSidebarNoteEditorInset)
                .padding(.trailing, standardGap * 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 58)

                WorkspaceSidebarNoteTextView(text: Binding(
                    get: { store.document(for: id)?.body ?? "" },
                    set: { store.updateBody($0, widgetID: id) }
                ))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Editing \(document.locationTitle), estimated and actual hours \(document.hoursSummary)")

                if let error = store.errors[id] {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(workspaceSidebarWidgetSemanticColor(.red, .color9))
                        .padding(.horizontal, workspaceSidebarNoteEditorInset)
                        .padding(.bottom, standardGap * 2)
                }
            }
        }
    }

    private func selectFolder(_ folder: WorkspaceSidebarTaskFolder) {
        let tasks = store.tasks(in: folder)
        if tasks.count == 1, let task = tasks.first {
            selectTask(task)
        } else {
            pickerFolder = folder
            isChoosingTask = true
        }
    }

    private func selectTask(_ task: WorkspaceSidebarTaskDocument) {
        store.selectTask(task, widgetID: id)
        pickerFolder = nil
        isChoosingTask = false
    }
}

private struct WorkspaceSidebarTaskPicker: View {
    let folders: [WorkspaceSidebarTaskFolder]
    @Binding var selectedFolder: WorkspaceSidebarTaskFolder?
    let tasks: [WorkspaceSidebarTaskDocument]
    let onSelectFolder: (WorkspaceSidebarTaskFolder) -> Void
    let onSelectTask: (WorkspaceSidebarTaskDocument) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: standardGap * 3) {
            HStack {
                if selectedFolder != nil {
                    Button {
                        selectedFolder = nil
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to task folders")
                }
                Text(selectedFolder?.name ?? "Choose a task folder")
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(workspaceSidebarWidgetContent(.primary))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: standardGap * 1) {
                    if let selectedFolder {
                        if tasks.isEmpty {
                            Text("No incomplete tasks in \(selectedFolder.name)")
                                .font(.system(size: 11.5))
                                .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                                .padding(.vertical, standardGap * 4)
                        } else {
                            ForEach(tasks) { task in
                                pickerButton(task.title, systemImage: "doc.text") {
                                    onSelectTask(task)
                                }
                            }
                        }
                    } else if folders.isEmpty {
                        Text("No task folders found")
                            .font(.system(size: 11.5))
                            .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                            .padding(.vertical, standardGap * 4)
                    } else {
                        ForEach(folders) { folder in
                            pickerButton(folder.name, systemImage: "folder") {
                                onSelectFolder(folder)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(workspaceSidebarNoteEditorInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(selectedFolder == nil ? "Task folders" : "Incomplete tasks")
    }

    private func pickerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(workspaceSidebarWidgetContent(.primary))
    }
}

enum WorkspaceSidebarMarkdownBlending {
    @MainActor
    static func apply(
        to textView: NSTextView,
        palette: WinMuxOverlayPalette = .current
    ) {
        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        let textColor = palette.contentNSColor(.primary)

        textStorage.beginEditing()
        if fullRange.length > 0 {
            textStorage.removeAttribute(workspaceSidebarMarkdownDividerAttribute, range: fullRange)
            textStorage.removeAttribute(.glyphInfo, range: fullRange)
            textStorage.removeAttribute(.paragraphStyle, range: fullRange)
            textStorage.addAttributes([.font: font, .foregroundColor: textColor], range: fullRange)
        }

        let source = textStorage.string as NSString
        let selectionLocation = min(textView.selectedRange().location, source.length)
        var location = 0
        while location < source.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            source.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: location, length: 0)
            )
            let contentRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            let content = source.substring(with: contentRange)
            let selectionIsOnLine = selectionLocation >= lineStart && selectionLocation < lineEnd

            if content.trimmingCharacters(in: .whitespaces) == "---", !selectionIsOnLine {
                let dividerBlock = NSTextBlock()
                dividerBlock.setValue(100, type: .percentageValueType, for: .width)
                dividerBlock.setWidth(1, type: .absoluteValueType, for: .border, edge: .minY)
                dividerBlock.setBorderColor(
                    palette.geistBorderNSColor(.normal),
                    for: .minY
                )
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.textBlocks = [dividerBlock]
                paragraphStyle.paragraphSpacingBefore = standardGap * 2.5
                paragraphStyle.paragraphSpacing = standardGap * 2
                textStorage.addAttribute(
                    workspaceSidebarMarkdownDividerAttribute,
                    value: true,
                    range: contentRange
                )
                textStorage.addAttribute(.foregroundColor, value: WinMuxDesignTokens.transparentNSColor, range: contentRange)
                textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: contentRange)
            } else if let bullet = bulletPrefix(in: content), !selectionIsOnLine {
                let markerRange = NSRange(location: lineStart + bullet.markerOffset, length: 1)
                if let glyphInfo = bulletGlyphInfo(font: font) {
                    textStorage.addAttribute(.glyphInfo, value: glyphInfo, range: markerRange)
                }
                let paragraphStyle = NSMutableParagraphStyle()
                let spaceWidth = " ".size(withAttributes: [.font: font]).width
                let nestingLevel = max(0, bullet.indentationColumns / 2)
                paragraphStyle.textLists = (0 ... nestingLevel).map { _ in
                    NSTextList(markerFormat: .disc, options: 0)
                }
                paragraphStyle.firstLineHeadIndent = 0
                paragraphStyle.headIndent = CGFloat(bullet.indentationColumns + 2) * spaceWidth
                textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: contentRange)
            }

            guard lineEnd > location else { break }
            location = lineEnd
        }
        textStorage.endEditing()

        textView.typingAttributes = [.font: font, .foregroundColor: textColor]
        textView.layoutManager?.invalidateDisplay(forCharacterRange: fullRange)
    }

    static func bulletPrefix(in line: String) -> (markerOffset: Int, indentationColumns: Int)? {
        var markerOffset = 0
        var indentationColumns = 0
        for character in line {
            if character == " " {
                markerOffset += 1
                indentationColumns += 1
            } else if character == "\t" {
                markerOffset += 1
                indentationColumns += 4
            } else {
                break
            }
        }

        let markerIndex = line.index(line.startIndex, offsetBy: markerOffset)
        guard markerIndex < line.endIndex,
              line[markerIndex] == "-",
              let spaceIndex = line.index(markerIndex, offsetBy: 1, limitedBy: line.endIndex),
              spaceIndex < line.endIndex,
              line[spaceIndex] == " "
        else { return nil }
        return (markerOffset, indentationColumns)
    }

    @MainActor
    static func adjustBulletIndent(
        in textView: NSTextView,
        direction: Int,
        palette: WinMuxOverlayPalette = .current
    ) -> Bool {
        let source = textView.string as NSString
        let selection = textView.selectedRange()
        guard source.length > 0 else { return false }
        let safeLocation = min(selection.location, max(0, source.length - 1))
        let probeRange = NSRange(location: safeLocation, length: selection.length)
        let affectedRange = source.lineRange(for: probeRange)
        let block = source.substring(with: affectedRange) as NSString
        let replacement = NSMutableString()
        var location = 0
        var changed = false
        var caretDelta = 0

        while location < block.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            block.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: location, length: 0)
            )
            let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            var line = block.substring(with: lineRange)
            let ending = block.substring(with: NSRange(location: contentsEnd, length: lineEnd - contentsEnd))

            if bulletPrefix(in: line) != nil {
                if direction > 0 {
                    line = "  " + line
                    changed = true
                    if affectedRange.location + lineStart <= selection.location { caretDelta += 2 }
                } else if line.hasPrefix("\t") {
                    line.removeFirst()
                    changed = true
                    if affectedRange.location + lineStart < selection.location { caretDelta -= 1 }
                } else {
                    let removableSpaces = min(2, line.prefix(while: { $0 == " " }).count)
                    if removableSpaces > 0 {
                        line.removeFirst(removableSpaces)
                        changed = true
                        if affectedRange.location + lineStart < selection.location { caretDelta -= removableSpaces }
                    }
                }
            }

            replacement.append(line)
            replacement.append(ending)
            guard lineEnd > location else { break }
            location = lineEnd
        }

        guard changed,
              textView.shouldChangeText(in: affectedRange, replacementString: replacement as String)
        else { return false }
        textView.textStorage?.replaceCharacters(in: affectedRange, with: replacement as String)
        textView.didChangeText()
        if selection.length == 0 {
            textView.setSelectedRange(NSRange(
                location: max(affectedRange.location, selection.location + caretDelta),
                length: 0
            ))
        } else {
            textView.setSelectedRange(NSRange(location: affectedRange.location, length: replacement.length))
        }
        apply(to: textView, palette: palette)
        return true
    }

    private static func bulletGlyphInfo(font: NSFont) -> NSGlyphInfo? {
        let glyph = font.glyph(withName: "bullet")
        return NSGlyphInfo(cgGlyph: CGGlyph(glyph), for: font, baseString: "-")
    }
}

struct WorkspaceSidebarNoteTextView: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.string = text
        Self.configure(scrollView: scrollView, textView: textView, palette: palette)
        WorkspaceSidebarMarkdownBlending.apply(to: textView, palette: palette)
        context.coordinator.installClickActivation(for: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
        textView.textColor = palette.contentNSColor(.primary)
        textView.insertionPointColor = palette.contentNSColor(.primary)
        WorkspaceSidebarMarkdownBlending.apply(to: textView, palette: palette)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.removeClickActivation()
    }

    @MainActor
    static func makeConfiguredTextViewForTesting() -> (NSScrollView, NSTextView) {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        configure(scrollView: scrollView, textView: textView, palette: .current)
        return (scrollView, textView)
    }

    @MainActor
    private static func configure(
        scrollView: NSScrollView,
        textView: NSTextView,
        palette: WinMuxOverlayPalette
    ) {
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: workspaceSidebarNoteEditorHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: workspaceSidebarNoteEditorInset, height: workspaceSidebarNoteEditorInset)
        textView.font = .systemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = palette.contentNSColor(.primary)
        textView.insertionPointColor = palette.contentNSColor(.primary)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WorkspaceSidebarNoteTextView
        private var clickMonitor: Any?

        init(parent: WorkspaceSidebarNoteTextView) { self.parent = parent }

        deinit {
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        }

        @MainActor
        func installClickActivation(for textView: NSTextView) {
            removeClickActivation()
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak textView] event in
                guard let textView,
                      event.window === textView.window,
                      textView.visibleRect.contains(textView.convert(event.locationInWindow, from: nil))
                else { return event }

                let panel = (textView.window as? WorkspaceSidebarPanel) ?? WorkspaceSidebarPanel.shared
                panel.prepareForInlineTextEditing()
                textView.window?.makeFirstResponder(textView)
                return event
            }
        }

        @MainActor
        func removeClickActivation() {
            guard let clickMonitor else { return }
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            WorkspaceSidebarMarkdownBlending.apply(to: textView, palette: parent.palette)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            WorkspaceSidebarMarkdownBlending.apply(to: textView, palette: parent.palette)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                return WorkspaceSidebarMarkdownBlending.adjustBulletIndent(
                    in: textView,
                    direction: 1,
                    palette: parent.palette
                )
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                return WorkspaceSidebarMarkdownBlending.adjustBulletIndent(
                    in: textView,
                    direction: -1,
                    palette: parent.palette
                )
            }
            return false
        }
    }
}
