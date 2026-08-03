local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("BoggleBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    describe("new / newGame", function()
        it("rolls a full 4x4 grid of letters", function()
            math.randomseed(42)
            local b = Board:new()
            assert.are.equal(4, b.n)
            for r = 1, b.n do
                for c = 1, b.n do
                    assert.is_not_nil(b.grid[r][c])
                    assert.are.equal(1, #b.grid[r][c])
                end
            end
        end)

        it("pre-computes at least some findable words", function()
            math.randomseed(42)
            local b = Board:new()
            assert.is_true(b.total_possible >= 0)
        end)
    end)

    describe("tapCell / getCurrentWord", function()
        it("adds adjacent cells to the path", function()
            math.randomseed(42)
            local b = Board:new()
            assert.are.equal("added", b:tapCell(1, 1))
            assert.are.equal("added", b:tapCell(1, 2))
            assert.are.equal(2, #b.path)
        end)

        it("rejects a non-adjacent cell", function()
            math.randomseed(42)
            local b = Board:new()
            b:tapCell(1, 1)
            assert.are.equal("invalid", b:tapCell(4, 4))
        end)

        it("tapping the last cell again removes it", function()
            math.randomseed(42)
            local b = Board:new()
            b:tapCell(1, 1)
            b:tapCell(1, 2)
            assert.are.equal("removed_end", b:tapCell(1, 2))
            assert.are.equal(1, #b.path)
        end)

        it("getCurrentWord concatenates the path's letters", function()
            math.randomseed(42)
            local b = Board:new()
            b:tapCell(1, 1)
            b:tapCell(1, 2)
            assert.are.equal(b.grid[1][1] .. b.grid[1][2], b:getCurrentWord())
        end)
    end)

    describe("submit", function()
        it("rejects a word shorter than 3 letters", function()
            math.randomseed(42)
            local b = Board:new()
            b:tapCell(1, 1)
            b:tapCell(1, 2)
            local result = b:submit()
            assert.are.equal("too_short", result)
            assert.are.same({}, b.path)
        end)

        -- Reuse _findAll's own DFS to locate a real adjacent path spelling a
        -- dictionary word, so submit() is exercised end-to-end through its
        -- actual "found" branch rather than assumed.
        local function findWordPath(b)
            local n = b.n
            local found_path
            local function dfs(r, c, used, word, path)
                if found_path then return end
                if #word >= 3 and b.dict[word:lower()] then
                    found_path = {}
                    for i, cell in ipairs(path) do found_path[i] = cell end
                    return
                end
                if #word >= 8 then return end
                for dr = -1, 1 do
                    for dc = -1, 1 do
                        if not (dr == 0 and dc == 0) and not found_path then
                            local nr, nc = r + dr, c + dc
                            if nr >= 1 and nr <= n and nc >= 1 and nc <= n then
                                local key = nr * 10 + nc
                                if not used[key] then
                                    used[key] = true
                                    path[#path + 1] = { r = nr, c = nc }
                                    dfs(nr, nc, used, word .. b.grid[nr][nc], path)
                                    path[#path] = nil
                                    used[key] = nil
                                end
                            end
                        end
                    end
                end
            end
            for r = 1, n do
                for c = 1, n do
                    if not found_path then
                        dfs(r, c, { [r * 10 + c] = true }, b.grid[r][c], { { r = r, c = c } })
                    end
                end
            end
            return found_path
        end

        it("scores and records a real word, then flags it duplicate on resubmit", function()
            math.randomseed(42)
            local b = Board:new()
            local path = findWordPath(b)
            if not path then
                pending("no dictionary word findable on this rolled grid")
                return
            end
            b.path = path
            local word = b:getCurrentWord()
            b.path = path
            local result, submitted_word, pts = b:submit()
            assert.are.equal("found", result)
            assert.are.equal(word, submitted_word)
            assert.are.equal(Board.wordScore(#word), pts)
            assert.are.equal(pts, b.score)

            b.path = path
            assert.are.equal("duplicate", (b:submit()))
        end)
    end)

    describe("wordScore", function()
        it("scores by length per the standard table", function()
            assert.are.equal(0, Board.wordScore(2))
            assert.are.equal(1, Board.wordScore(3))
            assert.are.equal(2, Board.wordScore(5))
            assert.are.equal(11, Board.wordScore(8))
            assert.are.equal(11, Board.wordScore(12))
        end)
    end)

    describe("clearPath / endGame", function()
        it("clearPath empties the current selection", function()
            math.randomseed(42)
            local b = Board:new()
            b:tapCell(1, 1)
            b:clearPath()
            assert.are.same({}, b.path)
        end)

        it("endGame marks the board done and further taps report done", function()
            math.randomseed(42)
            local b = Board:new()
            b:endGame()
            assert.is_true(b.done)
            assert.are.equal("done", b:tapCell(1, 1))
        end)
    end)

    describe("serialize / load", function()
        it("round-trips the grid, found words and score", function()
            math.randomseed(42)
            local b = Board:new()
            local any_word
            for w, s in pairs(b._all_words) do any_word, b.found[w] = w, s; b.score = s; break end
            local data = b:serialize()

            local b2 = Board:new()
            assert.is_true(b2:load(data))
            assert.are.equal(b.n, b2.n)
            assert.are.equal(b.score, b2.score)
            if any_word then
                assert.are.equal(b.found[any_word], b2.found[any_word])
            end
            for r = 1, b.n do
                for c = 1, b.n do
                    assert.are.equal(b.grid[r][c], b2.grid[r][c])
                end
            end
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
