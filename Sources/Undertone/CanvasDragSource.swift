import AppKit
import SwiftUI

/// Drags the artwork out as a PNG. The pasteboard carries both a real file URL and the PNG data, so
/// Finder gets a properly named file, browsers (Canva and other web apps) get a file upload, and apps
/// that take images get the image. A click focuses the canvas, so Edit › Copy copies the artwork.
struct CanvasDragSource: NSViewRepresentable {
    let model: StudioModel

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.model = model
        return view
    }

    func updateNSView(_ view: DragSourceView, context: Context) { view.model = model }
}

final class DragSourceView: NSView, NSDraggingSource {
    weak var model: StudioModel?
    private var mouseDownEvent: NSEvent?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        window?.makeFirstResponder(self)
    }

    override func mouseUp(with event: NSEvent) { mouseDownEvent = nil }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let start = down.locationInWindow, now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) > 4 else { return }
        mouseDownEvent = nil
        beginDrag(with: down)
    }

    private func beginDrag(with event: NSEvent) {
        guard let model, let url = model.dragFile() else { return }
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if let data = try? Data(contentsOf: url) { item.setData(data, forType: .png) }
        let dragging = NSDraggingItem(pasteboardWriter: item)
        // A small copy of the artwork follows the pointer.
        let point = convert(event.locationInWindow, from: nil)
        let ratio = CGFloat(model.recipe.width) / CGFloat(max(model.recipe.height, 1))
        let size = ratio >= 1 ? NSSize(width: 180, height: 180 / ratio) : NSSize(width: 180 * ratio, height: 180)
        let thumbnail = model.preview ?? NSImage(contentsOf: url) ?? NSImage()
        dragging.setDraggingFrame(NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), contents: thumbnail)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    /// Edit › Copy while the canvas is focused.
    @objc func copy(_ sender: Any?) {
        model?.copyImage()
    }

    /// The canvas's right-click menu, built here because this view receives the canvas's mouse events.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let copy = item("Copy Image") { model.copyImage() }
        let export = item("Export Image…") { model.exportImage() }
        copy.isEnabled = !model.isRendering
        export.isEnabled = !model.isRendering
        let style = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        style.submenu = NSMenu()
        style.submenu?.items = GradientMode.allCases.map { mode in
            let choice = item(mode.title) { model.setMode(mode) }
            choice.state = model.recipe.mode == mode ? .on : .off
            return choice
        }
        menu.items = [copy, export, .separator(), item("Randomize") { model.randomize() }, style]
        return menu
    }

    private func item(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runMenuItem(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = handler
        return item
    }

    @objc private func runMenuItem(_ sender: NSMenuItem) {
        (sender.representedObject as? () -> Void)?()
    }
}
