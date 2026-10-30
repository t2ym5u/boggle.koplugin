local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local Font       = require("ui/font")
local MenuHelper = require("menu_helper")
local ScreenBase = require("screen_base")
local BoggleBoard       = lrequire("board")
local BoggleBoardWidget = lrequire("board_widget")

local DeviceScreen = Device.screen

-- ---------------------------------------------------------------------------
-- BoggleScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Boggle — Rules

Find as many words as possible by connecting adjacent letters in the 4×4 grid.

Rules:
• Letters must be adjacent (horizontally, vertically, or diagonally).
• Each letter in the grid may only be used once per word.
• Minimum word length: 3 letters.
• Longer words score more points.

Tap letters in sequence to build a word, then tap Submit to score it.
The timer counts down — find as many words as you can before it runs out!
]])

local GAME_RULES_FR = [[
Boggle — Règles

Trouvez le plus de mots possible en reliant des lettres adjacentes dans la grille.

Règles :
• Les lettres doivent être adjacentes (horizontalement, verticalement ou en diagonale).
• Chaque lettre de la grille ne peut être utilisée qu'une seule fois par mot.
• Longueur minimale : 3 lettres.
• Les mots plus longs rapportent plus de points.

Appuyez sur les lettres dans l'ordre pour former un mot, puis sur Valider. La minuterie décompte — trouvez le maximum de mots avant la fin !
]]

local BoggleScreen = ScreenBase:extend{}

function BoggleScreen:init()
    local state = self.plugin:loadState()
    local lang  = self.plugin:getSetting("lang", "en")
    self.board  = BoggleBoard:new{ lang = lang }
    if not self.board:load(state) then
        -- fresh game
    end
    ScreenBase.init(self)
end

function BoggleScreen:serializeState()
    return self.board:serialize()
end

function BoggleScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Boggle"), function()
        return {
            { text = _("New game"),     callback = function() self:onNewGame() end },
            { text = self:_langLabel(), callback = function() self:openLangMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    -- Found words (and, once the game is over, the missed ones): a scrolling
    -- box the width of the controls, three lines under the board in portrait,
    -- a taller column beside it in landscape.
    local controls_w = self:getControlsWidth()
    self.status_text:setMaxWidth(controls_w)
    local list_face = Font:getFace("smallinfofont")
    local list_lines = is_landscape and 8 or 3
    self.word_list_widget = ScrollTextWidget:new{
        text   = self:_buildWordListText(),
        face   = list_face,
        width  = controls_w,
        height = math.ceil(list_face.size * 1.3 * list_lines),
        dialog = self,
    }
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self.word_list_widget,
        VerticalSpan:new{ width = Size.span.vertical_default },
        self:buildActionBar({
            { text = _("Submit"), callback = function() self:onSubmit() end },
            { text = _("Clear"),  callback = function() self:onClear() end },
            { text = _("Done"),   callback = function() self:onEndGame() end },
        }),
    }

    -- Board widget: it draws its own border, so the frame only pads it.
    local frame_pad   = Size.padding.default
    local frame_extra = 2 * frame_pad
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    local board_size = math.max(math.min(budget_w, budget_h) - frame_extra, 80)
    self.board_widget = BoggleBoardWidget:new{
        board      = self.board,
        max_width  = board_size,
        max_height = board_size,
        cellTapCallback  = function(r, c) self:onCellTap(r, c) end,
    }

    local board_frame = FrameContainer:new{
        padding    = frame_pad,
        margin     = 0,
        bordersize = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- "Done" ends the round; the board then only shows the missed words.
function BoggleScreen:isRoundOver()
    return self.board.done
end

function BoggleScreen:onCellTap(r, c)
    local result = self.board:tapCell(r, c)
    self.board_widget:refresh()
    self:updateStatus()
end

function BoggleScreen:onSubmit()
    local result, word, pts = self.board:submit()
    if result == "found" then
        self:updateStatus(T(_("Found: %1 (+%2 pts)"), word, pts))
        self:_refreshWordList()
        self.plugin:saveState(self.board:serialize())
    elseif result == "too_short" then
        self:updateStatus(_("Word too short (min 3 letters)"))
    elseif result == "not_word" then
        self:updateStatus(T(_("Not a word: %1"), word))
    elseif result == "duplicate" then
        self:updateStatus(T(_("Already found: %1"), word))
    end
    self.board_widget:refresh()
end

function BoggleScreen:onClear()
    self.board:clearPath()
    self.board_widget:refresh()
    self:updateStatus()
end

function BoggleScreen:onEndGame()
    self.board:endGame()
    -- The missed words join the word list (they never fitted on the one
    -- status line); the status shows the final score.
    self:_refreshWordList()
    self:updateStatus()
    self.board_widget:refresh()
    self:refreshActionBar()
    self.plugin:saveState(self.board:serialize())
end

function BoggleScreen:onNewGame()
    self.board:newGame()
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function BoggleScreen:openLangMenu()
    local items = {
        { id = "en", text = _("English") },
        { id = "fr", text = _("Français") },
    }
    MenuHelper.openPickerMenu{
        title      = _("Language"),
        items      = items,
        current_id = self.board.lang,
        parent     = self,
        on_select  = function(lang)
            self.board.lang = lang
            self.plugin:saveSetting("lang", lang)
            self.board:_loadDict()
            if self.lang_btn then
                self.lang_btn:setText(self:_langLabel(), self.lang_btn.width)
            end
            self:onNewGame()
        end,
    }
end

function BoggleScreen:_langLabel()
    local lang = self.plugin:getSetting("lang", "en")
    return T(_("Language: %1"), lang == "fr" and "FR" or "EN")
end

function BoggleScreen:_refreshWordList()
    if self.word_list_widget then
        -- ScrollTextWidget has no setText: update its inner text box, then
        -- its scroll bar, which now covers the longer list.
        local list = self.word_list_widget
        list.text_widget:setText(self:_buildWordListText())
        list:resetScroll()
        UIManager:setDirty(self, function() return "ui", self.dimen end)
    end
end

function BoggleScreen:_buildWordListText()
    local found = self.board:getFoundWords()
    local parts = {}
    for _, entry in ipairs(found) do
        parts[#parts + 1] = string.format("%s(%d)", entry.word, entry.score)
    end
    local text = #parts > 0 and table.concat(parts, "  ") or _("No words found yet.")
    if self.board.done then
        local missed = {}
        for _, entry in ipairs(self.board:getMissedWords()) do
            missed[#missed + 1] = entry.word
        end
        if #missed > 0 then
            text = text .. "\n\n" .. T(_("Missed: %1"), table.concat(missed, ", "))
        end
    end
    return text
end

function BoggleScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    else
        local found_cnt = 0
        for _ in pairs(self.board.found) do found_cnt = found_cnt + 1 end
        local progress = self:joinStatus(
            T(_("Score: %1"), self.board.score),
            T(_("Found: %1/%2"), found_cnt, self.board.total_possible))
        if self.board.done then
            status = self:joinStatus(_("Game over!"), progress)
        else
            -- The word being traced leads, so it stays visible when the
            -- line is cut short in the landscape side panel.
            status = self:joinStatus(self.board:getCurrentWord(), progress)
        end
    end
    ScreenBase.updateStatus(self, status)
end

return BoggleScreen
