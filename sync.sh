#!/bin/sh
# sync.sh - Upload new sideloaded books to Calibre server

SERVER="https://kobo.llmplays.com"
TOKEN="e85d044a1093947d34d5467cb79a2454"
STATE_FILE="/mnt/onboard/.adds/koreader/booksyncer_uploaded.txt"
LOG="/mnt/onboard/.adds/koreader/booksyncer.log"
TMPLIST="/tmp/booksyncer_files.txt"

# Rotate log if > 200 KB
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 204800 ]; then
    mv "$LOG" "${LOG}.old"
fi

echo "=== Sync started: $(date) ===" >> "$LOG"

# List ebook files directly in /mnt/onboard (no subdirs), write to temp file
find /mnt/onboard -maxdepth 1 -type f \( -name "*.epub" -o -name "*.pdf" -o -name "*.mobi" -o -name "*.cbz" -o -name "*.cbr" -o -name "*.fb2" -o -name "*.djvu" -o -name "*.azw" -o -name "*.azw3" -o -name "*.lit" -o -name "*.lrf" \) > "$TMPLIST" 2>/dev/null

while IFS= read -r filepath; do

    # Skip if already uploaded
    if grep -qF "$filepath" "$STATE_FILE" 2>/dev/null; then
        continue
    fi

    filename=$(basename "$filepath")
    filesize=$(wc -c < "$filepath" 2>/dev/null || echo 0)

    # Skip very small files (< 5 KB)
    if [ "$filesize" -lt 5120 ]; then
        echo "  SKIP (too small): $filename" >> "$LOG"
        continue
    fi

    echo "  Uploading: $filename ($(( filesize / 1024 )) KB)" >> "$LOG"

    http_code=$(curl -s -w "%{http_code}" -o /tmp/booksyncer_resp.txt \
        --connect-timeout 15 \
        --max-time 300 \
        -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -F "file=@${filepath};filename=${filename}" \
        "${SERVER}/upload")

    body=$(cat /tmp/booksyncer_resp.txt 2>/dev/null)

    case "$http_code" in
        200|201)
            echo "$filepath" >> "$STATE_FILE"
            echo "    OK ($http_code): $body" >> "$LOG"
            ;;
        *)
            echo "    FAIL ($http_code): $body" >> "$LOG"
            ;;
    esac

done < "$TMPLIST"

rm -f "$TMPLIST" /tmp/booksyncer_resp.txt
echo "=== Sync done: $(date) ===" >> "$LOG"
