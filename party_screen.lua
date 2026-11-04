-- party_screen.lua — "Boggle · multiplayer" (formerly the Boggle Party
-- plugin): the reader lies in the middle of the table and shows a big grid
-- and the countdown; everyone writes words on paper. At zero it reveals every
-- word of the grid, then tallies each player's remaining words (see
-- party_logic.lua) over a match of N rounds.

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local CenterContainer  = require("ui/widget/container/centercontainer")
local Device           = require("device")
local Font             = require("ui/font")
local FrameContainer   = require("ui/widget/container/framecontainer")
local Geom             = require("ui/geometry")
local HorizontalGroup  = require("ui/widget/horizontalgroup")
local HorizontalSpan   = require("ui/widget/horizontalspan")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size             = require("ui/size")
local TextBoxWidget    = require("ui/widget/textboxwidget")
local TextWidget       = require("ui/widget/textwidget")
local UIManager        = require("ui/uimanager")
local VerticalGroup    = require("ui/widget/verticalgroup")
local VerticalSpan     = require("ui/widget/verticalspan")
local _                = require("i18n")
local T                = require("ffi/util").template

local MenuHelper  = require("menu_helper")
local Party       = require("party")
local ScreenBase  = require("screen_base")
local Timer       = require("timer")
local BoggleBoard = lrequire("board")
local BoardWidget = lrequire("board_widget")
local Logic       = lrequire("party_logic")
local Rules       = lrequire("rules")

local DeviceScreen = Device.screen

-- Font:getFace scales its size by the DPI: a size wanted in pixels is
-- converted back first.
local function pxFace(name, px)
    return Font:getFace(name, math.max(12, math.floor(px * 1000 / DeviceScreen:scaleBySize(1000))))
end

-- A one-line TextWidget of about `px` pixels, shrunk until it fits max_w.
local function bigText(text, px, max_w, bold)
    local w
    repeat
        if w then w:free() end
        w = TextWidget:new{ text = text, face = pxFace("cfont", px), bold = bold }
        px = math.floor(px * 0.9)
    until w:getSize().w <= max_w or px < 14
    return w
end

local function mmss(secs)
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

-- ---------------------------------------------------------------------------
-- PartyScreen
-- ---------------------------------------------------------------------------

local PartyScreen = ScreenBase:extend{}

function PartyScreen:init()
    local p = self.plugin
    -- The word list language: the last multiplayer choice, else the solo
    -- one, else KOReader's language.
    local lang = p:getSetting("party_lang") or p:getSetting("lang")
        or (_.lang() == "fr" and "fr" or "en")
    self.lang       = lang == "fr" and "fr" or "en"
    self.duration   = tonumber(p:getSetting("party_duration", Logic.DEFAULT_DURATION)) or Logic.DEFAULT_DURATION
    self.show_timer = p:getSetting("party_show_timer", true) and true or false
    self.rounds     = tonumber(p:getSetting("party_rounds", Logic.DEFAULT_ROUNDS)) or Logic.DEFAULT_ROUNDS
    self.timer      = Timer:new()

    local saved = not self.fresh and p:loadState("party_state")
    self.match = type(saved) == "table" and Logic.restore(saved.match) or nil
    if self.match then
        self.board = BoggleBoard:new{ lang = self.lang, defer = true }
        if not self.board:load(saved.board) then self.board:newGame() end
        self.timer:load(saved.timer)
        -- A round in progress comes back paused: the countdown resumes on a tap.
        self.timer:stop()
    else
        self.board = BoggleBoard:new{ lang = self.lang }
        self.match = self:_newMatch()
        self:saveGame()
    end
    ScreenBase.init(self)
end

function PartyScreen:_newMatch()
    local names = Party.loadPlayers(self.plugin, Party.loadCount(self.plugin))
    return Logic.newMatch(names, self.rounds)
end

function PartyScreen:serializeState()
    return {
        match = Logic.serialize(self.match),
        board = self.board:serialize(),
        timer = self.timer:serialize(),
    }
end

-- The solo game lives under "state"; this mode only ever writes "party_state".
function PartyScreen:saveGame()
    self.plugin:saveState(self:serializeState(), "party_state")
end

function PartyScreen:closeScreen()
    self:_stopCountdown()
    self:saveGame()
    if self.plugin then self.plugin:onScreenClosed() end
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
end

function PartyScreen:isRoundOver()
    return Logic.isOver(self.match)
end

-- ---------------------------------------------------------------------------
-- Countdown (a tick a second; only the timer area is refreshed, and only
-- when its text changed)
-- ---------------------------------------------------------------------------

function PartyScreen:_remaining()
    return math.max(0, self.duration - math.floor(self.timer:getElapsed()))
end

function PartyScreen:_startCountdown()
    if self.match.phase ~= "playing" or not self.timer:isRunning() then return end
    -- Generation counter: any tick from a previous countdown sees a stale gen and exits.
    self._tick_gen = (self._tick_gen or 0) + 1
    local gen = self._tick_gen
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

function PartyScreen:_stopCountdown()
    self._tick_gen = (self._tick_gen or 0) + 1
end

function PartyScreen:_onTick(gen)
    if gen ~= self._tick_gen then return end
    local remaining = self:_remaining()
    if self.timer_widget and self.timer_widget.text ~= mmss(remaining) then
        self.timer_widget:setText(mmss(remaining))
        local frame = self.timer_frame
        UIManager:setDirty(self, function() return "fast", frame.dimen end)
    end
    if remaining <= 0 then
        self:onSolutions()
    else
        UIManager:scheduleIn(1, function() self:_onTick(gen) end)
    end
end

-- ---------------------------------------------------------------------------
-- Match flow
-- ---------------------------------------------------------------------------

function PartyScreen:_redraw()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- A new grid, in the current language (a language change waits for it).
function PartyScreen:_rollGrid()
    if self.board.lang ~= self.lang then
        self.board.lang = self.lang
        self.board:_loadDict()
    end
    self.board:newGame()
end

function PartyScreen:onNewGame()
    self:_stopCountdown()
    self.timer:reset()
    self.match = self:_newMatch()
    self:_rollGrid()
    self:saveGame()
    self:_redraw()
end

function PartyScreen:onStartRound()
    if not Logic.startPlaying(self.match) then return end
    self.timer:reset()
    self.timer:start()
    self:saveGame()
    self:_redraw()
    self:_startCountdown()
end

function PartyScreen:onPauseResume()
    if self.match.phase ~= "playing" then return end
    if self.timer:isRunning() then
        self:_stopCountdown()
        self.timer:stop()
    else
        self.timer:start()
        self:_startCountdown()
    end
    self:saveGame()
    self:_redraw()
end

-- Time is up, or Solutions / Show solution: every word of the grid is
-- shown, and the tally of the first player starts.
function PartyScreen:onSolutions()
    self:_stopCountdown()
    self.timer:stop()
    if not Logic.startScoring(self.match) then return end
    self:saveGame()
    self:_redraw()
end

function PartyScreen:onTally(b)
    if not Logic.tap(self.match, b) then return end
    self:saveGame()
    if self.tally_widget then
        self.tally_widget:setText(self:_tallyText())
        local frame = self.tally_frame
        UIManager:setDirty(self, function() return "ui", frame.dimen end)
    end
end

function PartyScreen:onUndo()
    if Logic.undo(self.match) then
        self:saveGame()
        self:_redraw()
    end
end

function PartyScreen:onNextPlayer()
    local m = self.match
    local result = Logic.nextPlayer(m)
    if not result then return end
    if result == "round" then self:_rollGrid() end
    self:saveGame()
    self:_redraw()
    if result == "over" then
        Party.showScoreboard(m.scores, { final = true })
    elseif result == "round" then
        Party.showScoreboard(m.scores, {
            title = T(_("Round %1/%2"), m.round - 1, m.rounds) .. "\n" .. Logic.gainsText(m),
        })
    end
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

function PartyScreen:openLangMenu()
    MenuHelper.openPickerMenu{
        title      = _("Language"),
        items      = { { id = "en", text = _("English") }, { id = "fr", text = _("Français") } },
        current_id = self.lang,
        parent     = self,
        on_select  = function(lang)
            self.lang = lang
            self.plugin:saveSetting("party_lang", lang)
            -- Between rounds the waiting grid is rolled again; during a
            -- round the change waits for the next grid.
            if self.match.phase == "ready" then
                self:_rollGrid()
                self:saveGame()
            end
            self:_redraw()
        end,
    }
end

function PartyScreen:openDurationMenu()
    local items = {}
    for _i, d in ipairs(Logic.DURATIONS) do items[#items + 1] = { id = d, text = mmss(d) } end
    items[#items + 1] = { id = "__toggle_timer__", text = self.show_timer and _("Hide timer") or _("Show timer") }
    MenuHelper.openPickerMenu{
        title      = _("Duration"),
        items      = items,
        current_id = self.duration,
        parent     = self,
        on_select  = function(d)
            if d == "__toggle_timer__" then
                self.show_timer = not self.show_timer
                self.plugin:saveSetting("party_show_timer", self.show_timer)
            else
                -- Also applies to the round being played.
                self.duration = d
                self.plugin:saveSetting("party_duration", d)
            end
            self:_redraw()
            if self.match.phase == "playing" and self:_remaining() <= 0 then
                self:onSolutions()
            end
        end,
    }
end

function PartyScreen:openRoundsMenu()
    local items = {}
    for _i, n in ipairs(Logic.ROUNDS) do items[#items + 1] = { id = n, text = tostring(n) } end
    MenuHelper.openPickerMenu{
        title      = _("Rounds"),
        items      = items,
        current_id = self.rounds,
        parent     = self,
        on_select  = function(n)
            self.rounds = n
            self.plugin:saveSetting("party_rounds", n)
            self:onNewGame()
        end,
    }
end

function PartyScreen:openModeMenu()
    MenuHelper.openPickerMenu{
        title      = _("Mode"),
        items      = { { id = "solo", text = _("Solo") }, { id = "party", text = _("Multiplayer") } },
        current_id = "party",
        parent     = self,
        on_select  = function(mode) self.plugin:switchMode(mode) end,
    }
end

-- ---------------------------------------------------------------------------
-- Texts
-- ---------------------------------------------------------------------------

-- Every word of the grid, grouped by length, with the totals (as Boggle
-- Party showed them).
function PartyScreen:_solutionText()
    local by_len, max_len, total = {}, 3, 0
    for w in pairs(self.board._all_words or {}) do
        local l = #w
        if l > max_len then max_len = l end
        by_len[l] = by_len[l] or {}
        by_len[l][#by_len[l] + 1] = w
        total = total + 1
    end
    local lines = {}
    for l = 3, max_len do
        local words = by_len[l]
        if words then
            table.sort(words)
            lines[#lines + 1] = T(_("%1 letters (%2): %3"), l, #words, table.concat(words, ", "))
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = T(_("Total: %1"), total)
    return table.concat(lines, "\n")
end

function PartyScreen:_tallyText()
    local m = self.match
    local counts = m.tally[m.scorer]
    local parts = {}
    for b, def in ipairs(Logic.BUCKETS) do
        if counts[b] > 0 then parts[#parts + 1] = def.label .. " ×" .. counts[b] end
    end
    local head = T(_("%1: %2 pts"), m.scores.names[m.scorer], Logic.points(counts))
    return head .. "\n" .. (#parts > 0 and table.concat(parts, " · ")
        or _("Tap the length of each unique word."))
end

function PartyScreen:_durationLabel()
    return T(_("Duration: %1"), mmss(self.duration))
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function PartyScreen:buildLayout()
    local is_landscape = self:isLandscape()
    local m     = self.match
    local phase = m.phase

    local title_bar = self:buildTitleBar(T(_("%1 · multiplayer"), _("Boggle")), function()
        local items = {
            { text = _("New game"), callback = function() self:onNewGame() end },
            { text = T(_("Players: %1"), #m.scores.names), callback = function()
                Party.pickCount(self.plugin, function() self:onNewGame() end, self)
            end },
            { text = _("Player names"), callback = function()
                -- Renames the seats of the match in progress too.
                Party.editPlayers(self.plugin, m.scores.names, function()
                    self:saveGame()
                    self:_redraw()
                end, self)
            end },
            { text = T(_("Language: %1"), self.lang == "fr" and "FR" or "EN"),
              callback = function() self:openLangMenu() end },
            { text = T(_("Rounds: %1"), self.rounds), callback = function() self:openRoundsMenu() end },
            { text = self:_durationLabel(), callback = function() self:openDurationMenu() end },
            { text = T(_("Mode: %1"), _("Multiplayer")), callback = function() self:openModeMenu() end },
        }
        if phase == "playing" then
            items[#items + 1] = { text = _("Show solution"), callback = function() self:onSolutions() end }
        end
        items[#items + 1] = self:makeModeRulesButtonConfig(Rules)
        return items
    end)

    local controls_w = self:getControlsWidth()
    local sw, sh = self.dimen.w, self.dimen.h
    local short = math.min(sw, sh)
    self.status_text:setMaxWidth(controls_w)
    -- The status of this phase now: its height sizes the controls.
    self:updateStatus()
    self.timer_widget, self.timer_frame = nil, nil
    self.tally_widget, self.tally_frame = nil, nil

    local panel = {}
    local buttons
    if phase == "ready" then
        panel[#panel + 1] = bigText(T(_("Round %1/%2"), m.round, m.rounds),
            math.floor(short * 0.09), controls_w, true)
        panel[#panel + 1] = TextBoxWidget:new{
            text      = m.round > 1 and table.concat(Party.scoreLines(m.scores), "\n")
                        or self:_durationLabel(),
            face      = Font:getFace("infofont"),
            width     = controls_w,
            alignment = "center",
        }
        buttons = { { text = _("Start round"), callback = function() self:onStartRound() end } }
    elseif phase == "playing" then
        if self.show_timer then
            -- Readable from across the table: a sixth of the short side.
            self.timer_widget = TextWidget:new{
                text = mmss(self:_remaining()),
                face = pxFace("cfont", math.floor(short * 0.16)),
            }
            self.timer_frame = FrameContainer:new{
                bordersize = 0, padding = 0, margin = 0,
                CenterContainer:new{
                    dimen = Geom:new{ w = controls_w, h = self.timer_widget:getSize().h },
                    self.timer_widget,
                },
            }
            panel[#panel + 1] = self.timer_frame
        end
        buttons = {
            { text = self.timer:isRunning() and _("Pause") or _("Resume"),
              callback = function() self:onPauseResume() end },
            { text = _("Solutions"), callback = function() self:onSolutions() end },
        }
    elseif phase == "scoring" then
        self.tally_widget = TextBoxWidget:new{
            text      = self:_tallyText(),
            face      = Font:getFace("infofont"),
            width     = controls_w,
            alignment = "center",
        }
        -- Room for three lines whatever the tally says (the hint may wrap),
        -- so a tap only redraws this box and never resizes the panel.
        local line_h = self.tally_widget:getLineHeight()
        self.tally_frame = FrameContainer:new{
            bordersize = 0, padding = 0, margin = 0,
            CenterContainer:new{
                dimen = Geom:new{ w = controls_w, h = math.max(3 * line_h, self.tally_widget:getSize().h) },
                self.tally_widget,
            },
        }
        panel[#panel + 1] = self.tally_frame
        local keys = {}
        for b, def in ipairs(Logic.BUCKETS) do
            keys[b] = { text = def.label, callback = function() self:onTally(b) end }
        end
        panel[#panel + 1] = self:buildNumberPad(keys, controls_w)
        buttons = {
            { text = _("Undo"), callback = function() self:onUndo() end },
            { text = Logic.isLastScorer(m) and _("End round") or _("Next player"),
              callback = function() self:onNextPlayer() end },
        }
        -- The solutions list on top takes what is left: in landscape the
        -- whole column under the status, in portrait a fifth of the screen
        -- (the grid keeps the rest).
        local list_h
        if is_landscape then
            local used = self.status_text:getSize().h + self.tally_frame:getSize().h
                + 2 * panel[2]:getSize().h -- the pad, and the bar of the same height
                + 4 * Size.span.vertical_large
            list_h = sh - title_bar:getSize().h - 2 * self:getGutter() - used
        else
            list_h = sh * 0.2
        end
        local list_face = Font:getFace("smallinfofont")
        list_h = math.max(math.floor(list_h), math.ceil(list_face.size * 1.3 * 2))
        table.insert(panel, 1, ScrollTextWidget:new{
            text   = self:_solutionText(),
            face   = list_face,
            width  = controls_w,
            height = list_h,
            dialog = self,
        })
    else -- over
        local leaders = Party.leaders(m.scores)
        local head = #leaders == 1 and T(_("%1 wins!"), m.scores.names[leaders[1]]) or _("It's a tie!")
        panel[#panel + 1] = bigText(head, math.floor(short * 0.08), controls_w, true)
        panel[#panel + 1] = TextBoxWidget:new{
            text      = table.concat(Party.scoreLines(m.scores), "\n"),
            face      = Font:getFace("infofont"),
            width     = controls_w,
            alignment = "center",
        }
        buttons = { { text = _("New game"), callback = function() self:onNewGame() end } }
    end

    local controls = VerticalGroup:new{ align = "center", self.status_text }
    for _i, w in ipairs(panel) do
        table.insert(controls, VerticalSpan:new{ width = Size.span.vertical_large })
        table.insert(controls, w)
    end
    table.insert(controls, VerticalSpan:new{ width = Size.span.vertical_large })
    table.insert(controls, self:buildActionBar(buttons))

    -- Board: as large as the budget allows; it draws its own border, so the
    -- frame only pads it. Empty tiles until the round starts.
    local frame_pad = Size.padding.default
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    local board_size = math.max(math.min(budget_w, budget_h) - 2 * frame_pad, 80)
    self.board_widget = BoardWidget:new{
        board        = self.board,
        max_width    = board_size,
        max_height   = board_size,
        display_only = true,
        hidden       = phase == "ready",
    }
    local board_frame = FrameContainer:new{
        padding = frame_pad, margin = 0, bordersize = 0,
        self.board_widget,
    }

    if is_landscape then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end

    self:updateStatus()
end

function PartyScreen:updateStatus(msg)
    local m = self.match
    local status = msg
    if not status then
        local round = T(_("Round %1/%2"), m.round, m.rounds)
        local scores = Party.statusText(m.scores)
        if m.phase == "ready" then
            status = self:joinStatus(round, scores)
        elseif m.phase == "playing" then
            -- The duration only when the countdown is hidden: the big timer
            -- already reads it out.
            status = self:joinStatus(round, T(_("Words: %1"), self.board.total_possible),
                not self.show_timer and self:_durationLabel() or nil,
                not self.timer:isRunning() and _("Paused") or nil)
        elseif m.phase == "scoring" then
            status = self:joinStatus(round, T(_("Words: %1"), self.board.total_possible))
        else
            status = self:joinStatus(_("Final scores"), scores)
        end
    end
    ScreenBase.updateStatus(self, status)
end

-- The dictionary is only needed while a game is open: drop it when the
-- screen closes (the next game reads its language's list again).
function PartyScreen:onCloseWidget()
    BoggleBoard.release()
end

return PartyScreen
