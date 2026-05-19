# mermaid.yazi demo recording — driven by `vhs` (https://github.com/charmbracelet/vhs).
#
# Regenerate the GIF with:
#     cd docs && vhs demo.tape
#
# The script assumes the fixtures under ~/mermaid-test/ exist:
#   - test.mmd                (single mermaid file)
#   - test-with-mermaid.md    (md with one mermaid block)
#   - plain.md                (md without mermaid → glow fallback)

Output demo.gif

Set FontSize 14
Set Width 1200
Set Height 720
Set Theme "Catppuccin Mocha"
Set TypingSpeed 80ms
Set Shell "zsh"

# Land in the test fixtures directory
Type "yazi ~/mermaid-test"
Enter
Sleep 2s

# .mmd standalone — mermaid image fills the preview pane
Type "/test.mmd"
Enter
Sleep 3s

# .md with a mermaid block — split layout (text on top, image at bottom)
Type "/test-with-mermaid.md"
Enter
Sleep 3s

# Scroll a couple of rows to show the live preview tracking
Shift+J
Sleep 700ms
Shift+J
Sleep 700ms
Shift+K
Sleep 700ms

# Toggle mode: split → image-only (max-zoom equivalent)
Type "z"
Sleep 2s

# Toggle back to split
Type "z"
Type "z"
Sleep 2s

# Plain .md falls back to glow
Type "/plain.md"
Enter
Sleep 2s

# Quit
Type "q"
Sleep 500ms
