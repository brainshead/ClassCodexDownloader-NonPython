# ClassCodex Downloader — Non-Python Edition

An independent, non-Python adaptation of WoWClassCodexDownloader, for users who prefer Windows PowerShell or macOS shell scripts.

This is not the official downloader and is not intended to replace or impersonate the original project.

## v1.16.4

- Windows updater and detailed diff utility (PowerShell with BAT launchers)
- Windows diff launcher calls the standard Windows PowerShell executable path directly
- Automatic WoW install discovery skips inaccessible network-path candidates instead of aborting
- macOS updater and diff utility (Bash)
- Configurable AddOns target path
- Incremental updates, manifest and SHA-256 verification
- Independent snapshots for history/rollback
- Icy Veins export diff with class/spec/hero-tree/profile detection
- UGG item popularity diff

See CHANGELOG-v1.16.4.txt for the repair notes.

## Status

Version: 1.16.4. Test against a separate AddOns folder before using on a live installation.
