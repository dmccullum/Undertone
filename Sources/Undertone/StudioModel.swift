import AppKit
import DMKit
import SwiftUI
import UniformTypeIdentifiers

@Observable final class StudioModel {
    private static let canvasWidthPreference = "canvasWidth"
    private static let canvasHeightPreference = "canvasHeight"
    private static let currentGradientPreference = "currentGradientID"
    static let maximumStops = 8
    /// Longest side of the preview image. On the GPU the canvas draws itself at full resolution
    /// (`MetalCanvas`), so this image only feeds the blurred backdrop; on the CPU it is the canvas.
    nonisolated private static var previewSize: Double { RenderEngine.usesGPU ? 256 : 1_280 }

    var recipe = GradientRecipe() {
        didSet { recipeDidChange(from: oldValue) }
    }
    private(set) var gradients: [SavedGradient] = []
    /// The gradient currently open on the canvas. Edits to `recipe` autosave into it only while it's
    /// an unsaved gradient; the first edit to a saved gradient opens an unsaved copy instead, so a
    /// saved gradient changes only through Update.
    private(set) var currentGradientID: UUID?
    var colorLibraries: [ColorLibrary] = [.coldwellBanker]
    private(set) var preview: NSImage?
    /// Changes only when the preview should crossfade.
    private(set) var previewIdentity = 0
    private(set) var styleThumbnails: [GradientMode: NSImage] = [:]
    private(set) var isRendering = false
    private(set) var toast: String?
    private(set) var renameRequest = 0
    /// While hovering the color tray, all points are revealed on the canvas.
    private(set) var pointsRevealed = false
    /// The specific tray chip being hovered, emphasized among the revealed points.
    var highlightedStopID: UUID?
    /// Mesh: the point library clicks paint, and the mesh point being hovered in the tray.
    private(set) var selectedMeshPoint = 0
    var highlightedMeshPoint: Int?
    /// The error alert: what failed (its title) and why.
    private(set) var errorTitle = ""
    var errorMessage: String?

    // Everything below is bookkeeping no view draws from, so it's left out of observation. The
    // thumbnail cache is written while views draw, and observing it would redraw them in a loop.
    @ObservationIgnored weak var undoManager: UndoManager?
    /// The studio window, which file panels attach to as sheets. ContentView sets it.
    @ObservationIgnored weak var window: NSWindow?
    /// Recipe edits undo against this target, so opening another gradient can drop them without
    /// also dropping library undo (colors, collections, names), which doesn't depend on the canvas.
    private let recipeUndoTarget = RecipeUndoTarget()
    private final class RecipeUndoTarget {}

    private let gradientsURL: URL
    private let legacyPalettesURL: URL
    private let colorLibrariesURL: URL
    private let legacyColorsURL: URL
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var undoBurstTask: Task<Void, Never>?
    @ObservationIgnored private var revealHideTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var renderInFlight = false
    @ObservationIgnored private var renderPending = false
    @ObservationIgnored private var displayedIsInteractive = false
    @ObservationIgnored private var isLoadingGradient = false
    @ObservationIgnored private var isApplyingUndo = false
    @ObservationIgnored private var undoBurstOpen = false
    @ObservationIgnored private var animateNextPreview = false
    @ObservationIgnored private var thumbnailCache: [UUID: (recipe: GradientRecipe, image: NSImage)] = [:]
    @ObservationIgnored private var dragFileCache: (recipe: GradientRecipe, url: URL)?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    init(directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Undertone", isDirectory: true)
        gradientsURL = directory.appendingPathComponent("gradients.json")
        legacyPalettesURL = directory.appendingPathComponent("palettes.json")
        colorLibrariesURL = directory.appendingPathComponent("color-libraries.json")
        legacyColorsURL = directory.appendingPathComponent("colors.json")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { fail("Couldn’t Open the Library Folder", error) }
        // Compile the shader and run the GPU self-test off the main thread before the canvas needs it.
        Task.detached(priority: .userInitiated) { _ = RenderEngine.usesGPU }
        loadColorLibraries()
        loadGradients()
        restoreCurrentGradient()
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    /// Opens the last-open gradient (or the first) on launch. The library always has at least one.
    private func restoreCurrentGradient() {
        let savedID = UserDefaults.standard.string(forKey: Self.currentGradientPreference).flatMap(UUID.init(uuidString:))
        let gradient = gradients.first { $0.id == savedID } ?? gradients.first
        guard let gradient else { return }
        currentGradientID = gradient.id
        load(gradient.recipe, animated: false)
    }

    // MARK: - Gradient library

    var currentGradient: SavedGradient? { gradients.first { $0.id == currentGradientID } }
    var isCurrentUnsaved: Bool { currentGradient?.isUnsaved ?? false }
    /// The saved gradient the open unsaved one was edited from, while it still exists.
    var currentSource: SavedGradient? {
        guard let sourceID = currentGradient?.sourceID else { return nil }
        return gradients.first { $0.id == sourceID && !$0.isUnsaved }
    }
    var currentName: String { currentGradient?.name ?? "Untitled" }
    private var currentIndex: Int? { gradients.firstIndex { $0.id == currentGradientID } }

    private static var defaultCanvasSize: (width: Int, height: Int) {
        let width = UserDefaults.standard.integer(forKey: canvasWidthPreference)
        let height = UserDefaults.standard.integer(forKey: canvasHeightPreference)
        if (128...8192).contains(width), (128...8192).contains(height) { return (width, height) }
        return (2160, 2880)
    }

    private func loadGradients() {
        do {
            if FileManager.default.fileExists(atPath: gradientsURL.path) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                gradients = try decoder.decode([SavedGradient].self, from: Data(contentsOf: gradientsURL))
            } else if FileManager.default.fileExists(atPath: legacyPalettesURL.path) {
                let palettes = try JSONDecoder().decode([BrandPalette].self, from: Data(contentsOf: legacyPalettesURL))
                gradients = palettes.map { SavedGradient(name: $0.name, hasCustomName: true, recipe: Self.laidOutRecipe($0.colors)) }
                try persistGradients()
                try? FileManager.default.moveItem(at: legacyPalettesURL, to: legacyPalettesURL.deletingLastPathComponent().appendingPathComponent("palettes-migrated.json"))
            } else {
                gradients = Self.starterGradients()
                try persistGradients()
            }
        } catch { fail("Couldn’t Load Your Gradients", error) }
        if gradients.isEmpty { gradients = Self.starterGradients() }
    }

    /// Spreads colors evenly around the canvas, the layout older palettes used.
    static func laidOutRecipe(_ colors: [String]) -> GradientRecipe {
        var recipe = GradientRecipe()
        let size = defaultCanvasSize
        recipe.width = size.width
        recipe.height = size.height
        recipe.stops = colors.enumerated().map { index, hex in
            let angle = Double(index) / Double(max(colors.count, 1)) * .pi * 2
            return ColorStop(hex: hex, x: 0.5 + cos(angle) * 0.35, y: 0.5 + sin(angle) * 0.35)
        }
        return recipe
    }

    private static func starterGradients() -> [SavedGradient] {
        var dusk = GradientRecipe()
        let size = defaultCanvasSize
        dusk.width = size.width
        dusk.height = size.height
        var tidal = laidOutRecipe(["164E63", "67B8AC", "E8DFC7"])
        tidal.mode = .linear
        tidal.colorArc = 0
        // A gentle diagonal (~115°) from top-right to bottom-left.
        tidal.startX = 0.711; tidal.startY = 0.047
        tidal.endX = 0.289; tidal.endY = 0.953
        var ember = laidOutRecipe(["842D43", "E57E55", "F4D8AB"])
        ember.mode = .aurora
        ember.angleDegrees = 70
        ember.seed = 7
        return [
            SavedGradient(name: "Dusk", hasCustomName: true, recipe: dusk),
            SavedGradient(name: "Tidal", hasCustomName: true, recipe: tidal),
            SavedGradient(name: "Ember", hasCustomName: true, recipe: ember)
        ]
    }

    private func persistGradients() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(gradients).write(to: gradientsURL, options: .atomic)
    }

    /// Writes the working recipe back into its library gradient. Called before switching, on idle
    /// autosave, and on quit. Edits fork a saved gradient into an unsaved one first, so this only
    /// ever writes into an unsaved gradient.
    private func commitRecipe() {
        guard let index = currentIndex, gradients[index].recipe != recipe else { return }
        gradients[index].recipe = recipe
        gradients[index].modified = Date()
    }

    func saveNow(confirm: Bool = false) {
        commitRecipe()
        do {
            try persistGradients()
            if confirm { flash("Saved") }
        } catch { fail("Couldn’t Save Your Gradients", error) }
    }

    /// Opens a gradient on the canvas, committing the current one first. An unsaved copy that was
    /// edited back to match its source is dropped on the way out.
    func selectGradient(id: UUID?) {
        guard let id, id != currentGradientID, let gradient = gradients.first(where: { $0.id == id }) else { return }
        commitRecipe()
        if let source = currentSource, source.recipe == recipe { gradients.removeAll { $0.id == currentGradientID } }
        currentGradientID = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.currentGradientPreference)
        load(gradient.recipe, animated: true)
        undoManager?.removeAllActions(withTarget: recipeUndoTarget)
    }

    private func load(_ recipe: GradientRecipe, animated: Bool) {
        isLoadingGradient = true
        animateNextPreview = animated
        if self.recipe == recipe { refreshPreview() } else { self.recipe = recipe }
        isLoadingGradient = false
    }

    /// Creates a new, empty unsaved gradient and opens it.
    @discardableResult func newGradient() -> UUID {
        commitRecipe()
        let before = librarySnapshot()
        var fresh = GradientRecipe()
        fresh.stops = []
        let size = Self.defaultCanvasSize
        fresh.width = size.width
        fresh.height = size.height
        fresh.seed = UInt64.random(in: 1...UInt64.max)
        let seed = Int.random(in: 0...9_999)
        let gradient = SavedGradient(name: NameGenerator.name(for: fresh, seed: seed), nameSeed: seed, recipe: fresh, isUnsaved: true)
        gradients.insert(gradient, at: 0)
        currentGradientID = gradient.id
        UserDefaults.standard.set(gradient.id.uuidString, forKey: Self.currentGradientPreference)
        load(fresh, animated: true)
        saveNow()
        undoManager?.removeAllActions(withTarget: recipeUndoTarget)
        registerGradientsUndo("New Gradient", restoring: before)
        return gradient.id
    }

    @discardableResult func duplicateGradient(id: UUID) -> UUID? {
        commitRecipe()
        guard let original = gradients.first(where: { $0.id == id }) else { return nil }
        let before = librarySnapshot()
        let copy = SavedGradient(name: numberedName(for: original.name), hasCustomName: true, nameSeed: original.nameSeed &+ 1, recipe: original.recipe)
        gradients.insert(copy, at: 0)
        saveNow()
        selectGradient(id: copy.id)
        registerGradientsUndo("Duplicate Gradient", restoring: before)
        flash("Duplicated \(original.name)")
        return copy.id
    }

    @discardableResult func duplicateCurrentGradient() -> UUID? {
        guard let id = currentGradientID else { return nil }
        return duplicateGradient(id: id)
    }

    // MARK: - Unsaved gradients

    /// The first edit to a saved gradient moves the work into a new unsaved copy and leaves the
    /// saved one as it was.
    private func forkUnsavedCopyIfNeeded() {
        guard let index = currentIndex, !gradients[index].isUnsaved, gradients[index].recipe != recipe else { return }
        let source = gradients[index]
        let copy = SavedGradient(name: source.name, hasCustomName: source.hasCustomName, nameSeed: source.nameSeed, recipe: recipe, isUnsaved: true, sourceID: source.id)
        gradients.insert(copy, at: 0)
        currentGradientID = copy.id
        UserDefaults.standard.set(copy.id.uuidString, forKey: Self.currentGradientPreference)
    }

    /// Saves the open unsaved gradient as a new saved gradient, leaving its source untouched.
    func saveAsNewGradient() {
        commitRecipe()
        guard let index = currentIndex, gradients[index].isUnsaved else { return }
        let before = librarySnapshot()
        var saved = gradients.remove(at: index)
        if saved.hasCustomName, gradients.contains(where: { !$0.isUnsaved && $0.name == saved.name }) {
            saved.name = numberedName(for: saved.name)
        }
        saved.isUnsaved = false
        saved.sourceID = nil
        saved.modified = Date()
        gradients.insert(saved, at: gradients.firstIndex { !$0.isUnsaved } ?? gradients.endIndex)
        saveNow()
        registerGradientsUndo("Save Gradient", restoring: before)
        flash("Saved \(saved.name)")
    }

    /// Writes the open unsaved gradient over the saved gradient it came from and opens that one.
    func updateSavedGradient() {
        commitRecipe()
        guard let index = currentIndex, let source = currentSource,
              let sourceIndex = gradients.firstIndex(where: { $0.id == source.id }) else { return }
        let before = librarySnapshot()
        let edited = gradients[index]
        gradients[sourceIndex].recipe = edited.recipe
        gradients[sourceIndex].name = edited.name
        gradients[sourceIndex].hasCustomName = edited.hasCustomName
        gradients[sourceIndex].nameSeed = edited.nameSeed
        gradients[sourceIndex].modified = Date()
        gradients.remove(at: index)
        currentGradientID = source.id
        UserDefaults.standard.set(source.id.uuidString, forKey: Self.currentGradientPreference)
        saveNow()
        registerGradientsUndo("Update Gradient", restoring: before)
        flash("Updated \(edited.name)")
    }

    /// Throws away the open unsaved gradient's edits and reopens the saved gradient it came from.
    func revertToSaved() {
        commitRecipe()
        guard let index = currentIndex, let source = currentSource else { return }
        let before = librarySnapshot()
        gradients.remove(at: index)
        currentGradientID = source.id
        UserDefaults.standard.set(source.id.uuidString, forKey: Self.currentGradientPreference)
        load(source.recipe, animated: true)
        saveNow()
        undoManager?.removeAllActions(withTarget: recipeUndoTarget)
        registerGradientsUndo("Revert to Saved", restoring: before)
    }

    private struct LibrarySnapshot { var gradients: [SavedGradient]; var currentID: UUID? }

    private func librarySnapshot() -> LibrarySnapshot { LibrarySnapshot(gradients: gradients, currentID: currentGradientID) }

    /// New, Duplicate, Import, Save, Update and Revert undo by restoring the whole gradient list and the open gradient.
    private func registerGradientsUndo(_ actionName: String, restoring previous: LibrarySnapshot) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            model.commitRecipe()
            let current = model.librarySnapshot()
            model.gradients = previous.gradients
            model.currentGradientID = previous.currentID
            UserDefaults.standard.set(previous.currentID?.uuidString, forKey: Self.currentGradientPreference)
            if let gradient = model.currentGradient { model.load(gradient.recipe, animated: true) }
            model.saveNow()
            model.registerGradientsUndo(actionName, restoring: current)
        }
        undoManager.setActionName(actionName)
    }

    /// Reorders the Saved section of the library. Offsets count saved gradients only, as the list
    /// shows them; unsaved gradients keep their places.
    func moveSavedGradients(fromOffsets source: IndexSet, toOffset destination: Int) {
        var saved = gradients.filter { !$0.isUnsaved }
        saved.move(fromOffsets: source, toOffset: destination)
        let before = librarySnapshot()
        var next = saved.makeIterator()
        gradients = gradients.map { $0.isUnsaved ? $0 : next.next()! }
        guard gradients.map(\.id) != before.gradients.map(\.id) else { return }
        saveNow()
        registerGradientsUndo("Move Gradient", restoring: before)
    }

    /// "Dusk" becomes "Dusk 2", and "Dusk 2" becomes "Dusk 3", skipping names already in use.
    private func numberedName(for name: String) -> String {
        var base = name
        if let range = name.range(of: " [0-9]+$", options: .regularExpression) { base = String(name[..<range.lowerBound]) }
        let existing = Set(gradients.map(\.name))
        var number = 2
        while existing.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    func deleteGradient(id: UUID) {
        guard let index = gradients.firstIndex(where: { $0.id == id }) else { return }
        let wasCurrent = id == currentGradientID
        let removed = gradients[index]
        gradients.remove(at: index)
        thumbnailCache[id] = nil
        if gradients.isEmpty {
            // The library always holds at least one gradient.
            var blank = GradientRecipe()
            blank.stops = []
            let size = Self.defaultCanvasSize
            blank.width = size.width
            blank.height = size.height
            let seed = Int.random(in: 0...9_999)
            gradients = [SavedGradient(name: NameGenerator.name(for: blank, seed: seed), nameSeed: seed, recipe: blank)]
        }
        if wasCurrent {
            let next = gradients[min(index, gradients.count - 1)]
            currentGradientID = next.id
            UserDefaults.standard.set(next.id.uuidString, forKey: Self.currentGradientPreference)
            load(next.recipe, animated: true)
        }
        saveNow()
        undoManager?.registerUndo(withTarget: self) { model in
            model.restoreDeletedGradient(removed, at: index)
        }
        undoManager?.setActionName(removed.isUnsaved ? "Discard Gradient" : "Delete Gradient")
        flash(removed.isUnsaved ? "Discarded \(removed.name)" : "Deleted \(removed.name)")
    }

    private func restoreDeletedGradient(_ gradient: SavedGradient, at index: Int) {
        commitRecipe()
        gradients.insert(gradient, at: min(index, gradients.count))
        currentGradientID = gradient.id
        UserDefaults.standard.set(gradient.id.uuidString, forKey: Self.currentGradientPreference)
        load(gradient.recipe, animated: true)
        saveNow()
        // Redo deletes it again, which registers the next undo.
        undoManager?.registerUndo(withTarget: self) { model in
            model.deleteGradient(id: gradient.id)
        }
        undoManager?.setActionName(gradient.isUnsaved ? "Discard Gradient" : "Delete Gradient")
    }

    /// Renames a gradient (the current one by default). An empty name hands naming back to the generator.
    func renameGradient(id: UUID? = nil, to name: String) {
        guard let id = id ?? currentGradientID, let index = gradients.firstIndex(where: { $0.id == id }) else { return }
        let previous = naming(at: index)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            gradients[index].hasCustomName = false
            let source = id == currentGradientID ? recipe : gradients[index].recipe
            gradients[index].name = NameGenerator.name(for: source, seed: gradients[index].nameSeed)
        } else {
            gradients[index].name = String(trimmed.prefix(60))
            gradients[index].hasCustomName = true
        }
        saveNow()
        registerRenameUndo(id: id, restoring: previous)
    }

    func renameCurrentGradient(_ name: String) { renameGradient(to: name) }

    /// Puts the cursor in the rename field for the current gradient.
    func beginRenaming() { renameRequest += 1 }

    /// Lets the current gradient's name follow the colors again.
    func useAutomaticName() { renameCurrentGradient("") }

    /// Rolls an automatic name from the current colors for the rename sheet's shuffle. Changes nothing.
    func automaticNameSuggestion() -> (name: String, seed: Int) {
        let seed = Int.random(in: 0...9_999)
        return (NameGenerator.name(for: recipe, seed: seed), seed)
    }

    /// Gives the current gradient the automatic name for `seed`; the name then follows the colors.
    func useAutomaticName(seed: Int) {
        guard let index = currentIndex else { return }
        let previous = naming(at: index)
        gradients[index].hasCustomName = false
        gradients[index].nameSeed = seed
        gradients[index].name = NameGenerator.name(for: recipe, seed: seed)
        saveNow()
        registerRenameUndo(id: gradients[index].id, restoring: previous)
    }

    /// Everything a rename touches: undoing one also restores whether the name follows the colors.
    private struct Naming: Equatable { var name: String; var hasCustomName: Bool; var nameSeed: Int }

    private func naming(at index: Int) -> Naming {
        Naming(name: gradients[index].name, hasCustomName: gradients[index].hasCustomName, nameSeed: gradients[index].nameSeed)
    }

    private func registerRenameUndo(id: UUID, restoring previous: Naming) {
        guard let undoManager, let index = gradients.firstIndex(where: { $0.id == id }), naming(at: index) != previous else { return }
        undoManager.registerUndo(withTarget: self) { model in
            model.restoreNaming(previous, of: id)
        }
        undoManager.setActionName("Rename Gradient")
    }

    private func restoreNaming(_ naming: Naming, of id: UUID) {
        guard let index = gradients.firstIndex(where: { $0.id == id }) else { return }
        let current = self.naming(at: index)
        gradients[index].name = naming.name
        gradients[index].hasCustomName = naming.hasCustomName
        gradients[index].nameSeed = naming.nameSeed
        // An automatic name follows the colors, which may have changed since.
        if !naming.hasCustomName {
            let source = id == currentGradientID ? recipe : gradients[index].recipe
            gradients[index].name = NameGenerator.name(for: source, seed: naming.nameSeed)
        }
        saveNow()
        registerRenameUndo(id: id, restoring: current)
    }

    func thumbnail(for gradient: SavedGradient) -> NSImage? {
        if let cached = thumbnailCache[gradient.id], cached.recipe == gradient.recipe { return cached.image }
        var small = gradient.recipe
        small.grain = 0
        let scale = 120.0 / Double(max(1, max(small.width, small.height)))
        let width = max(1, Int(Double(small.width) * scale)), height = max(1, Int(Double(small.height) * scale))
        guard let image = try? RenderEngine.render(small, width: width, height: height) else { return nil }
        let result = NSImage(cgImage: image, size: NSSize(width: width, height: height))
        thumbnailCache[gradient.id] = (gradient.recipe, result)
        return result
    }

    // MARK: - Editing, undo and autosave

    private func recipeDidChange(from old: GradientRecipe) {
        guard recipe != old else { return }
        if !isLoadingGradient {
            forkUnsavedCopyIfNeeded()
            if !isApplyingUndo { registerUndo(returningTo: old) }
            if old.stops.map(\.hex) != recipe.stops.map(\.hex) || old.mode != recipe.mode {
                refreshAutomaticName()
            }
        }
        refreshPreview()
    }

    /// One undo step per burst of edits, so a slider drag undoes in one go.
    private func registerUndo(returningTo old: GradientRecipe) {
        guard let undoManager else { return }
        if !undoBurstOpen {
            undoBurstOpen = true
            undoManager.registerUndo(withTarget: recipeUndoTarget) { [weak self] _ in
                self?.restore(old)
            }
            undoManager.setActionName("Gradient Change")
        }
        undoBurstTask?.cancel()
        undoBurstTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.undoBurstOpen = false
        }
    }

    private func restore(_ target: GradientRecipe) {
        let current = recipe
        undoManager?.registerUndo(withTarget: recipeUndoTarget) { [weak self] _ in
            self?.restore(current)
        }
        undoBurstOpen = false
        isApplyingUndo = true
        animateNextPreview = true
        recipe = target
        isApplyingUndo = false
    }

    // MARK: - Names

    /// The current gradient's name follows its colors automatically until the user sets a custom name.
    private func refreshAutomaticName() {
        guard let index = currentIndex, !gradients[index].hasCustomName else { return }
        gradients[index].name = NameGenerator.name(for: recipe, seed: gradients[index].nameSeed)
    }

    func libraryName(for hex: String) -> String? {
        for library in colorLibraries {
            if let match = library.colors.first(where: { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }) {
                let trimmed = match.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        return nil
    }

    // MARK: - Color collections

    private static let seededDefaultsPreference = "seededDefaultCollections"

    private func loadColorLibraries() {
        do {
            if FileManager.default.fileExists(atPath: colorLibrariesURL.path) {
                colorLibraries = try JSONDecoder().decode([ColorLibrary].self, from: Data(contentsOf: colorLibrariesURL))
            } else if FileManager.default.fileExists(atPath: legacyColorsURL.path) {
                let colors = try JSONDecoder().decode([LibraryColor].self, from: Data(contentsOf: legacyColorsURL))
                if !colors.isEmpty { colorLibraries = [.init(name: "My Colors", colors: colors)] }
            }
        } catch { fail("Couldn’t Load Your Collections", error) }
        seedDefaultCollectionsIfNeeded()
    }

    /// Coldwell Banker ships as the demo collection, added once. It's an ordinary, editable
    /// collection from then on, so deleting it sticks and edits persist.
    private func seedDefaultCollectionsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.seededDefaultsPreference) else { return }
        if !colorLibraries.contains(where: { $0.id == ColorLibrary.coldwellBankerID }) {
            colorLibraries.insert(.coldwellBanker, at: 0)
        }
        UserDefaults.standard.set(true, forKey: Self.seededDefaultsPreference)
        try? persistColorLibraries()
    }

    private func persistColorLibraries() throws {
        try JSONEncoder().encode(colorLibraries).write(to: colorLibrariesURL, options: .atomic)
    }

    private func saveColorLibraries() {
        do { try persistColorLibraries() } catch { fail("Couldn’t Save Your Collections", error) }
    }

    /// Color and collection edits undo by restoring the whole set of collections: it's small, and a
    /// snapshot puts a deleted color or collection back exactly where it was.
    private func registerLibraryUndo(_ actionName: String, restoring previous: [ColorLibrary]) {
        guard let undoManager, previous != colorLibraries else { return }
        undoManager.registerUndo(withTarget: self) { model in
            let current = model.colorLibraries
            model.colorLibraries = previous
            model.saveColorLibraries()
            model.registerLibraryUndo(actionName, restoring: current)
        }
        undoManager.setActionName(actionName)
    }

    @discardableResult func createColorLibrary(name: String, colors: [LibraryColor] = []) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let previous = colorLibraries
        let library = ColorLibrary(name: name, colors: colors)
        colorLibraries.append(library)
        do {
            try persistColorLibraries()
            registerLibraryUndo("New Collection", restoring: previous)
            flash("Created \(name)")
            return library.id
        } catch {
            colorLibraries.removeAll { $0.id == library.id }
            fail("Couldn’t Create the Collection", error)
            return nil
        }
    }

    /// Saves the gradient's colors as a collection, named after the gradient.
    @discardableResult func createColorLibraryFromCurrentColors() -> UUID? {
        guard !recipe.stops.isEmpty else { return nil }
        var seen: Set<String> = []
        let colors = recipe.stops.compactMap { stop -> LibraryColor? in
            guard seen.insert(stop.hex.uppercased()).inserted else { return nil }
            return LibraryColor(name: libraryName(for: stop.hex) ?? ColorNamer.name(stop.hex), hex: stop.hex.uppercased())
        }
        return createColorLibrary(name: currentName, colors: colors)
    }

    @discardableResult func renameColorLibrary(id: UUID, to name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = colorLibraries.firstIndex(where: { $0.id == id }) else { return false }
        let previous = colorLibraries
        colorLibraries[index].name = name
        saveColorLibraries()
        registerLibraryUndo("Rename Collection", restoring: previous)
        return true
    }

    func deleteColorLibrary(id: UUID) {
        guard let library = colorLibraries.first(where: { $0.id == id }) else { return }
        let previous = colorLibraries
        colorLibraries.removeAll { $0.id == id }
        saveColorLibraries()
        registerLibraryUndo("Delete Collection", restoring: previous)
        flash("Deleted \(library.name)")
    }

    func deleteLibraryColor(_ colorID: UUID, from libraryID: UUID) {
        guard let index = colorLibraries.firstIndex(where: { $0.id == libraryID }) else { return }
        let previous = colorLibraries
        colorLibraries[index].colors.removeAll { $0.id == colorID }
        saveColorLibraries()
        registerLibraryUndo("Delete Color", restoring: previous)
    }

    /// Moves colors before another color, or to the end, of a collection, which may be a different
    /// one from where they started.
    func moveLibraryColors(_ colorIDs: [UUID], to libraryID: UUID, before beforeID: UUID?) {
        guard let target = colorLibraries.firstIndex(where: { $0.id == libraryID }) else { return }
        let previous = colorLibraries
        var moving: [LibraryColor] = []
        for id in colorIDs {
            guard let library = colorLibraries.firstIndex(where: { $0.colors.contains { $0.id == id } }),
                  let index = colorLibraries[library].colors.firstIndex(where: { $0.id == id }) else { continue }
            moving.append(colorLibraries[library].colors.remove(at: index))
        }
        guard !moving.isEmpty else { return }
        let colors = colorLibraries[target].colors
        let insertion = beforeID.flatMap { id in colors.firstIndex { $0.id == id } } ?? colors.endIndex
        colorLibraries[target].colors.insert(contentsOf: moving, at: insertion)
        guard colorLibraries != previous else { return }
        saveColorLibraries()
        registerLibraryUndo("Move Color", restoring: previous)
    }

    @discardableResult func updateLibraryColor(_ colorID: UUID, in libraryID: UUID, name: String, hex: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hex = Hex.normalized(hex),
              let libraryIndex = colorLibraries.firstIndex(where: { $0.id == libraryID }),
              let colorIndex = colorLibraries[libraryIndex].colors.firstIndex(where: { $0.id == colorID }) else { return false }
        let previous = colorLibraries
        let onlyRenamed = previous[libraryIndex].colors[colorIndex].hex == hex
        colorLibraries[libraryIndex].colors[colorIndex].name = name
        colorLibraries[libraryIndex].colors[colorIndex].hex = hex
        saveColorLibraries()
        registerLibraryUndo(onlyRenamed ? "Rename Color" : "Edit Color", restoring: previous)
        return true
    }

    @discardableResult func saveColor(name: String, hex: String, libraryID: UUID? = nil) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hex = Hex.normalized(hex) else { return nil }
        let previous = colorLibraries
        var target = colorLibraries.firstIndex { $0.id == libraryID }
        if target == nil {
            target = colorLibraries.firstIndex { $0.name == "My Colors" }
        }
        if target == nil {
            colorLibraries.append(.init(name: "My Colors", colors: []))
            target = colorLibraries.indices.last
        }
        guard let target else { return nil }
        let color = LibraryColor(name: name, hex: hex)
        colorLibraries[target].colors.append(color)
        do {
            try persistColorLibraries()
            registerLibraryUndo("Add Color", restoring: previous)
            flash("Saved \(color.displayName) to \(colorLibraries[target].name)")
            return colorLibraries[target].id
        } catch {
            colorLibraries = previous
            fail("Couldn’t Add the Color", error)
            return nil
        }
    }

    func encodedColorLibrary(id: UUID) throws -> Data {
        guard let library = colorLibraries.first(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        let exported = ColorLibrary(id: library.id, name: library.name, colors: library.colors)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(exported)
    }

    @discardableResult func importColorLibrary(data: Data) throws -> UUID {
        let decoder = JSONDecoder()
        let decoded: ColorLibrary
        if let library = try? decoder.decode(ColorLibrary.self, from: data) {
            decoded = library
        } else if let colors = try? decoder.decode([LibraryColor].self, from: data) {
            decoded = .init(name: "Imported Colors", colors: colors)
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let name = decoded.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, decoded.colors.allSatisfy({ Hex.normalized($0.hex) != nil })
        else { throw CocoaError(.fileReadCorruptFile) }
        let imported = ColorLibrary(name: name, colors: decoded.colors.map {
            LibraryColor(name: $0.name, hex: $0.hex.uppercased())
        })
        let previous = colorLibraries
        colorLibraries.append(imported)
        do { try persistColorLibraries() }
        catch { colorLibraries = previous; throw error }
        registerLibraryUndo("Import Collection", restoring: previous)
        flash("Imported \(imported.name)")
        return imported.id
    }

    func importColorLibraryFromPanel() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        Task {
            guard await panel.present(in: window) == .OK, let url = panel.url else { return }
            do { try importColorLibrary(data: Data(contentsOf: url)) }
            catch { fail("Couldn’t Import Collection", error) }
        }
    }

    func exportColorLibrary(id: UUID) {
        guard let library = colorLibraries.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = Self.fileSafe(library.name) + ".undertone-colors.json"
        Task {
            guard await panel.present(in: window) == .OK, let url = panel.url else { return }
            do { try encodedColorLibrary(id: id).write(to: url, options: .atomic); flash("Exported \(library.name)") }
            catch { fail("Couldn’t Export Collection", error) }
        }
    }

    // MARK: - Color stops

    /// How many times a color appears in the gradient. Tonal counts only its base color; Mesh counts points.
    func count(of hex: String) -> Int {
        if recipe.mode == .mesh { return meshVertices.filter { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }.count }
        let stops = recipe.mode == .tonal ? Array(recipe.stops.prefix(1)) : recipe.stops
        return stops.filter { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }.count
    }

    func containsColor(hex: String) -> Bool { count(of: hex) > 0 }

    var canAddStop: Bool { recipe.mode == .tonal ? recipe.stops.isEmpty : recipe.stops.count < Self.maximumStops }

    /// Whether a library click does something: Tonal swaps its base, Mesh paints a point.
    var canUseLibraryColor: Bool { recipe.mode == .tonal || recipe.mode == .mesh || recipe.stops.count < Self.maximumStops }

    /// Library clicks always add; the same color can appear more than once.
    func addLibraryColor(_ color: LibraryColor) {
        if recipe.mode == .mesh {
            paintSelectedMeshPoint(color.hex)
            return
        }
        if recipe.mode == .tonal {
            setBaseColor(hex: color.hex)
            return
        }
        guard recipe.stops.count < Self.maximumStops else {
            flash("A gradient can use up to eight colors")
            return
        }
        let positions: [(Double, Double)] = [(0.18, 0.18), (0.82, 0.20), (0.22, 0.80), (0.78, 0.82), (0.50, 0.15), (0.50, 0.85), (0.15, 0.50), (0.85, 0.50)]
        let position = positions[recipe.stops.count]
        recipe.stops.append(.init(hex: color.hex, x: position.0, y: position.1))
    }

    func setBaseColor(hex: String) {
        if recipe.stops.isEmpty { recipe.stops = [.init(hex: hex, x: 0.5, y: 0.5)] }
        else { recipe.stops[0].hex = hex }
    }

    func addColor(hex: String) {
        if recipe.mode == .tonal { setBaseColor(hex: hex) }
        else if recipe.stops.count < Self.maximumStops {
            recipe.stops.append(.init(hex: hex, x: Double.random(in: 0.1...0.9), y: Double.random(in: 0.1...0.9)))
        }
    }

    func duplicateColor(id: UUID) {
        guard recipe.mode != .tonal, recipe.stops.count < Self.maximumStops,
              let index = recipe.stops.firstIndex(where: { $0.id == id }) else { return }
        let source = recipe.stops[index]
        let copy = ColorStop(hex: source.hex, x: min(max(source.x + 0.08, 0), 1), y: min(max(source.y + 0.06, 0), 1))
        recipe.stops.insert(copy, at: index + 1)
    }

    func setColor(hex: String, for id: UUID) {
        guard let hex = Hex.normalized(hex), let index = recipe.stops.firstIndex(where: { $0.id == id }) else { return }
        recipe.stops[index].hex = hex
    }

    /// How strongly a color point pulls in Organic.
    func setWeight(_ weight: Double, for id: UUID) {
        guard let index = recipe.stops.firstIndex(where: { $0.id == id }) else { return }
        recipe.stops[index].weight = min(4, max(0.1, weight))
    }

    /// Whether the current style uses per-point strength (i.e. blends positioned points spatially).
    var usesPointStrength: Bool { recipe.mode == .organic }

    // MARK: - Mesh grid

    var meshVertices: [MeshVertex] { MeshGrid.vertices(for: recipe) }
    var meshSize: Int { MeshGrid.clampedSize(recipe.meshSize) }

    /// The color a mesh point shows, or "" while it's unpainted.
    func meshColor(at index: Int) -> String {
        let vertices = meshVertices
        return vertices.indices.contains(index) ? vertices[index].hex : ""
    }

    /// Selects a mesh point: library clicks paint it, and the canvas and tray ring it.
    func selectMeshPoint(_ index: Int) {
        guard (0..<meshSize * meshSize).contains(index) else { return }
        selectedMeshPoint = index
    }

    /// Switches between a 3 × 3 and 4 × 4 grid, keeping the current bends and colors.
    func setMeshSize(_ size: Int) {
        let size = MeshGrid.clampedSize(size)
        guard size != meshSize else { return }
        var updated = recipe
        updated.meshVertices = MeshGrid.resampled(meshVertices, from: meshSize, to: size)
        updated.meshSize = size
        selectedMeshPoint = min(selectedMeshPoint, size * size - 1)
        recipe = updated
    }

    /// Moves a mesh point. Corners stay put and edge points slide along their edge.
    func moveMeshVertex(_ index: Int, x: Double, y: Double) {
        var vertices = meshVertices
        guard vertices.indices.contains(index) else { return }
        let position = MeshGrid.constrained(index, x: x, y: y, in: vertices, size: meshSize)
        vertices[index].x = position.x
        vertices[index].y = position.y
        recipe.meshVertices = vertices
    }

    /// Paints one mesh point.
    func setMeshColor(_ hex: String, at index: Int) {
        guard let hex = Hex.normalized(hex) else { return }
        var vertices = meshVertices
        guard vertices.indices.contains(index), vertices[index].hex != hex else { return }
        vertices[index].hex = hex
        var updated = recipe
        updated.meshVertices = vertices
        updated.stops = Self.stops(following: vertices, keeping: recipe.stops)
        recipe = updated
    }

    /// A library click in Mesh: paints the selected point, then moves to the next one in reading order,
    /// so clicking colors fills the grid.
    func paintSelectedMeshPoint(_ hex: String) {
        setMeshColor(hex, at: selectedMeshPoint)
        selectedMeshPoint = (selectedMeshPoint + 1) % (meshSize * meshSize)
    }

    /// The gradient's colors while it's a mesh: every distinct point color (up to eight) in reading
    /// order. Colors already in the gradient keep their identity and Organic positions, so switching
    /// styles carries the mesh's palette across.
    private static func stops(following vertices: [MeshVertex], keeping current: [ColorStop]) -> [ColorStop] {
        var seen: Set<String> = []
        let colors = vertices.map(\.hex).filter { !$0.isEmpty && seen.insert($0.uppercased()).inserted }.prefix(maximumStops)
        let spots: [(Double, Double)] = [(0.18, 0.18), (0.82, 0.20), (0.22, 0.80), (0.78, 0.82), (0.50, 0.15), (0.50, 0.85), (0.15, 0.50), (0.85, 0.50)]
        return colors.enumerated().map { index, hex in
            current.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
                ?? ColorStop(hex: hex, x: spots[index % spots.count].0, y: spots[index % spots.count].1)
        }
    }

    /// Deals the point colors across the grid in a new arrangement.
    func shuffleMeshColors() {
        var vertices = meshVertices
        let current = vertices.map(\.hex)
        guard Set(current).count > 1 else { return }
        var shuffled = current
        repeat { shuffled.shuffle() } while shuffled == current
        for index in vertices.indices { vertices[index].hex = shuffled[index] }
        recipe.meshVertices = vertices
    }

    /// Puts every mesh point back on an even grid, keeping the colors they show.
    func straightenMesh() {
        recipe.meshVertices = Self.straightened(recipe)
    }

    private static func straightened(_ recipe: GradientRecipe) -> [MeshVertex] {
        let size = MeshGrid.clampedSize(recipe.meshSize)
        return zip(MeshGrid.regular(size: size), MeshGrid.vertices(for: recipe)).map { even, vertex in
            MeshVertex(x: even.x, y: even.y, hex: vertex.hex)
        }
    }

    /// Reveals all canvas points while the tray is hovered, with a short grace period on exit so the
    /// points don't flicker when the pointer moves up to the canvas to grab one.
    func setTrayHovering(_ hovering: Bool) {
        revealHideTask?.cancel()
        if hovering {
            pointsRevealed = true
        } else {
            revealHideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                self?.pointsRevealed = false
                self?.highlightedStopID = nil
            }
        }
    }

    func removeColor(id: UUID) { recipe.stops.removeAll { $0.id == id } }

    func removeAllColors() { recipe.stops.removeAll() }

    /// Moves a color to a new slot; order drives Linear, Glow and Aurora.
    func moveColor(id: UUID, toIndex target: Int) {
        guard let from = recipe.stops.firstIndex(where: { $0.id == id }), recipe.stops.indices.contains(target), from != target else { return }
        var stops = recipe.stops
        let moving = stops.remove(at: from)
        stops.insert(moving, at: target)
        recipe.stops = stops
    }

    func suggestedColors() -> [String] {
        guard let color = recipe.stops.first?.nsColor.usingColorSpace(.sRGB) else {
            return ["F3AC91", "7655A3", "67B8AC", "E57E55"]
        }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return [-0.055, -0.025, 0.025, 0.055].enumerated().map { index, offset in
            let tone = NSColor(hue: (h + offset + 1).truncatingRemainder(dividingBy: 1), saturation: min(1, s * (index % 2 == 0 ? 0.72 : 0.92)), brightness: min(1, b * (index < 2 ? 1.13 : 0.86)), alpha: 1).usingColorSpace(.sRGB)!
            return String(format: "%02X%02X%02X", Int(tone.redComponent * 255), Int(tone.greenComponent * 255), Int(tone.blueComponent * 255))
        }
    }

    // MARK: - Style and canvas

    func setMode(_ mode: GradientMode) {
        guard mode != recipe.mode else { return }
        animateNextPreview = true
        var updated = recipe
        updated.mode = mode
        // Linear reads best as a smooth blend with no color arc; both stay adjustable from there.
        if mode == .linear {
            updated.colorArc = 0
            updated.smoothBlend = true
        }
        recipe = updated
    }

    /// Resets the current style's shape settings to defaults, keeping colors, canvas size and texture.
    func resetStyle() {
        let defaults = GradientRecipe()
        var updated = recipe
        updated.flow = defaults.flow
        updated.softness = defaults.softness
        updated.swirl = defaults.swirl
        updated.angleDegrees = defaults.angleDegrees
        updated.gradientPosition = defaults.gradientPosition
        updated.fadeWidth = defaults.fadeWidth
        updated.startX = defaults.startX; updated.startY = defaults.startY
        updated.endX = defaults.endX; updated.endY = defaults.endY
        updated.smoothBlend = updated.mode == .linear ? true : defaults.smoothBlend
        updated.easing = defaults.easing
        updated.colorArc = updated.mode == .linear ? 0 : defaults.colorArc
        updated.centerX = defaults.centerX; updated.centerY = defaults.centerY
        updated.meshVertices = Self.straightened(updated)
        updated.seed = defaults.seed
        animateNextPreview = true
        recipe = updated
    }

    /// Resets the grain texture to defaults and turns it back on.
    func resetTexture() {
        let defaults = GradientRecipe()
        var updated = recipe
        updated.textureEnabled = true
        updated.grain = defaults.grain
        updated.grainSize = defaults.grainSize
        recipe = updated
    }

    /// Reshapes the Organic blend's flow field without moving any color, by re-rolling the seed.
    func shuffleMesh() {
        recipe.seed = UInt64.random(in: 1...UInt64.max)
    }

    /// The Linear line's current angle in degrees (0–360), derived from its endpoints.
    var linearAngle: Double {
        let degrees = atan2(recipe.endY - recipe.startY, recipe.endX - recipe.startX) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Rotates the Linear line to a preset angle, keeping its center and length.
    func setLinearAngle(_ degrees: Double) {
        let radians = degrees * .pi / 180
        let axisX = cos(radians), axisY = sin(radians)
        let midX = (recipe.startX + recipe.endX) / 2, midY = (recipe.startY + recipe.endY) / 2
        let dx = recipe.endX - recipe.startX, dy = recipe.endY - recipe.startY
        let half = max(0.08, sqrt(dx * dx + dy * dy) / 2)
        func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
        var updated = recipe
        updated.startX = clamp01(midX - axisX * half)
        updated.startY = clamp01(midY - axisY * half)
        updated.endX = clamp01(midX + axisX * half)
        updated.endY = clamp01(midY + axisY * half)
        recipe = updated
    }

    func setCanvasSize(width: Int, height: Int) {
        guard (128...8192).contains(width), (128...8192).contains(height), width * height <= 33_554_432 else { return }
        UserDefaults.standard.set(width, forKey: Self.canvasWidthPreference)
        UserDefaults.standard.set(height, forKey: Self.canvasHeightPreference)
        animateNextPreview = true
        recipe.width = width
        recipe.height = height
    }

    func randomize() {
        animateNextPreview = true
        recipe = Self.randomized(recipe)
    }

    static func randomized(_ source: GradientRecipe) -> GradientRecipe {
        var recipe = source
        recipe.seed = UInt64.random(in: 1...UInt64.max)
        switch recipe.mode {
        case .organic:
            for index in recipe.stops.indices {
                recipe.stops[index].x = Double.random(in: 0.05...0.95)
                recipe.stops[index].y = Double.random(in: 0.05...0.95)
            }
            recipe.swirl = Bool.random() ? Double.random(in: 0.2...0.8) : 0
        case .mesh:
            // Bend the grid: nudge every point within its cell, keeping its color.
            let size = MeshGrid.clampedSize(recipe.meshSize)
            let cell = 1 / Double(size - 1)
            var vertices = straightened(recipe)
            for index in vertices.indices {
                let position = MeshGrid.constrained(
                    index,
                    x: vertices[index].x + Double.random(in: -0.42...0.42) * cell,
                    y: vertices[index].y + Double.random(in: -0.42...0.42) * cell,
                    in: vertices, size: size
                )
                vertices[index].x = position.x
                vertices[index].y = position.y
            }
            recipe.meshVertices = vertices
        case .tonal:
            recipe.flow = Double.random(in: 0.25...0.95)
            recipe.softness = Double.random(in: 0.2...0.9)
            recipe.colorArc = Double.random(in: 0.2...0.95)
            recipe.swirl = Bool.random() ? Double.random(in: 0.2...0.8) : 0
        case .linear:
            let radians = Double.random(in: 0...360) * .pi / 180
            let axisX = cos(radians), axisY = sin(radians)
            let half = Double.random(in: 0.35...0.6)
            let midX = Double.random(in: 0.4...0.6), midY = Double.random(in: 0.4...0.6)
            func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
            recipe.startX = clamp01(midX - axisX * half)
            recipe.startY = clamp01(midY - axisY * half)
            recipe.endX = clamp01(midX + axisX * half)
            recipe.endY = clamp01(midY + axisY * half)
        case .aurora:
            recipe.angleDegrees = Double.random(in: 0...360)
            recipe.gradientPosition = Double.random(in: 0.35...0.65)
        case .radial:
            recipe.centerX = Double.random(in: -0.25...1.25)
            recipe.centerY = Double.random(in: -0.25...1.25)
        }
        return recipe
    }

    // MARK: - Rendering

    /// Renders are serial: while one runs, newer edits wait and the latest one renders next,
    /// so a drag keeps updating instead of discarding every frame. Every edit renders the small,
    /// fast preview first for instant feedback; the full-size version sharpens in once edits settle.
    func refreshPreview() {
        generation += 1
        renderPreview(interactive: true)
        scheduleIdleWork()
    }

    private func renderPreview(interactive: Bool) {
        guard !renderInFlight else {
            renderPending = true
            return
        }
        renderInFlight = true
        let snapshot = recipe
        let animated = animateNextPreview
        animateNextPreview = false
        Task {
            let result: Result<CGImage, Error> = await Task.detached(priority: .userInitiated) {
                let scale = min(1, Self.previewSize / Double(max(1, max(snapshot.width, snapshot.height))))
                let width = max(1, Int(Double(snapshot.width) * scale))
                let height = max(1, Int(Double(snapshot.height) * scale))
                return Result { try RenderEngine.render(snapshot, width: width, height: height) }
            }.value
            self.renderInFlight = false
            switch result {
            case .success(let image):
                let rendered = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                self.displayedIsInteractive = interactive
                if animated {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        self.preview = rendered
                        self.previewIdentity += 1
                    }
                } else {
                    self.preview = rendered
                }
            case .failure(let error):
                self.fail("Couldn’t Render the Preview", error)
            }
            if self.renderPending {
                self.renderPending = false
                self.renderPreview(interactive: true)
            }
        }
    }

    /// When edits pause: save, sharpen a small preview and refresh the extras that follow the artwork.
    private func scheduleIdleWork() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            if !self.isLoadingGradient { self.saveNow() }
            if self.displayedIsInteractive, !self.renderInFlight { self.renderPreview(interactive: false) }
            let snapshot = self.recipe
            let styles = await Task.detached(priority: .utility) { Self.renderStyleThumbnails(for: snapshot) }.value
            guard !Task.isCancelled else { return }
            self.styleThumbnails = styles.mapValues { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
            self.prepareDragFile()
        }
    }

    nonisolated private static func renderStyleThumbnails(for recipe: GradientRecipe) -> [GradientMode: CGImage] {
        var styles: [GradientMode: CGImage] = [:]
        for mode in GradientMode.allCases {
            var variant = recipe
            variant.mode = mode
            variant.grain = 0
            if let image = try? RenderEngine.render(variant, width: 120, height: 90) { styles[mode] = image }
        }
        return styles
    }

    // MARK: - Messages

    /// Shows the error alert, titled with what failed.
    private func fail(_ title: String, _ error: Error) {
        errorTitle = title
        errorMessage = error.localizedDescription
    }

    func flash(_ message: String) {
        toastTask?.cancel()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.8)) { toast = message }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    // MARK: - Export

    static func fileSafe(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Undertone" : cleaned
    }

    func exportFileName(extension ext: String) -> String {
        "\(Self.fileSafe(currentName)) \(recipe.width)x\(recipe.height).\(ext)"
    }

    private func renderExport(failureTitle: String, completion: @escaping (CGImage, GradientRecipe) throws -> Void) {
        guard !isRendering else { return }
        isRendering = true
        let snapshot = recipe
        Task {
            defer { isRendering = false }
            do {
                let image = try await Task.detached(priority: .userInitiated) { try RenderEngine.render(snapshot, width: snapshot.width, height: snapshot.height) }.value
                try completion(image, snapshot)
            } catch { fail(failureTitle, error) }
        }
    }

    nonisolated static func encoded(_ image: CGImage, jpeg: Bool = false, quality: Double = ExportFormat.defaultJPEGQuality) throws -> Data {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: jpeg ? .jpeg : .png, properties: jpeg ? [.compressionFactor: quality] : [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    /// Export Image's starting format, from Settings.
    private static var exportFormat: ExportFormat {
        UserDefaults.standard.string(forKey: ExportFormat.preference).flatMap(ExportFormat.init(rawValue:)) ?? .png
    }

    /// JPEG compression quality from Settings, 0.5 to 1.
    private static var jpegQuality: Double {
        let quality = UserDefaults.standard.object(forKey: ExportFormat.jpegQualityPreference) as? Double ?? ExportFormat.defaultJPEGQuality
        return min(1, max(0.5, quality))
    }

    func copyImage() {
        renderExport(failureTitle: "Couldn’t Copy Image") { image, _ in
            let item = NSPasteboardItem()
            item.setData(try Self.encoded(image), forType: .png)
            if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation { item.setData(tiff, forType: .tiff) }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.writeObjects([item]) else { throw CocoaError(.fileWriteUnknown) }
            self.flash("Copied \(self.recipe.width) × \(self.recipe.height) image")
        }
    }

    /// The full-size PNG a canvas drag hands out, named like an export ("Dusk 2160x2880.png"). It is
    /// written ahead of time when edits settle, so a drag starts instantly with a real file every
    /// destination understands; if the artwork changed since, it's rendered on the spot.
    func dragFile() -> URL? {
        let name = exportFileName(extension: "png")
        if let cached = dragFileCache, cached.recipe == recipe, cached.url.lastPathComponent == name,
           FileManager.default.fileExists(atPath: cached.url.path) { return cached.url }
        guard let url = try? Self.writeDragFile(recipe, name: name) else { return nil }
        dragFileCache = (recipe, url)
        return url
    }

    /// Writes the drag file in the background so it's ready before the next drag.
    private func prepareDragFile() {
        let snapshot = recipe, name = exportFileName(extension: "png")
        if let cached = dragFileCache, cached.recipe == snapshot, cached.url.lastPathComponent == name { return }
        Task {
            guard let url = await Task.detached(priority: .utility, operation: { try? Self.writeDragFile(snapshot, name: name) }).value,
                  self.recipe == snapshot else { return }
            self.dragFileCache = (snapshot, url)
        }
    }

    nonisolated private static func writeDragFile(_ recipe: GradientRecipe, name: String) throws -> URL {
        let image = try RenderEngine.render(recipe, width: recipe.width, height: recipe.height)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Undertone Drags", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try encoded(image).write(to: url, options: .atomic)
        return url
    }

    func exportImage() {
        let format = Self.exportFormat
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = exportFileName(extension: format.fileExtension)
        panel.canCreateDirectories = true
        let accessory = ExportFormatAccessory(panel: panel, format: format)
        panel.accessoryView = accessory.view
        Task {
            guard await panel.present(in: window) == .OK, let url = panel.url else { return }
            let jpeg = accessory.format == .jpeg, quality = Self.jpegQuality
            renderExport(failureTitle: "Couldn’t Export Image") { image, _ in
                try Self.encoded(image, jpeg: jpeg, quality: quality).write(to: url, options: .atomic)
                self.flash("Saved \(url.lastPathComponent)")
            }
        }
    }

    func exportRecipe() { exportRecipe(currentName, recipe) }

    /// Exports a specific saved gradient's recipe.
    func exportRecipe(id: UUID) {
        guard let gradient = gradients.first(where: { $0.id == id }) else { return }
        exportRecipe(gradient.name, gradient.recipe)
    }

    private func exportRecipe(_ name: String, _ recipe: GradientRecipe) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = Self.fileSafe(name) + ".undertone.json"
        Task {
            guard await panel.present(in: window) == .OK, let url = panel.url else { return }
            do {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(recipe).write(to: url, options: .atomic)
                flash("Exported \(url.lastPathComponent)")
            } catch { fail("Couldn’t Export Recipe", error) }
        }
    }

    func importRecipe() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        Task {
            guard await panel.present(in: window) == .OK, let url = panel.url else { return }
            importRecipe(from: url)
        }
    }

    private func importRecipe(from url: URL) {
        do {
            let recipe = try Self.validatedRecipe(from: Data(contentsOf: url))
            var name = url.lastPathComponent
            for suffix in [".json", ".undertone"] where name.lowercased().hasSuffix(suffix) { name = String(name.dropLast(suffix.count)) }
            commitRecipe()
            let before = librarySnapshot()
            let seed = Int.random(in: 0...9_999)
            let gradient = SavedGradient(name: name.isEmpty ? NameGenerator.name(for: recipe, seed: seed) : name, hasCustomName: !name.isEmpty, nameSeed: seed, recipe: recipe)
            gradients.insert(gradient, at: 0)
            currentGradientID = gradient.id
            UserDefaults.standard.set(gradient.id.uuidString, forKey: Self.currentGradientPreference)
            load(recipe, animated: true)
            saveNow()
            undoManager?.removeAllActions(withTarget: recipeUndoTarget)
            registerGradientsUndo("Import Recipe", restoring: before)
        } catch { fail("Couldn’t Import Recipe", error) }
    }

    static func validatedRecipe(from data: Data) throws -> GradientRecipe {
        let candidate = try JSONDecoder().decode(GradientRecipe.self, from: data)
        let unitValues = [candidate.flow, candidate.softness, candidate.swirl, candidate.grain, candidate.gradientPosition, candidate.easing, candidate.colorArc]
        guard (0...maximumStops).contains(candidate.stops.count),
              (1...8192).contains(candidate.width), (1...8192).contains(candidate.height),
              unitValues.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              candidate.angleDegrees.isFinite,
              candidate.centerX.isFinite, candidate.centerY.isFinite,
              (-1...2).contains(candidate.centerX), (-1...2).contains(candidate.centerY),
              candidate.fadeWidth.isFinite, (0.05...6).contains(candidate.fadeWidth),
              [candidate.startX, candidate.startY, candidate.endX, candidate.endY].allSatisfy({ $0.isFinite && (-3...3).contains($0) }),
              candidate.grainSize.isFinite, (0.25...10).contains(candidate.grainSize),
              MeshGrid.sizes.contains(candidate.meshSize),
              candidate.meshVertices.isEmpty || candidate.meshVertices.count == candidate.meshSize * candidate.meshSize,
              candidate.meshVertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }),
              candidate.stops.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) && Hex.normalized($0.hex) != nil })
        else { throw CocoaError(.fileReadCorruptFile) }
        return candidate
    }
}

/// The Format pop-up in Export Image's save panel. Choosing a format changes the file type and the
/// name's extension for this export; Settings keeps the default.
private final class ExportFormatAccessory: NSObject {
    private(set) var format: ExportFormat
    let view: NSView
    private weak var panel: NSSavePanel?
    private let popUp = NSPopUpButton(frame: .zero, pullsDown: false)

    init(panel: NSSavePanel, format: ExportFormat) {
        self.panel = panel
        self.format = format
        let stack = NSStackView(views: [NSTextField(labelWithString: "Format:"), popUp])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        view = stack
        super.init()
        popUp.addItems(withTitles: ExportFormat.allCases.map(\.title))
        popUp.selectItem(at: ExportFormat.allCases.firstIndex(of: format) ?? 0)
        popUp.target = self
        popUp.action = #selector(formatChanged)
        stack.frame.size = stack.fittingSize
    }

    @objc private func formatChanged() {
        guard let panel, ExportFormat.allCases.indices.contains(popUp.indexOfSelectedItem) else { return }
        format = ExportFormat.allCases[popUp.indexOfSelectedItem]
        panel.allowedContentTypes = [format.contentType]
        let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = base + "." + format.fileExtension
    }
}
