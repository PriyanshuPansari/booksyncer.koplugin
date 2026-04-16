#!/bin/sh
# sync.sh - Upload new sideloaded books to Calibre server
# Runs in background via os.execute so KOReader stays responsive

SERVER="https://kobo.llmplays.com"
TOKEN="e85d044a1093947d34d5467cb79a2454"
STATE_FILE="/mnt/onboard/.adds/koreader/booksyncer_uploaded.txt"
LOG="/mnt/onboard/.adds/koreader/booksyncer.log"
TMPLIST="/tmp/booksyncer_files.txt"
RESP="/tmp/booksyncer_resp.txt"

# Rotate log if > 200 KB
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 204800 ]; then
    mv "$LOG" "${LOG}.old"
fi

echo "=== Sync started: $(date) ===" >> "$LOG"

# List ebook files directly in /mnt/onboard (no subdirs)
find /mnt/onboard -maxdepth 1 -type f \( -name "*.epub" -o -name "*.pdf" -o -name "*.mobi" -o -name "*.cbz" -o -name "*.cbr" -o -name "*.fb2" -o -name "*.djvu" -o -name "*.azw" -o -name "*.azw3" -o -name "*.lit" -o -name "*.lrf" -o -name "*.EPUB" -o -name "*.PDF" -o -name "*.CBZ" -o -name "*.CBR" \) > "$TMPLIST" 2>/dev/null

while IFS= read -r filepath; do

    grep -qF "$filepath" "$STATE_FILE" 2>/dev/null && continue

    filename=$(basename "$filepath")
    filesize=$(wc -c < "$filepath" 2>/dev/null || echo 0)

    if [ "$filesize" -lt 5120 ]; then
        echo "  SKIP (too small): $filename" >> "$LOG"
        continue
    fi

    echo "  Uploading: $filename ($(( filesize / 1024 )) KB)" >> "$LOG"

    wget -q -O "$RESP" \
        --header="Authorization: Bearer $TOKEN" \
        --header="X-Filename: $filename" \
        --post-file="$filepath" \
        "${SERVER}/rawfile" 2>/dev/null
    rc=$?

    if [ $rc -eq 0 ]; then
        echo "$filepath" >> "$STATE_FILE"
        echo "    OK: $(cat "$RESP" 2>/dev/null)" >> "$LOG"
    else
        echo "    FAIL: wget exit $rc" >> "$LOG"
    fi

done < "$TMPLIST"

rm -f "$TMPLIST" "$RESP"
echo "=== Sync done: $(date) ===" >> "$LOG"
