--[[
BookSyncer KOReader plugin
Uploads new sideloaded books from /mnt/onboard (root only) to the Calibre server.
Uses KOReader's built-in ssl.https — no curl or external tools needed.
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
    local sz = f:seek("end")
    f:close()
    return sz
end

-- ── Upload one file via HTTPS PUT (streaming, no full-read into memory) ────────

local function upload_file(filepath, filename)
    local https = require("ssl.https")
    local ltn12 = require("ltn12")

    local fh = io.open(filepath, "rb")
    if not fh then return false, "cannot open file" end
    local size = fh:seek("end")
    fh:seek("set", 0)

    local resp = {}
    local _, code = https.request{
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
    fh:close()

    local body = table.concat(resp)
    if code == 200 or code == 201 then
        return true, body
    end
    return false, "HTTP " .. tostring(code) .. " " .. body
end

-- ── Main sync logic ───────────────────────────────────────────────────────────

local function do_sync()
    -- Rotate log if > 200 KB
    local lf = io.open(LOG_FILE, "r")
    if lf then
        local sz = lf:seek("end"); lf:close()
        if sz > 204800 then
            os.rename(LOG_FILE, LOG_FILE .. ".old")
        end
    end

    log("=== Sync started: " .. os.date() .. " ===")

    -- Collect ebook files directly in /mnt/onboard (no subdirs)
    local p = io.popen("find /mnt/onboard -maxdepth 1 -type f 2>/dev/null")
    if not p then
        log("ERROR: cannot run find")
        return 0, 0
    end
    local files = {}
    for line in p:lines() do
        if EBOOK_EXTS[get_ext(line)] then
            table.insert(files, line)
        end
    end
    p:close()

    local ok_n, skip_n, fail_n = 0, 0, 0

    for _, filepath in ipairs(files) do
        if is_uploaded(filepath) then
            skip_n = skip_n + 1
        else
            local sz = file_size(filepath)
            if sz < 5120 then
                log("  SKIP (too small): " .. basename(filepath))
            else
                local fname = basename(filepath)
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
            end
        end
    end

    log(("=== Done: added=%d skipped=%d failed=%d ==="):format(ok_n, skip_n, fail_n))
    return ok_n, fail_n
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
                        self:startSync()
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

function BookSyncer:startSync()
    local spinner = InfoMessage:new{ text = "Syncing books...", timeout = 0 }
    UIManager:show(spinner)
    UIManager:scheduleIn(0, function()
        local ok_n, fail_n = do_sync()
        UIManager:close(spinner)
        UIManager:show(InfoMessage:new{
            text = ("Done: %d added, %d failed"):format(ok_n, fail_n),
            timeout = 5,
        })
    end)
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
