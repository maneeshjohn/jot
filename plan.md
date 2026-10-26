# Lightweight macOS Markdown Editor — Execution Plan

A minimalist, local-first AppKit Markdown editor built without Xcode using Swift Package Manager, Zed, and the macOS Command Line Tools.

---

## Architecture Overview

* **UI Layer:** Native AppKit (`NSSplitViewController`, `NSTextView`, `NSOutlineView`).
* **Text Model:** Pure Markdown (`.md` files) stored on disk; no proprietary database.
* **Build System:** Swift Package Manager (`Package.swift`) targeting macOS 13+.
* **Dev Environment:** Zed + `sourcekit-lsp` + Terminal (`swift run`).
* **Backup:** Background Git commands executed via Swift `Process`.

---

## 4-Week Phased Roadmap

### Week 1: Core AppKit Shell & Raw Editor

- [ ] **SPM Setup & Window Initialization**
  - Initialize the project with `swift package init --type executable`.
  - Configure `Package.swift` for macOS 13+ and add `apple/swift-markdown`.
  - Create `main.swift` and `AppDelegate.swift` programmatically.
  - Configure borderless window chrome (`hiddenTitleBar`, transparent titlebar, full-size content view).
- [ ] **Dual-Pane Split Layout**
  - Implement `NSSplitViewController`.
  - Leading pane: Sidebar container for note lists and tags.
  - Trailing pane: Editor container.
  - Map `Cmd + \` to collapse and expand the sidebar.
- [ ] **Raw Editor Setup (`NSTextView`)**
  - Wrap `NSTextView` in an `NSScrollView`.
  - Configure text attributes: monospaced/system font, custom line height, and paragraph spacing.
  - Disable smart quotes, smart dashes, and autocorrect to prevent syntax corruption.
- [ ] **Local File I/O**
  - Implement note directory selection (defaulting to `~/Notes` or user-selected folder).
  - Add standard file actions: Open, Save, and Debounced Auto-save (1s after typing stops).

---

### Week 2: Metadata, Fast Search & Bin Functionality

- [ ] **Metadata Indexing & Tag Engine**
  - Parse YAML frontmatter (`tags: [...]`) and inline hashtags (`#tag`) on load.
  - Maintain an in-memory index:
    ```swift
    struct NoteMetadata {
        let id: UUID
        let fileURL: URL
        var title: String
        var tags: Set<String>
        var lastModified: Date
        var isTrashed: Bool
        var trashedAt: Date?
        var originalURL: URL?
    }
    ```
- [ ] **Sidebar Navigation & Search**
  - Display tags and notes list using `NSOutlineView`.
  - Implement a minimal filter/search bar above the sidebar list.
  - Filter notes instantly in-memory by title or tag intersection.
- [ ] **Trash / Bin System (`.trash/` Folder)**
  - Move deleted files into a hidden local directory (`<NotesRoot>/.trash/`).
  - Store metadata for trashed files (original relative path + deletion timestamp) in `<NotesRoot>/.trash/trash_index.json`.
  - **Sidebar Bin Section:** Display a dedicated "Bin" section at the bottom of the sidebar.
  - **Read-Only Inspection:** When a file in the Bin is selected:
    - Display note contents in `NSTextView`.
    - Set `textView.isEditable = false` and `textView.isSelectable = true`.
  - **Restore Action:** Move file back to its recorded `originalURL` and refresh index.
  - **Permanent Delete:** Hard delete specific files immediately via context menu or `Cmd + Delete`.
  - **7-Day Auto-Purge:** On app startup, scan `trash_index.json`. Delete any file where `Date() - trashedAt > 7 days` from disk and update the index.

---

### Week 3: Git Sync & Theme Engine

- [ ] **Background Git Integration**
  - Check if `<NotesRoot>/.git` exists; if not, provide an option to initialize it.
  - Create a lightweight background runner using Swift `Process`:
    ```swift
    func runGit(args: [String], directory: URL) async throws -> String
    ```
  - Auto-commit and push on a 5-minute debounce after edits or when the app loses focus/terminates.
  - Add visual non-intrusive status (e.g., small dot in sidebar) indicating sync status (Clean, Uncommitted, Syncing, Error).
- [ ] **Theme Architecture (10 Themes)**
  - Create a unified `Theme` struct supporting background, sidebar, caret, text, and selection colors.
  - Bundle 10 JSON theme files in `Resources/Themes/`:
    - **Dark:** Catppuccin Mocha, Rosé Pine Moon, Kanagawa Dragon, One Dark, Darcula.
    - **Light:** Catppuccin Latte, Rosé Pine Dawn, Kanagawa Lotus, One Light, Solarized Light.
  - Implement dynamic theme switching without restarting:
    - Apply background and text colors to `NSTextView`, `NSScrollView`, and sidebar.
    - Set `textView.insertionPointColor` to theme accent.
    - Save selected theme to `UserDefaults`.

---

### Week 4: Frictionless Insertion UI (Context Menus & Modals)

- [ ] **Right-Click Context Menu & Shortcuts**
  - Override `menu(for event: NSEvent)` in custom `NSTextView`.
  - Provide quick actions: Insert Table, Insert Link, Insert Image, Toggle Checkbox.
- [ ] **Interactive Checkboxes**
  - Detect `- [ ]` and `- [x]` lines.
  - Map shortcut (`Cmd + Shift + C`) to toggle task completion on the active line.
- [ ] **Link & Image HUD (`Cmd + K`)**
  - Pop a lightweight native HUD under the cursor.
  - Automatically wrap selected text into `[Title](url)`.
  - For images, open `NSOpenPanel` to select an image, copy it to `<NotesRoot>/assets/`, and insert `![Alt](assets/filename.png)`.
- [ ] **Table Generator (`Cmd + Shift + T`)**
  - Popover modal asking for Row and Column counts.
  - Insert formatted pipe table template at insertion point.
  - Intercept Tab key in `NSTextView` to jump between `|` cells.

---

## Future Scope (Post-V1)

- [ ] **In-Place Hybrid/UI Mode:** Replace raw Markdown tokens with inline styling and rendered block widgets via `apple/swift-markdown` and `NSTextStorage`.
- [ ] **Local Data Encryption:** Add an `EncryptedStorageAdapter` using AES-GCM-256 for local file encryption before committing to remote backends.
- [ ] **Standalone App Packaging:** Set up a shell script to bundle SPM build artifacts into a signed `.app` bundle with `Info.plist` and icon assets.
-
