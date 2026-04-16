--[[
BookSyncer KOReader plugin
Adds a "Sync Books to Server" menu entry that uploads new sideloaded books
to your Calibre server via HTTP.

Wallabag articles live under /mnt/onboard/.adds/ and are automatically excluded.
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager       = require("ui/uimanager")
local InfoMessage     = require("ui/widget/infomessage")
local logger          = require("logger")
local util            = require("util")

local PLUGIN_DIR = "/mnt/onboard/.adds/koreader/plugins/booksyncer.koplugin"
local SYNC_SCRIPT = PLUGIN_DIR .. "/sync.sh"
local LOG_FILE    = "/mnt/onboard/.adds/koreader/booksyncer.log"

local BookSyncer = WidgetContainer:extend{
    name = "booksyncer",
}

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
                    self:startSync()
                end,
            },
            {
                text = "View last sync log",
                callback = function()
                    self:showLog()
                end,
            },
        },
    }
end

function BookSyncer:startSync()
    UIManager:show(InfoMessage:new{
        text = "Syncing books… check log when done.",
        timeout = 3,
    })
    -- Run detached so the UI stays responsive
    os.execute("sh " .. SYNC_SCRIPT .. " > /dev/null 2>&1 &")
    logger.info("BookSyncer: sync started")
end

function BookSyncer:showLog()
    local f = io.open(LOG_FILE, "r")
    local text = "No log yet."
    if f then
        -- Show last 40 lines
        local lines = {}
        for line in f:lines() do
            table.insert(lines, line)
        end
        f:close()
        local start = math.max(1, #lines - 39)
        local tail = {}
        for i = start, #lines do
            table.insert(tail, lines[i])
        end
        text = table.concat(tail, "\n")
    end
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = 0,   -- stay until dismissed
    })
end

return BookSyncer
