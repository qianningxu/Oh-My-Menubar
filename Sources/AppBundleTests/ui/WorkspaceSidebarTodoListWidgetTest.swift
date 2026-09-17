@testable import AppBundle
import AppKit
import Foundation
import XCTest

@MainActor
final class WorkspaceSidebarTodoListWidgetTest: XCTestCase {
    func testDiscoversTopLevelFoldersAndExcludesArchivedAndHiddenFolders() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.makeDirectory("zeta")
        try fixture.makeDirectory("Alpha")
        try fixture.makeDirectory("archived")
        try fixture.makeDirectory("ARCHIVED")
        try fixture.makeDirectory(".hidden")
        try Data().write(to: fixture.rootURL.appending(component: "not-a-folder"))

        XCTAssertEqual(
            WorkspaceSidebarTaskFile.folders(at: fixture.rootURL).map(\.name),
            ["Alpha", "zeta"]
        )
    }

    func testFiltersCompletedAndNonMarkdownFilesAndOrdersTasks() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let folderURL = try fixture.makeDirectory("Project")
        try fixture.writeTask(folderURL: folderURL, filename: "later.md", title: "Later", completed: false, order: 20)
        try fixture.writeTask(folderURL: folderURL, filename: "first.md", title: "First", completed: false, order: 1)
        try fixture.writeTask(folderURL: folderURL, filename: "done.md", title: "Done", completed: true, order: 0)
        try fixture.write(contents: "plain note", to: folderURL.appending(component: "Fallback.md"))
        try fixture.write(contents: "ignore", to: folderURL.appending(component: "ignore.txt"))

        let folder = WorkspaceSidebarTaskFolder(url: folderURL)
        let tasks = WorkspaceSidebarTaskFile.tasks(in: folder)

        XCTAssertEqual(tasks.map(\.title), ["First", "Later", "Fallback"])
        XCTAssertEqual(tasks.map(\.url.lastPathComponent), ["first.md", "later.md", "Fallback.md"])
        XCTAssertEqual(tasks[0].locationTitle, "Project | First")
        XCTAssertEqual(tasks[0].hoursSummary, "2.0/0.5h")
        XCTAssertEqual(tasks[2].hoursSummary, "—/—h")
    }

    func testMissingOrMalformedFrontmatterRemainsEligible() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let folderURL = try fixture.makeDirectory("Project")
        try fixture.write(contents: "---\ntitle: Broken\ncompleted: true\nNo closing marker", to: folderURL.appending(component: "broken.md"))
        try fixture.write(contents: "---\ntitle: False value\ncompleted: definitely\n---\nBody", to: folderURL.appending(component: "false-value.md"))

        let tasks = WorkspaceSidebarTaskFile.tasks(in: WorkspaceSidebarTaskFolder(url: folderURL))

        XCTAssertEqual(tasks.map(\.title), ["broken", "False value"])
    }

    func testLoadsBodyAndPreservesFrontmatterExactlyWhenSaving() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let fileURL = fixture.rootURL.appending(component: "task.md")
        let prefix = "---\r\ntitle: \"Task\"\r\ncompleted: false\r\n---\r\n"
        try fixture.write(contents: prefix + "\r\n# Task\r\nOld body", to: fileURL)

        var document = try XCTUnwrap(WorkspaceSidebarTaskFile.load(url: fileURL))
        XCTAssertEqual(document.frontmatterPrefix, prefix)
        XCTAssertEqual(document.body, "\r\n# Task\r\nOld body")

        document.body = "\n# Task\nNew body"
        try WorkspaceSidebarTaskFile.save(document)

        let saved = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(saved.hasPrefix(prefix))
        XCTAssertEqual(saved, prefix + "\n# Task\nNew body")
    }

    func testSelectionPersistsIndependentlyByWidgetID() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let folderURL = try fixture.makeDirectory("Project")
        let firstURL = try fixture.writeTask(folderURL: folderURL, filename: "first.md", title: "First", completed: false, order: 1)
        let secondURL = try fixture.writeTask(folderURL: folderURL, filename: "second.md", title: "Second", completed: false, order: 2)
        let first = try XCTUnwrap(WorkspaceSidebarTaskFile.load(url: firstURL))
        let second = try XCTUnwrap(WorkspaceSidebarTaskFile.load(url: secondURL))

        let store = WorkspaceSidebarTodoStore(tasksRootURL: fixture.rootURL, storageURL: fixture.storageURL)
        store.selectTask(first, widgetID: "one")
        store.selectTask(second, widgetID: "two")

        let reloaded = WorkspaceSidebarTodoStore(tasksRootURL: fixture.rootURL, storageURL: fixture.storageURL)
        reloaded.restoreSelection(for: "one")
        reloaded.restoreSelection(for: "two")
        XCTAssertEqual(reloaded.document(for: "one")?.url, firstURL)
        XCTAssertEqual(reloaded.document(for: "two")?.url, secondURL)
    }

    func testEditingSavesImmediatelyAndUpdatesSharedStoreDocument() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let folderURL = try fixture.makeDirectory("Project")
        let fileURL = try fixture.writeTask(folderURL: folderURL, filename: "task.md", title: "Task", completed: false, order: 1)
        let task = try XCTUnwrap(WorkspaceSidebarTaskFile.load(url: fileURL))
        let store = WorkspaceSidebarTodoStore(tasksRootURL: fixture.rootURL, storageURL: fixture.storageURL)
        store.selectTask(task, widgetID: "note")

        store.updateBody("\nUpdated in WinMux", widgetID: "note")

        XCTAssertEqual(store.document(for: "note")?.body, "\nUpdated in WinMux")
        XCTAssertEqual(WorkspaceSidebarTaskFile.load(url: fileURL)?.body, "\nUpdated in WinMux")
    }

    func testRefreshLoadsExternalChangesAndClearsInvalidSelection() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let folderURL = try fixture.makeDirectory("Project")
        let fileURL = try fixture.writeTask(folderURL: folderURL, filename: "task.md", title: "Task", completed: false, order: 1)
        let task = try XCTUnwrap(WorkspaceSidebarTaskFile.load(url: fileURL))
        let store = WorkspaceSidebarTodoStore(tasksRootURL: fixture.rootURL, storageURL: fixture.storageURL)
        store.selectTask(task, widgetID: "note")

        try fixture.writeTask(folderURL: folderURL, filename: "task.md", title: "Task", completed: false, order: 1, body: "Externally changed")
        store.refreshSelection(for: "note")
        XCTAssertEqual(store.document(for: "note")?.body, "\nExternally changed")

        try fixture.writeTask(folderURL: folderURL, filename: "task.md", title: "Task", completed: true, order: 1)
        store.refreshSelection(for: "note")
        XCTAssertNil(store.document(for: "note"))

        let reopened = try fixture.writeTask(folderURL: folderURL, filename: "task.md", title: "Task", completed: false, order: 1)
        store.selectTask(try XCTUnwrap(WorkspaceSidebarTaskFile.load(url: reopened)), widgetID: "note")
        try FileManager.default.removeItem(at: reopened)
        store.refreshSelection(for: "note")
        XCTAssertNil(store.document(for: "note"))
    }

    func testMalformedSelectionPersistenceLoadsAsEmpty() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("not-json".utf8).write(to: fixture.storageURL, options: .atomic)

        let store = WorkspaceSidebarTodoStore(tasksRootURL: fixture.rootURL, storageURL: fixture.storageURL)

        XCTAssertEqual(store.selectedPaths, [:])
    }

    func testEditorUsesNativePlainMultilineTextBehavior() {
        let (scrollView, textView) = WorkspaceSidebarNoteTextView.makeConfiguredTextViewForTesting()

        XCTAssertTrue(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(textView.isRichText)
        XCTAssertFalse(textView.drawsBackground)
        XCTAssertTrue(textView.allowsUndo)
        XCTAssertTrue(textView.isVerticallyResizable)
        XCTAssertFalse(textView.isHorizontallyResizable)
        XCTAssertTrue(textView.textContainer?.widthTracksTextView == true)
        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertTrue(type(of: textView) == NSTextView.self)
        XCTAssertEqual(workspaceSidebarNoteEditorHeight, 240)
        XCTAssertEqual(textView.minSize.height, workspaceSidebarNoteEditorHeight)
        XCTAssertEqual(textView.textContainerInset.width, workspaceSidebarNoteEditorInset)
        XCTAssertEqual(textView.textContainerInset.height, workspaceSidebarNoteEditorInset)
    }

    func testMarkdownBlendingUsesTextKitAttributesWithoutChangingSource() throws {
        let (_, textView) = WorkspaceSidebarNoteTextView.makeConfiguredTextViewForTesting()
        let source = "- Root\n  - Child\n---\n"
        textView.string = source
        textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))

        WorkspaceSidebarMarkdownBlending.apply(to: textView)

        let storage = try XCTUnwrap(textView.textStorage)
        XCTAssertEqual(textView.string, source)
        XCTAssertNotNil(storage.attribute(.glyphInfo, at: 0, effectiveRange: nil))
        let childStyle = try XCTUnwrap(storage.attribute(
            .paragraphStyle,
            at: (source as NSString).range(of: "- Child").location,
            effectiveRange: nil
        ) as? NSParagraphStyle)
        XCTAssertEqual(childStyle.textLists.count, 2)
        let dividerLocation = (source as NSString).range(of: "---").location
        XCTAssertNotNil(storage.attribute(
            workspaceSidebarMarkdownDividerAttribute,
            at: dividerLocation,
            effectiveRange: nil
        ))
        let dividerStyle = try XCTUnwrap(storage.attribute(
            .paragraphStyle,
            at: dividerLocation,
            effectiveRange: nil
        ) as? NSParagraphStyle)
        XCTAssertEqual(dividerStyle.textBlocks.count, 1)
    }

    func testTabAndShiftTabAdjustBulletNestingWithoutChangingNonBullets() {
        let (_, textView) = WorkspaceSidebarNoteTextView.makeConfiguredTextViewForTesting()
        textView.string = "- Root\nParagraph\n"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        XCTAssertTrue(WorkspaceSidebarMarkdownBlending.adjustBulletIndent(in: textView, direction: 1))
        XCTAssertEqual(textView.string, "  - Root\nParagraph\n")
        XCTAssertEqual(textView.selectedRange().location, 5)

        XCTAssertTrue(WorkspaceSidebarMarkdownBlending.adjustBulletIndent(in: textView, direction: -1))
        XCTAssertEqual(textView.string, "- Root\nParagraph\n")
        XCTAssertEqual(textView.selectedRange().location, 3)

        textView.setSelectedRange((textView.string as NSString).range(of: "Paragraph"))
        XCTAssertFalse(WorkspaceSidebarMarkdownBlending.adjustBulletIndent(in: textView, direction: 1))
        XCTAssertEqual(textView.string, "- Root\nParagraph\n")
    }
}

private struct Fixture {
    let directoryURL: URL
    let rootURL: URL
    let storageURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appending(component: "winmux-task-note-\(UUID().uuidString)", directoryHint: .isDirectory)
        rootURL = directoryURL.appending(component: "Tasks", directoryHint: .isDirectory)
        storageURL = directoryURL.appending(component: "selection.json", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    @discardableResult
    func makeDirectory(_ name: String) throws -> URL {
        let url = rootURL.appending(component: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func writeTask(
        folderURL: URL,
        filename: String,
        title: String,
        completed: Bool,
        order: Int,
        estimated: String = "2.0",
        actual: String = "0.5",
        body: String? = nil
    ) throws -> URL {
        let url = folderURL.appending(component: filename, directoryHint: .notDirectory)
        let contents = """
        ---
        title: "\(title)"
        completed: \(completed)
        display_order: \(order)
        estimated: \(estimated)
        actual: \(actual)
        ---

        \(body ?? "# \(title)")
        """
        try write(contents: contents, to: url)
        return url
    }

    func write(contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url, options: .atomic)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
