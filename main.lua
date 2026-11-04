local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = _dir .. "?.lua;" .. _dir .. "common/?.lua;" .. package.path

local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

-- The game screen -- and the boards, word lists and puzzle banks it pulls
-- in -- loads the first time the game is opened, not when KOReader starts:
-- KOReader loads every plugin at startup and keeps it all session, so a
-- top-level require here costs memory even if the game is never played.
-- KOReader has put package.path back by then, so our directories are added
-- again while the module loads (common/ stays as a fallback for the shared
-- modules the game requires later on).
local function lazyrequire(name)
    local saved = package.path
    package.path = _dir .. "?.lua;" .. _dir .. "common/?.lua;" .. saved
    local ok, mod = pcall(lrequire, name)
    package.path = saved
    if not package.path:find(_dir .. "common/?.lua", 1, true) then
        package.path = package.path .. ";" .. _dir .. "common/?.lua"
    end
    if not ok then error(mod, 0) end
    return mod
end

local DataStorage  = require("datastorage")
local LuaSettings  = require("luasettings")
local UIManager    = require("ui/uimanager")
local PluginBase   = require("plugin_base")
local _            = require("i18n")

require("i18n").extend(lrequire("i18n_fr"))

local Boggle = PluginBase:extend{
    name       = "boggle",
    menu_text  = _("Boggle"),
    menu_hint  = "tools",
    -- "Boggle · multiplayer": the grid for a table of players on paper
    -- (formerly the separate Boggle Party plugin).
    party_mode = true,
}

-- fresh: start a new game instead of restoring the saved one.
function Boggle:createScreen(fresh)
    if self.launch_mode == "party" then
        self:migratePartySettings()
        return lazyrequire("party_screen"):new{ plugin = self, fresh = fresh }
    end
    return lazyrequire("screen"):new{ plugin = self, fresh = fresh }
end

-- The in-game "Mode: Solo / Multiplayer" setting: the current game is saved
-- (under its own mode's key), the other screen replaces it with a new game.
function Boggle:switchMode(mode)
    if mode == self.launch_mode then return end
    local old = self.screen
    if old and old.saveGame then old:saveGame() end
    if old then UIManager:close(old) end
    self.launch_mode = mode
    self.screen = self:createScreen(true)
    UIManager:show(self.screen)
end

-- boggleparty.koplugin's settings (settings/boggleparty.lua), or nil when the
-- file does not exist. Only read, never modified or deleted.
local function read_boggleparty_settings()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then ok, lfs = pcall(require, "lfs") end
    local path = DataStorage:getSettingsDir() .. "/boggleparty.lua"
    if not ok or lfs.attributes(path, "mode") ~= "file" then return nil end
    local ok2, s = pcall(LuaSettings.open, LuaSettings, path)
    return ok2 and s and s.data or nil
end

-- One-time import of Boggle Party's language, duration and timer choice, on
-- the first multiplayer launch, unless this mode already has settings of its
-- own (same pattern as dashboard importing startmenu's settings).
function Boggle:migratePartySettings()
    if self:getSetting("party_migrated", false) then return end
    local PartyLogic = lazyrequire("party_logic")
    local has_party = false
    for _i, key in ipairs(PartyLogic.PARTY_KEYS) do
        if self:getSetting(key) ~= nil then has_party = true end
    end
    local out = PartyLogic.migrate(has_party, not has_party and read_boggleparty_settings() or nil)
    for key, value in pairs(out or {}) do
        self.settings:saveSetting(key, value)
    end
    self.settings:saveSetting("party_migrated", true)
    self.settings:flush()
end

return Boggle
