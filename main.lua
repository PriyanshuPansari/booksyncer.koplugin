--[[
BookSyncer KOReader plugin
Uploads new sideloaded books from /mnt/onboard (root only) to the Calibre server.
sync.sh runs in background via os.execute so KOReader is never blocked.
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager       = require("ui/uimanager")
local InfoMessage     = require("ui/widget/infomessage")
local NetworkMgr      = require("ui/network/manager")
local logger          = require("logger")

local PLUGIN_DIR = "/mnt/onboard/.adds/koreader/plugins/booksyncer.koplugin"
local SYNC_SCRIPT = PLUGIN_DIR .. "/sync.sh"
local LOG_FILE    = "/mnt/onboard/.adds/koreader/booksyncer.log"

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
    -- Runs in background — KOReader stays fully responsive
    os.execute("sh " .. SYNC_SCRIPT .. " 2>>" .. LOG_FILE .. " &")
    logger.info("BookSyncer: sync started in background")
    UIManager:show(InfoMessage:new{
        text = "Book sync started in background.\nCheck log when done.",
        timeout = 3,
    })
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
