local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local Blocklist = assert(loadfile(_dir .. "blocklist.lua"))()

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
    -- opts.defer: the caller loads a saved grid right after, so rolling and
    -- solving one here would be wasted (solving takes seconds on a slow reader).
    if not opts.defer then obj:newGame() end
    return obj
end

-- The dictionary of the language last loaded, shared by every board (solo
-- and multiplayer screens, a board restored over a fresh one): each list is
-- ~10 MB once loaded, so it is read once, and the other language is dropped
-- when the language changes. It loads with the first board, not with the
-- module, and BoggleBoard.release() (the screen closing) drops it: reading it
-- again takes a few tens of milliseconds on a desktop. Always this plugin's own file: require() would
-- search package.path, where every word game prepends its own directory, and
-- could return another game's (much shorter) words_en.lua.
local dict_cache = { lang = nil, dict = nil }

function BoggleBoard:_loadDict()
    local lang = self.lang == "fr" and "fr" or "en"
    if dict_cache.lang ~= lang then
        dict_cache.lang, dict_cache.dict, dict_cache.prefixes = nil, nil, nil
        local fn = loadfile(_dir .. "words_" .. lang .. ".lua")
        dict_cache.dict = fn and fn() or {}
        dict_cache.lang = lang
    end
    self.dict = dict_cache.dict
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

-- Every proper prefix (3 to 7 letters) of the dictionary's words, built once
-- per language next to the dictionary: the grid search below drops a path as
-- soon as its letters cannot start any word, instead of walking every path of
-- up to 8 cells (a few hundred milliseconds per grid on a desktop, several
-- seconds on a slow reader). Shorter prefixes are not stored: nearly every
-- 1-2 letter start leads somewhere, so they would not prune anything.
local MAX_LEN = 8
local function buildPrefixes(dict)
    local prefixes, sub = {}, string.sub
    for w in pairs(dict) do
        local n = #w
        if n > MAX_LEN then n = MAX_LEN end
        -- Longest first: once a prefix is known, all its shorter ones are too.
        for k = n - 1, 3, -1 do
            local p = sub(w, 1, k)
            if prefixes[p] then break end
            prefixes[p] = true
        end
    end
    return prefixes
end

function BoggleBoard:_prefixes()
    -- A board that outlived a release() (cache emptied while it was still
    -- open) puts its dictionary back as the shared one.
    if dict_cache.dict == nil and self.dict then
        dict_cache.lang, dict_cache.dict = self.lang == "fr" and "fr" or "en", self.dict
    end
    if dict_cache.dict ~= self.dict then return buildPrefixes(self.dict) end
    if not dict_cache.prefixes then dict_cache.prefixes = buildPrefixes(self.dict) end
    return dict_cache.prefixes
end

function BoggleBoard:_findAll()
    local all = {}
    self._all_words = all
    -- The grid's word list is what the game reveals (missed words, the
    -- solutions, the total): it leaves out the family-friendly blocklist
    -- (blocklist.lua). Those words are still accepted when a player finds one.
    local blocked = Blocklist.set(self.lang)
    local dict, prefixes = self.dict, self:_prefixes()
    local n = self.n
    -- Lowercase letters (the dictionary's case) and neighbour lists, flat.
    local letter, nbrs = {}, {}
    for r = 1, n do
        for c = 1, n do
            local i = (r - 1) * n + c
            letter[i] = self.grid[r][c]:lower()
            local list = {}
            for dr = -1, 1 do
                for dc = -1, 1 do
                    local nr, nc = r + dr, c + dc
                    if not (dr == 0 and dc == 0)
                            and nr >= 1 and nr <= n and nc >= 1 and nc <= n then
                        list[#list + 1] = (nr - 1) * n + nc
                    end
                end
            end
            nbrs[i] = list
        end
    end
    local used = {}
    local function dfs(i, word, len)
        if len >= 3 then
            if dict[word] then
                local up = word:upper()
                if not blocked[up] then all[up] = wordScore(len) end
            end
            if len >= MAX_LEN or not prefixes[word] then return end
        end
        used[i] = true
        local list = nbrs[i]
        for k = 1, #list do
            local j = list[k]
            if not used[j] then dfs(j, word .. letter[j], len + 1) end
        end
        used[i] = false
    end
    for i = 1, n * n do dfs(i, letter[i], 1) end
    local count = 0
    for _ in pairs(all) do count = count + 1 end
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

-- Drops the loaded dictionary and its prefixes (called when the game screen
-- closes); the next board reads its language's list again.
function BoggleBoard.release()
    dict_cache.lang, dict_cache.dict, dict_cache.prefixes = nil, nil, nil
end

-- The languages whose dictionary is loaded now (for the specs).
function BoggleBoard.loadedLanguages()
    return dict_cache.lang and { dict_cache.lang } or {}
end

BoggleBoard.SIZES      = SIZES
BoggleBoard.DEFAULT_N  = DEFAULT_N
BoggleBoard.wordScore  = wordScore
BoggleBoard.LANG_ORDER = LANG_ORDER

return BoggleBoard
