ClassCodex Windows + macOS Downloader v1.16.1
==============================================

This release supports Windows and macOS and uses the installed WoW Retail
ClassCodex AddOn as the baseline for incremental updates.

UPDATE MODEL
------------
1. Fetch and verify the production manifest.
2. Compare the manifest with the installed ClassCodex files.
3. Leave files whose size and SHA-256 already match completely untouched.
4. Download only new or changed files.
5. Remove files no longer present in the production manifest, only after all
   required downloads and verification have succeeded.
6. Verify the resulting AddOn before installation changes are committed.
7. Save an independent snapshot for history/rollback.

Snapshots are history only. They are NOT used as the source for unchanged
files during normal updates.

SNAPSHOTS
---------
Snapshots are ordinary independent file copies. No NTFS or APFS hard links
are used. This keeps snapshots independent from the live AddOn and keeps the
filesystem behavior simple and predictable on both Windows and macOS.

The main SSD optimization is the incremental updater itself: unchanged live
files are not rewritten or copied during an update.

WINDOWS
-------
Run Update-ClassCodex.bat.

macOS
-----
Double-click macOS/Update-ClassCodex.command, or run
macOS/Update-ClassCodex.sh from Terminal.

CONFIG
------
config.txt supports:

ADDONS_PATH=

Leave it blank for automatic WoW Retail AddOns detection. If set, the path is
used exactly as the target AddOns directory and must already exist.
