# Agent Notes for this Repository

## Scope
- Applies to `D:\Programing\pySraz\lua` and all subfolders.
- Primary runtime is LÖVE (Love2D) 11.x; Lua code lives in `main.lua` and `src/`.

## Project Layout
- `main.lua`: entrypoint for the game.
- `src/`: modularized game logic and helpers.
- `assets/`: sprite tools and source art.
- `questions.csv`: trivia content loaded at runtime.
- `shadertoy.mp3`: audio source for the FFT shader.
- `renders/`: splash video assets.

## Build / Run
- Main game: `love .`
- Sprite editor demo: `love assets`
- Alternate single-file prototype: `love 11.lua` (legacy; use only if asked).
- There is no build script; distribution is typically via LÖVE’s packaging flow.

## Lint / Format
- No linting configuration found (`.luacheckrc`, `.stylua.toml`, etc.).
- No formatter is configured in this repo.
- If linting is required, confirm tooling choice before adding anything.

## Tests
- No automated test harness or framework is configured.
- There is no command for a single test; manual playthrough is the current validation path.
- Suggested manual checks:
  - Launch `love .` and reach the menu screen.
  - Start a game and confirm piece movement + attack rules.
  - Trigger questions and verify timed answer behavior.
  - Confirm audio + shader background render.
  - Verify splash video handling and fallback text.

## Cursor / Copilot Rules
- No Cursor rules found in `.cursor/rules/` or `.cursorrules`.
- No Copilot instructions found in `.github/copilot-instructions.md`.

## Code Style (Lua)
### Formatting
- Use two spaces for indentation.
- Keep lines readable; wrap long expressions where practical.
- Separate logical blocks with blank lines.
- Prefer trailing commas in multi-line tables.
- Comments use `--` and are kept short.

### Imports / Requires
- `require` statements go at the top of the file.
- Use double quotes in `require` paths, e.g. `require("src.util")`.
- Align `local` require assignments with spacing when grouped:
  - `local Config    = require("src.config")`
  - `local Assets    = require("src.assets")`

### Naming
- Module tables use `PascalCase` (e.g., `Game`, `Assets`, `Config`).
- Helper aliases are short, consistent locals (e.g., `U` for util).
- Functions use `lowerCamelCase`.
- Constants use `UPPER_SNAKE_CASE` in `Config` or top-level tables.
- Booleans use descriptive names: `isFlag`, `isHole`, `hovered`.

### Tables / Data
- Treat mutable state as tables (e.g., `S` in `main.lua`).
- Store runtime state on a shared state object and pass it to modules.
- Prefer explicit fields over positional arrays for readability.
- Use `table.insert` for list append and avoid manual index math.

### Control Flow
- Guard clauses for early exits (nil checks, mode checks).
- Use `pcall` when calling LÖVE APIs that may throw.
- Avoid deeply nested conditionals when a return is clearer.

### Error Handling
- When assets are missing, prefer `print` warnings plus fallback behavior.
- If a resource load fails, set the value to `nil` and continue.
- Do not throw errors for optional content (sprites, videos).

### LÖVE Specifics
- Game loop uses standard `love.load`, `love.update`, `love.draw` callbacks.
- Use `love.graphics.setColor` via `U.setColor255` for consistency.
- Use `love.graphics.setFont` once per block before drawing text.
- Video loading is optional; handle missing file gracefully.

### Math / Random
- Random uses `love.math.random`; seed in `love.load` via `os.time()`.
- Use `U.clamp` and other helpers rather than inline math when available.

### Performance / Rendering
- Avoid rebuilding quads or canvases inside `love.draw` unless necessary.
- Cache sprite sheets and quads at load time.
- Reuse canvases and images across frames when possible.

### File/Asset Access
- Use `love.filesystem.getInfo` to test existence before loading.
- Prefer relative paths rooted at the repo for game assets.
- Keep audio and video files out of hot loops (load once in `love.load`).

### Misc Conventions
- Functions return module tables at end of file (`return Module`).
- Keep module state local; expose public API via returned table only.
- Use `local` for all file-scoped variables.
- Avoid one-letter variable names unless they are loop indices.

### State / Architecture
- Keep global state on the shared `S` table in `main.lua`.
- Pass `S` into modules instead of storing globals.
- Keep module-local helpers `local` and expose only needed functions.
- Prefer pure helpers in `src/util.lua` for common math and data work.
- Create UI state objects (`questionUI`, `feedbackUI`) with explicit fields.

### Rendering Conventions
- Derive layout from `love.graphics.getDimensions()` each frame.
- Cache calculated values that are reused inside loops.
- Use `U.setColor255` for RGB color convenience and consistency.
- Keep fonts in `S.fonts` and set once per draw block.
- Use `love.graphics.rectangle` and `printf` as in existing UI.

### Input Conventions
- Normalize UI input in `Game.mousepressed` before dispatching.
- Use `button == 1` for left-click checks.
- Keep input mode checks (`menu`, `game`, `splash`) near the top.
- Use helper functions for hit-testing (`U.pointInRect`).

### Asset Conventions
- Use `Assets.tryLoadImage` for optional textures.
- Use `Assets.loadSpriteSheet` for animated sprites.
- Store loaded sheets on `S` for reuse during draw.
- Use fallback canvases when assets are missing.

### Questions / CSV
- Load trivia with `Questions.loadQuestionsCSV`.
- Expect CSV rows with 6 columns: category, question, correct, wrong1-3.
- Trim category text with `:match("^%s*(.-)%s*$")`.

### Shader + Audio FFT
- Keep shader source in `src/shader_galaxy.lua`.
- Use `AudioFFT` to update `iChannel0` each frame.
- Ensure `AudioFFT:update` is called before drawing background.

## When Adding New Code
- Mirror patterns in `src/` (module table + functions + `return`).
- Add new assets to `assets/` or top-level, not nested within `src/`.
- Update any manual test checklist if behavior changes.
- If you introduce tooling (tests, lint), document it here.
