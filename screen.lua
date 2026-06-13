local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local T               = require("ffi/util").template

local Font       = require("ui/font")
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
    local sw           = DeviceScreen:getWidth()
    local sh           = DeviceScreen:getHeight()
    local is_landscape = self:isLandscape()

    local btn_width = is_landscape
        and math.max(math.floor(sw * 0.38), 120)
        or  math.floor(sw * 0.9)

    local top_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_width,
        buttons = {{
            { text = _("New"),    callback = function() self:onNewGame() end },
            { text = _("Submit"), callback = function() self:onSubmit() end },
            { text = _("Clear"),  callback = function() self:onClear() end },
            { id = "lang_btn", text = self:_langLabel(),
              callback = function() self:openLangMenu() end },
            { text = _("Done"),   callback = function() self:onEndGame() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
            self:makeCloseButtonConfig(),
        }},
    }
    self.lang_btn = top_buttons:getButtonById("lang_btn")

    -- Board widget
    local board_size = is_landscape
        and math.floor(math.min(sw * 0.45, sh * 0.7))
        or  math.floor(sw * 0.8)
    board_size = math.max(board_size, 80)

    self.board_widget = BoggleBoardWidget:new{
        board      = self.board,
        max_width  = board_size,
        max_height = board_size,
        onCellTap  = function(r, c) self:onCellTap(r, c) end,
    }

    local board_frame = FrameContainer:new{
        padding = Size.padding.default,
        margin  = Size.margin.default,
        self.board_widget,
    }

    -- Word list display (found words)
    local list_w = is_landscape
        and math.max(math.floor(sw * 0.38) - Size.margin.default * 2, 100)
        or  btn_width - Size.margin.default * 2
    local list_h = is_landscape
        and math.floor(sh * 0.35)
        or  math.floor(sh * 0.2)

    self.word_list_widget = TextBoxWidget:new{
        text   = self:_buildWordListText(),
        face   = Font:getFace("smallinfofont"),
        width  = list_w,
        height = list_h,
    }

    if is_landscape then
        local right = VerticalGroup:new{
            align = "center",
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.word_list_widget,
        }
        self.layout = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right,
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.word_list_widget,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end
    self[1] = self.layout
    self:updateStatus()
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
    -- Show missed words
    local missed = self.board:getMissedWords()
    local parts = {}
    for i = 1, math.min(20, #missed) do
        parts[#parts + 1] = missed[i].word
    end
    if #parts > 0 then
        self:updateStatus(T(_("Missed: %1"), table.concat(parts, ", ")))
    end
    self:_refreshWordList()
    self.board_widget:refresh()
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
    return lang == "fr" and "FR" or "EN"
end

function BoggleScreen:_refreshWordList()
    if self.word_list_widget then
        self.word_list_widget:setText(self:_buildWordListText())
        UIManager:setDirty(self, function() return "ui", self.dimen end)
    end
end

function BoggleScreen:_buildWordListText()
    local found = self.board:getFoundWords()
    if #found == 0 then return _("No words found yet.") end
    local parts = {}
    for _, entry in ipairs(found) do
        parts[#parts + 1] = string.format("%s(%d)", entry.word, entry.score)
    end
    return table.concat(parts, "  ")
end

function BoggleScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board.done then
        local found = self.board:getFoundWords()
        status = T(_("Game over! Score: %1  Words: %2/%3"),
            self.board.score, #found, self.board.total_possible)
    else
        local word = self.board:getCurrentWord()
        local found_cnt = 0
        for _ in pairs(self.board.found) do found_cnt = found_cnt + 1 end
        if word ~= "" then
            status = T(_("Word: %1  Score: %2  Found: %3"), word, self.board.score, found_cnt)
        else
            status = T(_("Score: %1  Found: %2/%3"),
                self.board.score, found_cnt, self.board.total_possible)
        end
    end
    ScreenBase.updateStatus(self, status)
end

return BoggleScreen
