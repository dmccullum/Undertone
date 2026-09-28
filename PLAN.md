# Undertone — native Mac gradient studio

Current direction: image handoff uses Copy Image and Save Image. Instagram (2160 × 2880) is available as a canvas preset.

Working name: Undertone. SwiftUI interface, AppKit clipboard and native panels, local files and palettes. macOS 14+. No accounts, backend, paid APIs, or third-party packages.

## Interaction design

Standard resizable Mac window with system typography, toolbar, keyboard shortcuts and three parts:

```
┌ Gradients | Colors ┬──────── Name ✦ ──── 2160 × 2880 ┬ Inspector ────────┐
│ thumbnail list     │                                  │ Style tiles       │
│   or               │        [flowing artwork]         │ Style controls    │
│ swatch grid        │     handles appear on hover      │ Texture           │
│                    │  ( ● ● ● ● + │ × )  color tray   │                   │
└────────────────────┴──────────────────────────────────┴───────────────────┘
          Toolbar: Randomize · Copy Image · Export Image · Inspector
```

Two libraries, not three. A collection of named colors covers both brand libraries and small palettes. A gradient is a full recipe (colors, positions, direction, center, sliders, seed and canvas size) with a name, and it autosaves like a note. Names come from the colors through a deterministic word picker, upgraded by Apple's on-device Foundation Models framework where Apple Intelligence is available.

The window takes on the artwork's colors through a blurred copy of the preview behind the canvas and inspector. Style tiles are live renders of the current colors, which the renderer's speed makes cheap. Preview changes from Randomize, style switches, undo and gradient selection crossfade.

## First development slice

1. Deterministic renderer with Organic, Linear, Magic Linear, Magic Single, Radial Glow, and Aurora modes plus granular film grain. Identical settings and seed reproduce a composition.
2. Native editor with mode-specific controls, movable Organic color stops, palette controls, related-tone suggestions, randomization and export dimensions.
3. Persistent named palettes, portable JSON recipes, PNG/JPEG export, clipboard and file drag.
4. Build a local `.app`, test renderer and export basics, inspect the running interface where automation permits.

Sol owns the renderer and tests. Terra owns the native interface. The coordinating agent owns model, persistence, exports, packaging and integration. Shared data contracts are fixed before parallel work to keep rework and model cost low.

## Follow-on work and acceptance gates

- Verify direct drop and paste into Canva in the user's actual browser/app, plus Finder and Preview. AppKit supports standard transfer representations; each destination decides what it accepts.
- Profile 4K and 8K exports; verify color, file dimensions and grain scaling. Respect explicit memory/dimension caps rather than allowing oversized requests to crash.
- Undo/redo and library autosave shipped in the redesign. Still open: favorite compositions, color and position locks, export history.
- Explore Liquid Blobs as the next distinct flowing mode and a richer editable mesh when point topology can be made clear.
- Improve palette suggestions with perceptual color-space distances and editable brand tolerance; initial suggestions are deterministic related tones, not AI or a guarantee of brand compliance.
- Add a Metal renderer if measured performance requires it, file promises for delayed drag export, and background pre-rendering of the drag shelf.
- Test accessibility, light/dark mode and Intel hardware; Developer ID signing and notarization are a separate distribution milestone.

## Sources

- [Apple: AppKit drag and drop](https://developer.apple.com/documentation/appkit/drag-and-drop)
- [Apple: NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard)
- [Apple: Creating a macOS app](https://developer.apple.com/tutorials/swiftui/creating-a-macos-app)
