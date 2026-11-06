-- Family-friendly words: the game is also played at a family table, so the
-- words it reveals by itself (the missed words, the solutions, the total)
-- must never include blocklist.lua's vulgar, sexual, scatological, slur or
-- drug-related words. A player who finds one still scores it: the
-- dictionary is not edited.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local Blocklist = dofile(DIR .. "blocklist.lua")

local function setGrid(b, rows)
    b.grid = {}
    for r, row in ipairs(rows) do
        b.grid[r] = {}
        for c = 1, #row do b.grid[r][c] = row:sub(c, c) end
    end
    b.found, b.path = {}, {}
    b:_findAll()
end

describe("family-friendly solutions", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    it("leaves a blocklisted word out of the solutions but still accepts it", function()
        local b = Board:new({ lang = "fr", n = 4, defer = true })
        setGrid(b, { "CACA", "TRES", "BIEN", "OURS" })
        assert.is_not_nil(b.dict["caca"])    -- the dictionary keeps it
        assert.is_nil(b._all_words.CACA)
        assert.is_not_nil(b._all_words.BIEN)
        for _, e in ipairs(b:getMissedWords()) do
            assert.are_not.equal("CACA", e.word)
        end
        for c = 1, 4 do b:tapCell(1, c) end
        assert.are.equal("found", (b:submit()))
    end)

    for _, lang in ipairs({ "en", "fr" }) do
        it("never reveals a blocklisted word on random " .. lang .. " grids", function()
            math.randomseed(11)
            local b = Board:new({ lang = lang, n = 4, defer = true })
            for _ = 1, 15 do
                b:newGame()
                for w in pairs(b._all_words) do
                    assert.is_false(Blocklist.isBlocked(w, lang), w)
                end
            end
        end)
    end
end)

-- "lynch" and its forms were missing from the shared blocklist: a game could
-- draw or reveal LYNCH (EN) or LYNCHAGE (FR). LYNCHPIN is another word.
describe("blocklist: lynch", function()
    it("blocks every English and French form, in any case", function()
        for _, w in ipairs({ "LYNCH", "lynched", "Lynches", "LYNCHING", "LYNCHER", "lynchers" }) do
            assert.is_true(Blocklist.isBlocked(w, "en"), w)
        end
        for _, w in ipairs({ "lyncher", "LYNCHAGE", "lynchee", "lyncheurs" }) do
            assert.is_true(Blocklist.isBlocked(w, "fr"), w)
        end
        assert.is_false(Blocklist.isBlocked("LYNCHPIN", "en"))
    end)
end)
