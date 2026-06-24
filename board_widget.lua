local Blitbuffer     = require("ffi/blitbuffer")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")

local gwb      = require("grid_widget_base")
local drawLine = gwb.drawLine

local C_BG      = Blitbuffer.COLOR_WHITE
local C_FG      = Blitbuffer.COLOR_BLACK
local C_GRID    = Blitbuffer.COLOR_GRAY_9
local C_TILE    = Blitbuffer.COLOR_GRAY_E
local C_SEL     = Blitbuffer.COLOR_GRAY_6
local C_LAST    = Blitbuffer.COLOR_GRAY_4
local C_BORDER  = Blitbuffer.COLOR_BLACK
local C_TEXT    = Blitbuffer.COLOR_BLACK
local C_SEL_TXT = Blitbuffer.COLOR_WHITE

-- ---------------------------------------------------------------------------
-- BoggleBoardWidget
-- ---------------------------------------------------------------------------

local BoggleBoardWidget = InputContainer:extend{
    board      = nil,
    max_width  = 0,
    max_height = 0,
    onCellTap  = nil,
}

function BoggleBoardWidget:init()
    local n    = self.board.n
    local cell = math.floor(math.min(self.max_width / n, self.max_height / n))
    cell = math.max(cell, 20)
    self.cell = cell
    self.w    = cell * n
    self.h    = cell * n
    self.dimen = Geom:new{ w = self.w, h = self.h }

    local fs = math.max(10, math.floor(cell * 0.6))
    self.letter_face = Font:getFace("cfont", fs)
    local ord_fs = math.max(6, math.floor(cell * 0.3))
    self.ord_face = Font:getFace("smallinfofont", ord_fs)

    self.paint_rect = nil

    self.ges_events = {
        CellTap = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

local function centeredText(bb, text, face, cx, cy, color)
    local m = RenderText:sizeUtf8Text(0, cx * 2, face, text, true, false)
    local tx = cx - math.floor(m.x / 2)
    local ty = cy - math.floor((m.y_bottom - m.y_top) / 2)
    RenderText:renderUtf8Text(bb, tx, ty, face, text, true, false, color or Blitbuffer.COLOR_BLACK)
end

function BoggleBoardWidget:onCellTap(ges)
    if not self.paint_rect then return end
    local lx = ges.pos.x - self.paint_rect.x
    local ly = ges.pos.y - self.paint_rect.y
    if lx < 0 or ly < 0 or lx >= self.w or ly >= self.h then return end
    local c = math.floor(lx / self.cell) + 1
    local r = math.floor(ly / self.cell) + 1
    local n = self.board.n
    if r >= 1 and r <= n and c >= 1 and c <= n then
        if self.onCellTap then self.onCellTap(r, c) end
    end
    return true
end

function BoggleBoardWidget:refresh()
    UIManager:setDirty(self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

function BoggleBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local board = self.board
    local n     = board.n
    local cell  = self.cell
    local thin  = 1

    bb:paintRect(x, y, self.w, self.h, C_BG)

    -- Build path lookup: cell key → order
    local path_order = {}
    for i, p in ipairs(board.path) do
        path_order[p.r * 100 + p.c] = i
    end
    local last_p = board.path[#board.path]

    for r = 1, n do
        for c = 1, n do
            local cx  = x + (c - 1) * cell
            local cy  = y + (r - 1) * cell
            local key = r * 100 + c
            local ord = path_order[key]
            local is_last = last_p and last_p.r == r and last_p.c == c

            local pad = math.max(2, math.floor(cell * 0.06))
            local bg  = is_last and C_LAST
                     or (ord and C_SEL)
                     or C_TILE
            bb:paintRect(cx + pad, cy + pad, cell - 2*pad, cell - 2*pad, bg)

            local tc = (ord or is_last) and C_SEL_TXT or C_TEXT
            centeredText(bb, board.grid[r][c], self.letter_face,
                cx + cell // 2, cy + cell // 2, tc)

            -- Show order number in top-left corner of selected cell
            if ord then
                local small_x = cx + pad + 2
                local small_y = cy + pad + 2
                RenderText:renderUtf8Text(bb, small_x, small_y + (self.ord_face.size or 8),
                    self.ord_face, tostring(ord), true, false, C_SEL_TXT)
            end
        end
    end

    -- Draw path lines connecting selected cells
    if #board.path >= 2 then
        for i = 1, #board.path - 1 do
            local p1 = board.path[i]
            local p2 = board.path[i + 1]
            local x1 = x + (p1.c - 1) * cell + cell // 2
            local y1 = y + (p1.r - 1) * cell + cell // 2
            local x2 = x + (p2.c - 1) * cell + cell // 2
            local y2 = y + (p2.r - 1) * cell + cell // 2
            -- Draw line from (x1,y1) to (x2,y2)
            local lw = math.max(1, math.floor(cell * 0.05))
            local steps = math.max(math.abs(x2 - x1), math.abs(y2 - y1))
            if steps > 0 then
                local dx = (x2 - x1) / steps
                local dy = (y2 - y1) / steps
                for s = 0, steps do
                    bb:paintRect(
                        math.floor(x1 + dx * s),
                        math.floor(y1 + dy * s),
                        lw, lw, C_BORDER)
                end
            end
        end
    end

    -- Grid lines
    for i = 0, n do
        drawLine(bb, x + i*cell, y,          thin, self.h, C_GRID)
        drawLine(bb, x,          y + i*cell, self.w, thin, C_GRID)
    end
    -- Border
    local bw = math.max(2, thin)
    drawLine(bb, x,              y,              self.w, bw, C_BORDER)
    drawLine(bb, x,              y + self.h - bw, self.w, bw, C_BORDER)
    drawLine(bb, x,              y,              bw, self.h, C_BORDER)
    drawLine(bb, x + self.w - bw, y,             bw, self.h, C_BORDER)
end

return BoggleBoardWidget
