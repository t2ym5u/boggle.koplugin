-- Spec for party_logic.lua: Boggle's "· multiplayer" mode (tally, rounds,
-- save/restore, the import of Boggle Party's settings).
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

package.loaded["i18n"] = setmetatable({}, { __call = function(_, s) return s end })
package.loaded["ffi/util"] = { template = function(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end }

local Logic = dofile(DIR .. "party_logic.lua")

local function scoreRound(m, taps_per_player)
    assert.is_true(Logic.startPlaying(m))
    assert.is_true(Logic.startScoring(m))
    local result
    for i, taps in ipairs(taps_per_player) do
        assert.are.equal(i, m.scorer)
        for _, b in ipairs(taps) do assert.is_true(Logic.tap(m, b)) end
        result = Logic.nextPlayer(m)
    end
    return result
end

describe("buckets", function()
    it("match board.lua's standard Boggle scores", function()
        local Board = dofile(DIR .. "board.lua")
        for len = 3, 9 do
            local b = Logic.bucketOf(len)
            assert.are.equal(Board.wordScore(len), Logic.BUCKETS[b].pts, "length " .. len)
        end
    end)

    it("add up points and words", function()
        assert.are.equal(1 + 1 + 3 + 11, Logic.points({ 2, 0, 1, 0, 1 }))
        assert.are.equal(4, Logic.words({ 2, 0, 1, 0, 1 }))
        assert.are.equal(0, Logic.points(nil))
    end)
end)

describe("a match", function()
    it("plays N rounds, awards the tallies and ends", function()
        local m = Logic.newMatch({ "Alice", "Bob" }, 2)
        assert.are.equal("ready", m.phase)
        assert.are.equal("round", scoreRound(m, { { 1, 1, 2 }, { 5 } }))
        assert.are.same({ 4, 11 }, m.scores.points)
        assert.are.same({ 4, 11 }, m.gains)
        assert.are.equal("Alice +4 · Bob +11", Logic.gainsText(m))
        assert.are.equal(2, m.round)
        assert.are.equal(1, m.scores.round)
        assert.are.equal("ready", m.phase)
        assert.is_false(Logic.isOver(m))

        assert.are.equal("over", scoreRound(m, { { 4, 4, 4 }, {} }))
        assert.are.same({ 19, 11 }, m.scores.points)
        assert.are.equal(2, m.scores.round)
        assert.is_true(Logic.isOver(m))
        -- nothing moves once over
        assert.is_false(Logic.startPlaying(m))
        assert.is_nil(Logic.nextPlayer(m))
    end)

    it("refuses steps out of order", function()
        local m = Logic.newMatch({ "A", "B" }, 1)
        assert.is_false(Logic.startScoring(m))
        assert.is_false(Logic.tap(m, 1))
        assert.is_nil(Logic.nextPlayer(m))
        Logic.startPlaying(m)
        assert.is_false(Logic.startPlaying(m))
        Logic.startScoring(m)
        assert.is_false(Logic.tap(m, 9))
    end)

    it("undoes taps, then goes back to the previous player", function()
        local m = Logic.newMatch({ "A", "B", "C" }, 1)
        Logic.startPlaying(m); Logic.startScoring(m)
        Logic.tap(m, 2); Logic.tap(m, 3)
        assert.are.equal("next", Logic.nextPlayer(m))
        Logic.tap(m, 1)
        assert.is_true(Logic.undo(m))            -- B's tap
        assert.are.same({ 0, 0, 0, 0, 0 }, m.tally[2])
        assert.are.equal(2, m.scorer)
        assert.is_true(Logic.undo(m))            -- back to A
        assert.are.equal(1, m.scorer)
        assert.is_true(Logic.undo(m))            -- A's last tap
        assert.are.same({ 0, 1, 0, 0, 0 }, m.tally[1])
        assert.is_true(Logic.undo(m))
        assert.is_false(Logic.undo(m))           -- nothing left
        assert.are.equal(1, m.scorer)
    end)

    it("leaves a tie as equal points", function()
        local m = Logic.newMatch({ "A", "B" }, 1)
        assert.are.equal("over", scoreRound(m, { { 2 }, { 2 } }))
        assert.are.same({ 2, 2 }, m.scores.points)
    end)
end)

describe("save / restore", function()
    it("round-trips a match in the middle of the tally", function()
        local m = Logic.newMatch({ "Alice", "Bob" }, 3)
        scoreRound(m, { { 1 }, { 2 } })
        Logic.startPlaying(m); Logic.startScoring(m)
        Logic.tap(m, 5); Logic.nextPlayer(m); Logic.tap(m, 3)
        local saved = Logic.serialize(m)
        -- the copy does not follow later changes
        Logic.tap(m, 3)
        local r = Logic.restore(saved)
        assert.are.equal("scoring", r.phase)
        assert.are.equal(2, r.round)
        assert.are.equal(3, r.rounds)
        assert.are.equal(2, r.scorer)
        assert.are.same({ 1, 2 }, r.scores.points)
        assert.are.same({ 0, 0, 1, 0, 0 }, r.tally[2])
        assert.is_true(Logic.undo(r))
        assert.is_true(Logic.undo(r))
        assert.are.equal(1, r.scorer)
        assert.are.equal("next", Logic.nextPlayer(r))
        assert.are.equal("round", Logic.nextPlayer(r))
        assert.are.same({ 12, 2 }, r.scores.points)
    end)

    it("restores a finished match as over", function()
        local m = Logic.newMatch({ "A", "B" }, 1)
        scoreRound(m, { { 1 }, {} })
        local r = Logic.restore(Logic.serialize(m))
        assert.is_true(Logic.isOver(r))
        assert.are.same({ 1, 0 }, r.scores.points)
    end)

    it("rejects unusable saves", function()
        assert.is_nil(Logic.restore(nil))
        assert.is_nil(Logic.restore({ phase = "ready" }))
        assert.is_nil(Logic.restore({ phase = "bogus", scores = { names = { "A" }, points = { 0 } } }))
        assert.is_nil(Logic.restore({ phase = "scoring",
            scores = { names = { "A", "B" }, points = { 0, 0 } }, tally = { { 0 } } }))
        local ok = Logic.restore({ phase = "ready", scores = { names = { "A", "B" }, points = { 0, 0 } } })
        assert.are.equal(1, ok.round)
    end)
end)

describe("Boggle Party settings import", function()
    it("imports language, duration and timer choice", function()
        assert.are.same({ party_lang = "fr", party_duration = 240, party_show_timer = false },
            Logic.migrate(false, { lang = "fr", duration = 240, show_timer = false,
                                   state = { lang = "fr", duration = 240 } }))
    end)

    it("keeps boggle's own multiplayer settings", function()
        assert.is_nil(Logic.migrate(true, { lang = "fr", duration = 240 }))
    end)

    it("imports nothing without a Boggle Party file, or from garbage", function()
        assert.is_nil(Logic.migrate(false, nil))
        assert.is_nil(Logic.migrate(false, {}))
        assert.is_nil(Logic.migrate(false, { lang = "de", duration = 17, show_timer = "yes" }))
        assert.are.same({ party_duration = 120 }, Logic.migrate(false, { lang = "xx", duration = 120 }))
    end)
end)
