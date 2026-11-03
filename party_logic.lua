-- party_logic.lua — Boggle's "· multiplayer" mode, without any UI.
--
-- Everyone writes their words on paper while the reader shows the grid and
-- the countdown. At the reveal, players read their lists aloud and cross out
-- every word someone else also found. Then, player by player, the reader
-- tallies what is left: one tap per remaining word, on its length (3–4, 5,
-- 6, 7, 8+), and adds up the standard Boggle points. A match is N rounds.
--
-- A match is plain data (safe for the settings file):
--   { scores = <party.lua scores>, rounds = N, round = k,
--     phase  = "ready" | "playing" | "scoring" | "over",
--     tally  = { [player] = { count per bucket } },   -- while scoring
--     scorer = player being tallied, undo = { actions },
--     gains  = { points of the last finished round, per player } }
-- `round` is the round being played (1-based); scores.round counts the
-- rounds already scored.

local Party = require("party")

local Logic = {}

-- Word lengths a player taps while tallying, with the standard Boggle points
-- (board.lua's wordScore: 3 and 4 letters = 1, 5 = 2, 6 = 3, 7 = 5, 8+ = 11).
Logic.BUCKETS = {
    { label = "3–4", pts = 1 },
    { label = "5",   pts = 2 },
    { label = "6",   pts = 3 },
    { label = "7",   pts = 5 },
    { label = "8+",  pts = 11 },
}

-- Countdown choices, as boggleparty offered them (seconds).
Logic.DURATIONS        = { 120, 180, 240, 300 }
Logic.DEFAULT_DURATION = 180
Logic.ROUNDS           = { 1, 2, 3, 4, 5, 6, 8, 10 }
Logic.DEFAULT_ROUNDS   = 3

-- Every setting key of the multiplayer mode in boggle's settings file (the
-- solo game keeps "lang" and "state"). party_count / party_players are
-- party.lua's.
Logic.PARTY_KEYS = {
    "party_lang", "party_duration", "party_show_timer", "party_rounds",
    "party_state", "party_count", "party_players",
}

function Logic.bucketOf(len)
    if len <= 4 then return 1 end
    if len >= 8 then return 5 end
    return len - 3
end

local function emptyCounts()
    local t = {}
    for b = 1, #Logic.BUCKETS do t[b] = 0 end
    return t
end

-- Points of one player's tally.
function Logic.points(counts)
    local sum = 0
    for b, def in ipairs(Logic.BUCKETS) do
        sum = sum + (counts and counts[b] or 0) * def.pts
    end
    return sum
end

function Logic.words(counts)
    local n = 0
    for b = 1, #Logic.BUCKETS do n = n + (counts and counts[b] or 0) end
    return n
end

-- ---------------------------------------------------------------------------
-- Match
-- ---------------------------------------------------------------------------

function Logic.newMatch(names, rounds)
    return {
        scores = Party.newScores(names),
        rounds = math.max(1, tonumber(rounds) or Logic.DEFAULT_ROUNDS),
        round  = 1,
        phase  = "ready",
    }
end

function Logic.startPlaying(m)
    if m.phase ~= "ready" then return false end
    m.phase = "playing"
    m.gains = nil
    return true
end

-- Time is up (or Solutions): the tally of the first player starts.
function Logic.startScoring(m)
    if m.phase ~= "playing" then return false end
    m.phase  = "scoring"
    m.tally  = {}
    for i = 1, #m.scores.names do m.tally[i] = emptyCounts() end
    m.scorer = 1
    m.undo   = {}
    return true
end

-- One more remaining word of bucket b for the player being tallied.
function Logic.tap(m, b)
    if m.phase ~= "scoring" or not Logic.BUCKETS[b] then return false end
    local counts = m.tally[m.scorer]
    counts[b] = counts[b] + 1
    m.undo[#m.undo + 1] = { "tap", m.scorer, b }
    return true
end

-- Undoes the last tap, or goes back to the previous player when the current
-- one has no tap yet (the last action was "Next player").
function Logic.undo(m)
    if m.phase ~= "scoring" then return false end
    local last = table.remove(m.undo)
    if not last then return false end
    if last[1] == "tap" then
        local counts = m.tally[last[2]]
        counts[last[3]] = math.max(0, counts[last[3]] - 1)
    end
    m.scorer = last[2]
    return true
end

function Logic.isLastScorer(m)
    return m.scorer == #m.scores.names
end

-- Next player, or, after the last one, the round's points go to the scores.
-- Returns "next", "round" (the next round is ready) or "over" (match over).
function Logic.nextPlayer(m)
    if m.phase ~= "scoring" then return nil end
    if not Logic.isLastScorer(m) then
        m.undo[#m.undo + 1] = { "next", m.scorer }
        m.scorer = m.scorer + 1
        return "next"
    end
    m.gains = {}
    for i = 1, #m.scores.names do
        m.gains[i] = Logic.points(m.tally[i])
        Party.award(m.scores, i, m.gains[i])
    end
    Party.nextRound(m.scores)
    m.tally, m.scorer, m.undo = nil, nil, nil
    if m.round >= m.rounds then
        m.phase = "over"
        return "over"
    end
    m.round = m.round + 1
    m.phase = "ready"
    return "round"
end

function Logic.isOver(m)
    return m.phase == "over"
end

-- "Alice +7 · Bob +3": the points of the round just scored.
function Logic.gainsText(m)
    if not m.gains then return "" end
    local parts = {}
    for i, s in ipairs(m.scores.names) do
        parts[i] = s .. " +" .. (m.gains[i] or 0)
    end
    return table.concat(parts, " · ")
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

local function copyList(t)
    local c = {}
    for i, v in ipairs(t or {}) do
        c[i] = type(v) == "table" and copyList(v) or v
    end
    return c
end

function Logic.serialize(m)
    return {
        scores = Party.copyScores(m.scores),
        rounds = m.rounds,
        round  = m.round,
        phase  = m.phase,
        tally  = m.tally and copyList(m.tally) or nil,
        scorer = m.scorer,
        undo   = m.undo and copyList(m.undo) or nil,
        gains  = m.gains and copyList(m.gains) or nil,
    }
end

local PHASES = { ready = true, playing = true, scoring = true, over = true }

-- A saved match, or nil when it is unusable.
function Logic.restore(t)
    if type(t) ~= "table" or not PHASES[t.phase] then return nil end
    local scores = Party.restoreScores(t.scores)
    if not scores then return nil end
    local n = #scores.names
    local m = {
        scores = scores,
        rounds = math.max(1, tonumber(t.rounds) or Logic.DEFAULT_ROUNDS),
        round  = math.max(1, tonumber(t.round) or 1),
        phase  = t.phase,
        gains  = type(t.gains) == "table" and copyList(t.gains) or nil,
    }
    if m.phase == "scoring" then
        if type(t.tally) ~= "table" or #t.tally ~= n then return nil end
        m.tally = {}
        for i = 1, n do
            m.tally[i] = emptyCounts()
            for b = 1, #Logic.BUCKETS do
                m.tally[i][b] = math.max(0, tonumber(t.tally[i] and t.tally[i][b]) or 0)
            end
        end
        local s = tonumber(t.scorer) or 1
        m.scorer = math.max(1, math.min(n, s))
        m.undo   = type(t.undo) == "table" and copyList(t.undo) or {}
    end
    return m
end

-- ---------------------------------------------------------------------------
-- Migration from boggleparty.koplugin (Boggle Party, retired: it is now this
-- mode). Its settings file (settings/boggleparty.lua) held `lang` ("en" or
-- "fr"), `duration` (seconds) and `show_timer`; its `state` only repeated
-- the first two, it never restored a grid.
--
-- has_party: boggle already has a multiplayer setting (its own choice wins).
-- bp: boggleparty's settings table, or nil when the file does not exist.
-- Returns { key = value } for boggle's party keys, or nil to import nothing.
-- ---------------------------------------------------------------------------

function Logic.migrate(has_party, bp)
    if has_party or type(bp) ~= "table" then return nil end
    local out, any = {}, false
    if bp.lang == "en" or bp.lang == "fr" then
        out.party_lang = bp.lang; any = true
    end
    local d = tonumber(bp.duration)
    if d then
        for _i, ok in ipairs(Logic.DURATIONS) do
            if d == ok then out.party_duration = d; any = true end
        end
    end
    if type(bp.show_timer) == "boolean" then
        out.party_show_timer = bp.show_timer; any = true
    end
    return any and out or nil
end

return Logic
