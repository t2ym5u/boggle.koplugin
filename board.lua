local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

local grid_utils = require("grid_utils")
local shuffle    = grid_utils.shuffle

-- Standard Boggle dice (16 dice for 4×4 game)
local DICE_EN = {
    "AAEEGN","ABBJOO","ACHOPS","AFFKPS",
    "AOOTTW","CIMOTU","DEILRX","DELRVY",
    "DISTTY","EEGHNW","EEINSU","EHRTVW",
    "EIOSST","ELRTTY","HIMNU","HLNNRZ",
}

-- French Boggle dice (optimized for French letter frequencies)
local DICE_FR = {
    "AAEEIO","AEINRS","AELRST","AENOTR",
    "AILOSU","CEINOR","ADEINR","BEIORS",
    "AELORU","CEINST","ADELOR","AIMNOT",
    "ELNRST","CELORU","ADINRS","AEIRST",
}

local LANG_ORDER = { "en", "fr" }

-- Scoring: word length → points
local SCORE = { [3]=1,[4]=1,[5]=2,[6]=3,[7]=5,[8]=11 }
local function wordScore(len)
    if len <= 2 then return 0 end
    return SCORE[len] or (len >= 8 and 11 or 1)
end

local SIZES = { 4, 5 }
local DEFAULT_N = 4

-- ---------------------------------------------------------------------------
-- BoggleBoard
-- ---------------------------------------------------------------------------

local BoggleBoard = {}
BoggleBoard.__index = BoggleBoard

function BoggleBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        n       = opts.n or DEFAULT_N,
        lang    = opts.lang or "en",
        grid    = {},      -- grid[r][c] = letter (string)
        path    = {},      -- current selection path [{r,c}, ...]
        found   = {},      -- set of found words (word→score)
        score   = 0,
        total_possible = 0,
        done    = false,   -- true when game ends
        dict    = nil,     -- will be loaded lazily
    }, self)
    obj:_loadDict()
    obj:newGame()
    return obj
end

function BoggleBoard:_loadDict()
    self.dict = nil
    if self.lang == "fr" then
        local path = _dir .. "words_fr.lua"
        local fn = loadfile(path)
        self.dict = fn and fn() or {}
    else
        local ok, d = pcall(require, "words_en")
        self.dict = ok and d or {}
    end
end

function BoggleBoard:newGame()
    local n = self.n
    local dice = self.lang == "fr" and DICE_FR or DICE_EN
    local freq_en = "AAAABBCDDEEEEFFFGGHHIIIJKLLMMNNOOOOPPQRRRSSSTTTUUUVVWWXYYZ"
    local freq_fr = "AAAAEEEEEEEIIIIINNNOOORRRSSSSTTTTTUULLLDDDCCCMMMPPPPBBGGHV"
    -- Roll dice
    local letters = {}
    if n == 4 then
        local rolled = {}
        for _, d in ipairs(dice) do rolled[#rolled + 1] = d end
        shuffle(rolled)
        for i = 1, 16 do
            local die = rolled[i] or "AEIOR"
            local face = math.random(#die)
            letters[#letters + 1] = die:sub(face, face)
        end
    else
        -- 5×5: use frequency-weighted random letters
        local freq = self.lang == "fr" and freq_fr or freq_en
        for _ = 1, n * n do
            local i = math.random(#freq)
            letters[#letters + 1] = freq:sub(i, i)
        end
    end

    self.grid = {}
    local idx = 1
    for r = 1, n do
        self.grid[r] = {}
        for c = 1, n do
            self.grid[r][c] = letters[idx]
            idx = idx + 1
        end
    end

    self.path  = {}
    self.found = {}
    self.score = 0
    self.done  = false

    -- Pre-compute all possible words
    self.total_possible = 0
    self:_findAll()
end

function BoggleBoard:_findAll()
    self._all_words = {}
    local n = self.n
    local function dfs(r, c, used, word)
        if #word >= 3 and self.dict[word:lower()] then
            self._all_words[word] = wordScore(#word)
        end
        if #word >= 8 then return end
        for dr = -1, 1 do
            for dc = -1, 1 do
                if not (dr == 0 and dc == 0) then
                    local nr, nc = r + dr, c + dc
                    if nr >= 1 and nr <= n and nc >= 1 and nc <= n then
                        local key = nr * 10 + nc
                        if not used[key] then
                            used[key] = true
                            dfs(nr, nc, used, word .. self.grid[nr][nc])
                            used[key] = nil
                        end
                    end
                end
            end
        end
    end
    for r = 1, n do
        for c = 1, n do
            local used = { [r * 10 + c] = true }
            dfs(r, c, used, self.grid[r][c])
        end
    end
    local count = 0
    for _ in pairs(self._all_words) do count = count + 1 end
    self.total_possible = count
end

-- Select or deselect a cell on the current path
-- Returns "added", "removed_end", "invalid", "cleared"
function BoggleBoard:tapCell(r, c)
    if self.done then return "done" end
    -- Check if this cell is already in path
    local path = self.path
    if #path > 0 then
        local last = path[#path]
        if last.r == r and last.c == c then
            -- Remove last cell
            table.remove(path)
            return "removed_end"
        end
        -- Check if this is a non-last cell (clear path)
        for i, p in ipairs(path) do
            if p.r == r and p.c == c then
                -- Clear path up to this point
                self.path = {}
                return "cleared"
            end
        end
        -- Check adjacency
        local dr = math.abs(r - last.r)
        local dc = math.abs(c - last.c)
        if dr > 1 or dc > 1 then return "invalid" end
    end
    -- Add cell
    path[#path + 1] = { r = r, c = c }
    return "added"
end

-- Build current word from path
function BoggleBoard:getCurrentWord()
    local letters = {}
    for _, p in ipairs(self.path) do
        letters[#letters + 1] = self.grid[p.r][p.c]
    end
    return table.concat(letters)
end

-- Submit current word. Returns "too_short", "not_word", "duplicate", "found"
function BoggleBoard:submit()
    local word = self:getCurrentWord()
    self.path = {}
    if #word < 3 then return "too_short", word end
    if self.found[word] then return "duplicate", word end
    if not self.dict[word:lower()] then return "not_word", word end
    -- Valid!
    local pts = wordScore(#word)
    self.found[word] = pts
    self.score = self.score + pts
    return "found", word, pts
end

-- Clear current path
function BoggleBoard:clearPath()
    self.path = {}
end

-- End game
function BoggleBoard:endGame()
    self.done = true
    self.path = {}
end

-- Get sorted list of found words
function BoggleBoard:getFoundWords()
    local list = {}
    for w, s in pairs(self.found) do list[#list + 1] = { word = w, score = s } end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.word < b.word
    end)
    return list
end

-- Get missed words (possible but not found)
function BoggleBoard:getMissedWords()
    local list = {}
    if self._all_words then
        for w, s in pairs(self._all_words) do
            if not self.found[w] then
                list[#list + 1] = { word = w, score = s }
            end
        end
        table.sort(list, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            return a.word < b.word
        end)
    end
    return list
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function BoggleBoard:serialize()
    local n = self.n
    local flat = {}
    for r = 1, n do
        for c = 1, n do flat[#flat + 1] = self.grid[r][c] end
    end
    local found_list = {}
    for w, s in pairs(self.found) do
        found_list[#found_list + 1] = { w, s }
    end
    return {
        n     = n,
        lang  = self.lang,
        grid  = flat,
        found = found_list,
        score = self.score,
        done  = self.done,
    }
end

function BoggleBoard:load(data)
    if type(data) ~= "table" or not data.grid then return false end
    local n = data.n or DEFAULT_N
    self.n     = n
    self.lang  = data.lang or "en"
    self.grid  = {}
    local idx  = 1
    for r = 1, n do
        self.grid[r] = {}
        for c = 1, n do
            self.grid[r][c] = data.grid[idx] or "A"
            idx = idx + 1
        end
    end
    self.found = {}
    for _, pair in ipairs(data.found or {}) do
        self.found[pair[1]] = pair[2]
    end
    self.score = data.score or 0
    self.done  = data.done  or false
    self.path  = {}
    self:_loadDict()
    self:_findAll()
    return true
end

BoggleBoard.SIZES      = SIZES
BoggleBoard.DEFAULT_N  = DEFAULT_N
BoggleBoard.wordScore  = wordScore
BoggleBoard.LANG_ORDER = LANG_ORDER

return BoggleBoard
