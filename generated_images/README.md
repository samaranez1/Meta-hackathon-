# Generated art

AI-generated PNG art could not be saved in this environment (the image tool
returned "write failed" on every attempt), so the game ships hand-crafted
vector art instead:

- `icon.svg` (project root) - app icon, wired as the Godot project icon and
  the source for Store tiles (export to 1024px PNG as `SourceIcon.png`).
- `assets/logo.svg` - menu emblem, shown above the title on the main menu.

If you regenerate PNG art elsewhere, drop the files here and point
`config/icon` in `project.godot` at the new icon.
