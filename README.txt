ROBLOX 2016 BROWSER PORT - STAGE 1

This package applies the first renderer-platform source changes to your existing local clone.
It does NOT create a new client and does NOT alter your master branch. It is intended for:
  web-port/stage-1-webgl-context

IMPORTANT
- Make sure GitHub Desktop currently has web-port/stage-1-webgl-context selected.
- Extract this ZIP.
- Copy BOTH APPLY_WEB_PORT_STAGE1.bat and APPLY_WEB_PORT_STAGE1.ps1 into the root of your local project16 folder (the folder containing .git and README.md).
- Double-click APPLY_WEB_PORT_STAGE1.bat.
- If it reports success, open GitHub Desktop. It should show the changed files under Changes.
- Commit the changes with a message such as: Add initial WebGL 2 renderer context
- Click Push origin.

The script validates the exact expected source sections before writing and makes backups of the four modified original files in .web-port-stage1-backup.

LIMITATIONS
This is only the first renderer/backend source milestone. It is NOT a complete browser build, and it has NOT been compiled or run with Emscripten. The next stages still need a web build target, browser entry point/lifecycle, input, audio, networking, filesystem and asset delivery.
