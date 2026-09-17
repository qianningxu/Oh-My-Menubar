@testable import AppBundle
import AppKit
import SwiftUI
import XCTest

@MainActor
final class WindowTabRenameTest: XCTestCase {
    private var text = "Original"
    private var commits = 0
    private var cancels = 0

    private func coordinator() -> WindowTabRenameTextField.Coordinator {
        WindowTabRenameTextField.Coordinator(
            text: Binding(get: { self.text }, set: { self.text = $0 }),
            onCommit: { self.commits += 1 },
            onCancel: { self.cancels += 1 }
        )
    }

    func testActivationDoesNotPrematurelySaveRename() {
        let editor = coordinator()
        let field = NSTextField(string: "Draft")
        editor.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        XCTAssertEqual(text, "Draft")
        XCTAssertEqual(commits, 0)
        XCTAssertFalse(editor.didFinish)
    }

    func testReturnSavesCurrentEditorTextExactlyOnce() {
        let editor = coordinator()
        let field = NSTextField(string: "Original")
        let textView = NSTextView()
        textView.string = "New name"
        XCTAssertTrue(editor.control(field, textView: textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        editor.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        XCTAssertEqual(text, "New name")
        XCTAssertEqual(commits, 1)
        XCTAssertEqual(cancels, 0)
    }

    func testEscapeDoesNotSaveOnSubsequentFocusLoss() {
        let editor = coordinator()
        let field = NSTextField(string: "Draft")
        XCTAssertTrue(editor.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        editor.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        XCTAssertEqual(text, "Original")
        XCTAssertEqual(commits, 0)
        XCTAssertEqual(cancels, 1)
    }

    func testFocusLossAfterAcquiringFocusSaves() {
        let editor = coordinator()
        editor.didFocus = true
        editor.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: NSTextField(string: "Saved")))
        XCTAssertEqual(text, "Saved")
        XCTAssertEqual(commits, 1)
    }

    func testDismantledEditorCannotRefocusOrSave() {
        let editor = coordinator()
        let field = NSTextField(string: "Draft")
        WindowTabRenameTextField.dismantleNSView(field, coordinator: editor)
        editor.focus(field)
        editor.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
        XCTAssertTrue(editor.didFinish)
        XCTAssertEqual(editor.focusAttempts, 0)
        XCTAssertEqual(commits, 0)
    }
}
