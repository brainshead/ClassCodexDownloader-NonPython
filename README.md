# ClassCodex Downloader — Non-Python Edition

An independent, non-Python adaptation of [WoWClassCodexDownloader](https://github.com/gable44/WoWClassCodexDownloader), for users who prefer Windows PowerShell or macOS shell scripts.

This is **not the official downloader** and is not intended to replace or impersonate the original project.

## Included release

The v1.16.1 package provides:
- Windows updater and detailed diff utility (PowerShell with BAT launchers)
- macOS updater and diff utility (Bash, using macOS `osascript` JavaScript support)
- Configurable AddOns target path
- Incremental updates: unchanged files are left untouched
- Manifest and SHA-256 verification
- Independent snapshots for history/rollback

See the release notes in `CHANGELOG-v1.16.1.txt` and usage in `README-v1.16.1.txt`.

## Upstream and licensing

The original project is at https://github.com/gable44/WoWClassCodexDownloader. The upstream source is marked CC0 1.0 Universal; see its license and notices for applicable terms. This adaptation is independent.

ClassCodex addon data and associated third-party trademarks are not relicensed by this repository.

## Status

Version: **1.16.1**. Use at your own discretion; test against a separate AddOns folder before using on a live installation.
