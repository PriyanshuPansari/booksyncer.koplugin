--[[
BookSyncer KOReader plugin
Uploads new sideloaded books from /mnt/onboard (root only) to the Calibre server.
Uses ssl.https (KOReader built-in) with pcall guards so errors log instead of crashing.
Collects the file list synchronously, then uploads each file sequentially via scheduleIn
so the UI event loop keeps running between files (prevents watchdog kill on Kobo).
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager       = require("ui/uimanager")
local InfoMessage     = require("ui/widget/infomessage")
local NetworkMgr      = require("ui/network/manager")
local logger          = require("logger")

local SERVER     = "https://kobo.llmplays.com"
local TOKEN      = "e85d044a1093947d34d5467cb79a2454"
local STATE_FILE = "/mnt/onboard/.adds/koreader/booksyncer_uploaded.txt"
local LOG_FILE   = "/mnt/onboard/.adds/koreader/booksyncer.log"

local EBOOK_EXTS = {
    epub=true, pdf=true, mobi=true, cbz=true, cbr=true,
    fb2=true, djvu=true, azw=true, azw3=true, lit=true, lrf=true,
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function log(msg)
    local f = io.open(LOG_FILE, "a")
    if f then f:write(msg .. "\n"); f:close() end
end

local function url_encode(s)
    return (s:gsub("[^%w%-%.%_%~]", function(c)
        return ("%%%02X"):format(c:byte())
    end))
end

local function get_ext(path)
    return (path:match("%.([^%.]+)$") or ""):lower()
end

local function basename(path)
    return path:match("([^/]+)$") or path
end

local function is_uploaded(path)
    local f = io.open(STATE_FILE, "r")
    if not f then return false end
    for line in f:lines() do
        if line == path then f:close(); return true end
    end
    f:close()
    return false
end

local function mark_uploaded(path)
    local f = io.open(STATE_FILE, "a")
    if f then f:write(path .. "\n"); f:close() end
end

local function file_size(path)
    local f = io.open(path, "rb")
    if not f then return 0 end
    local sz = f:seek("end"); f:close()
    return sz
end

-- ── Upload one file (pcall-wrapped so any error goes to log, not a crash) ─────

local function upload_file(filepath, filename)
    -- Lazy-require inside pcall so a missing module logs instead of crashing
    local ok_req, https = pcall(require, "ssl.https")
    if not ok_req then
        return false, "ssl.https unavailable: " .. tostring(https)
    end
    local ok_ltn, ltn12 = pcall(require, "ltn12")
    if not ok_ltn then
        return false, "ltn12 unavailable: " .. tostring(ltn12)
    end

    local fh = io.open(filepath, "rb")
    if not fh then return false, "cannot open file" end
    local size = fh:seek("end"); fh:seek("set", 0)

    local resp = {}
    local ok_req2, result1, result2 = pcall(function()
        return https.request{
            url     = SERVER .. "/file/" .. url_encode(filename),
            method  = "PUT",
            headers = {
                ["Authorization"]  = "Bearer " .. TOKEN,
                ["Content-Type"]   = "application/octet-stream",
                ["Content-Length"] = tostring(size),
            },
            source = ltn12.source.file(fh),
            sink   = ltn12.sink.table(resp),
        }
    end)
    -- ltn12.source.file closes fh itself when exhausted; guard against double-close
    pcall(function() fh:close() end)

    if not ok_req2 then
        return false, "request error: " .. tostring(result1)
    end
    local code = result2  -- https.request returns (r, code, headers, status)
    local body = table.concat(resp)
    if code == 200 or code == 201 then
        return true, body
    end
    return false, "HTTP " .. tostring(code) .. " " .. body
end

-- ── Upload queue: one file per UI tick so watchdog never triggers ─────────────

local function process_next(files, idx, ok_n, fail_n, spinner)
    if idx > #files then
        UIManager:close(spinner)
        log(("=== Done: added=%d skipped=%d failed=%d ==="):format(ok_n, 0, fail_n))
        UIManager:show(InfoMessage:new{
            text = ("Sync done: %d added, %d failed\nSee log for details"):format(ok_n, fail_n),
            timeout = 5,
        })
        return
    end

    local filepath = files[idx]
    local fname    = basename(filepath)

    if is_uploaded(filepath) then
        -- Skip silently, move to next on next tick
        UIManager:scheduleIn(0, function()
            process_next(files, idx + 1, ok_n, fail_n, spinner)
        end)
        return
    end

    local sz = file_size(filepath)
    if sz < 5120 then
        log("  SKIP (too small): " .. fname)
        UIManager:scheduleIn(0, function()
            process_next(files, idx + 1, ok_n, fail_n, spinner)
        end)
        return
    end

    log("  Uploading: " .. fname .. " (" .. math.floor(sz / 1024) .. " KB)")
    local ok, msg = upload_file(filepath, fname)
    if ok then
        mark_uploaded(filepath)
        log("    OK: " .. msg)
        ok_n = ok_n + 1
    else
        log("    FAIL: " .. msg)
        fail_n = fail_n + 1
    end

    -- Yield back to UI before next file
    UIManager:scheduleIn(0, function()
        process_next(files, idx + 1, ok_n, fail_n, spinner)
    end)
end

local function start_sync_queue()
    -- Rotate log
    local lf = io.open(LOG_FILE, "r")
    if lf then
        local sz = lf:seek("end"); lf:close()
        if sz > 204800 then os.rename(LOG_FILE, LOG_FILE .. ".old") end
    end
    log("=== Sync started: " .. os.date() .. " ===")

    -- Collect file list synchronously (fast, no network)
    local p = io.popen("find /mnt/onboard -maxdepth 1 -type f 2>/dev/null")
    if not p then log("ERROR: find failed"); return end
    local files = {}
    for line in p:lines() do
        if EBOOK_EXTS[get_ext(line)] then
            table.insert(files, line)
        end
    end
    p:close()

    if #files == 0 then
        log("No ebook files found.")
        UIManager:show(InfoMessage:new{ text = "No books found in /mnt/onboard", timeout = 3 })
        return
    end

    local spinner = InfoMessage:new{ text = "Syncing " .. #files .. " books...", timeout = 0 }
    UIManager:show(spinner)

    -- Kick off the queue (each file on its own UI tick)
    UIManager:scheduleIn(0, function()
        process_next(files, 1, 0, 0, spinner)
    end)
end

-- ── Widget ────────────────────────────────────────────────────────────────────

local BookSyncer = WidgetContainer:extend{ name = "booksyncer" }

function BookSyncer:init()
    self.ui.menu:registerToMainMenu(self)
end

function BookSyncer:addToMainMenu(menu_items)
    menu_items.booksyncer = {
        text = "Sync Books to Server",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = "Upload new books now",
                callback = function()
                    NetworkMgr:runWhenConnected(function()
                        start_sync_queue()
                    end)
                end,
            },
            {
                text = "View last sync log",
                callback = function() self:showLog() end,
            },
        },
    }
end

function BookSyncer:showLog()
    local f = io.open(LOG_FILE, "r")
    local text = "No sync log yet."
    if f then
        local lines = {}
        for l in f:lines() do table.insert(lines, l) end
        f:close()
        local s = math.max(1, #lines - 39)
        local tail = {}
        for i = s, #lines do tail[#tail + 1] = lines[i] end
        text = table.concat(tail, "\n")
    end
    UIManager:show(InfoMessage:new{ text = text, timeout = 0 })
end

return BookSyncer
