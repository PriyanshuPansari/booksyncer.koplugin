# BookSyncer KOReader Plugin

Upload sideloaded books from the Kobo to your Calibre library in one tap.

## What it does

- Scans only the root of `/mnt/onboard` (no subdirectories) for ebook files (epub, pdf, mobi, cbz, cbr, fb2, djvu, azw, azw3)
- Wallabag articles and KOReader files live under `/mnt/onboard/.adds/` and are never touched
- Uploads each new file to `https://kobo.llmplays.com/upload`
- The server checks the Calibre library and adds the book if it's not there yet
- Tracks uploaded files locally so the same file is never sent twice

## Installation on the Kobo

1. Connect the Kobo to your computer via USB.

2. Copy the entire `booksyncer.koplugin/` folder to:
   ```
   /mnt/onboard/.adds/koreader/plugins/booksyncer.koplugin/
   ```
   The folder should contain: `_meta.lua`, `main.lua`, `sync.sh`

3. Make `sync.sh` executable (optional — `sh sync.sh` works regardless):
   ```
   chmod +x /mnt/onboard/.adds/koreader/plugins/booksyncer.koplugin/sync.sh
   ```

4. Safely eject the Kobo.

## Using the plugin

In KOReader (file manager or while reading):

- Tap the **menu** (top-left gear / ☰ icon)
- Go to **Tools** → **Sync Books to Server** → **Upload new books now**
- A toast appears: "Syncing books… check log when done."
- The upload runs in the background; the UI stays responsive.
- View the last sync log via **Tools** → **Sync Books to Server** → **View last sync log**

## Files on device

| Path | Purpose |
|------|---------|
| `/mnt/onboard/.adds/koreader/booksyncer_uploaded.txt` | List of already-uploaded file paths |
| `/mnt/onboard/.adds/koreader/booksyncer.log` | Sync log (last 40 lines shown in UI) |

## Server-side check

From Telegram bot: `/importbooks` — shows how many books were imported and recent additions.
