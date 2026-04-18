# Changelog

## v0.2.5 - 2026-04-18

- Fixed the Windows packaging process to build `.love` as a ZIP archive instead of a TAR archive.
- Rebuilt the packaged EXE from a valid ZIP-based `.love` file so the released game actually starts correctly.

## v0.2.4 - 2026-04-18

- Changed the packaged game startup to open directly to the main menu instead of the splash screen.
- Set the game window title to `SRAZ 2026` instead of the default LÖVE title.

## v0.2.3 - 2026-04-18

- Fixed the Windows release package to include the missing Visual C++ runtime DLLs.
- Updated the Windows build instructions to list `msvcp120.dll` and `msvcr120.dll` as required runtime files.

## v0.2.2 - 2026-04-16

- Corrected the bundled Croatian localization and trivia text to use proper UTF-8 Croatian characters.
- Updated the shipped `lua/localization.csv` and `lua/questions.csv` files to use `č ć ž š đ` instead of ASCII fallbacks.

## v0.2.1 - 2026-04-16

- Linked trivia question selection to the active menu language.
- Added Croatian translations for the bundled `lua/questions.csv` set alongside the existing English questions.
- Kept backward compatibility with the legacy 6-column question CSV format.

## v0.2.0 - 2026-04-16

- Added CSV-driven localization for the Lua/LÖVE game.
- Added in-menu language selection with built-in English and Croatian support.
- Added external `lua/localization.csv` so players can add more languages without code changes.
- Localized splash screen, main menu, HUD, legend, and generated player names.
- Kept selected menu language active when loading a saved game.
