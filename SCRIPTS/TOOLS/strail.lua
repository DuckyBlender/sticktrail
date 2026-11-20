-- TNS|StickTrail|TNE
-- StickTrail: draws live stick movement as trails. EdgeTX, 128x64 B&W radios.
-- ENTER = open menu / edit value, wheel = move / change, EXIT = back / quit.

local STICK_MODE = 2 -- 1..4, set to your radio's stick mode
local CFG = "/SCRIPTS/TOOLS/strail.cfg"
local CFG_VER = 2
local MAXLEN = 48
local W, H = LCD_W, LCD_H
local floor, abs, min, max = math.floor, math.abs, math.min, math.max

-- per-style params: len, size, taper, tail, soft, shape, head, curve
local NAMES = { "Ribbon", "Beads", "Comet", "Thread", "Rings", "User 1", "User 2", "User 3" }
local DEFAULTS = {
  { 24, 2, 1, 100, 5, 1, 0, 1 },
  { 12, 3, 1, 80, 3, 2, 0, 0 },
  { 14, 6, 2, 100, 4, 1, 1, 1 },
  { 30, 1, 0, 0, 6, 1, 1, 1 },
  { 10, 5, 1, 60, 3, 3, 0, 0 },
  { 16, 4, 2, 100, 4, 1, 0, 1 },
  { 16, 4, 2, 100, 4, 1, 0, 1 },
  { 16, 4, 2, 100, 4, 1, 0, 1 },
}
local NP = 8
local P = {}                 -- P[style][param]
local G = { 3, 0, 0, 0 }     -- style, sticks, frame, invert

-- menu items: label, global?, index, min, max, step, value names
local ITEMS = {
  { "Style", true, 1, 1, #NAMES, 1, NAMES },
  { "Len", false, 1, 4, MAXLEN, 2 },
  { "Size", false, 2, 1, 8, 1 },
  { "Taper", false, 3, 0, 2, 1, { [0] = "None", "Linear", "Smooth" } },
  { "Tail", false, 4, 0, 100, 10 },
  { "Soft", false, 5, 0, 9, 1 },
  { "Shape", false, 6, 1, 3, 1, { "Ribbon", "Beads", "Rings" } },
  { "Curve", false, 8, 0, 2, 1, { [0] = "Off", "Spline", "Bezier" } },
  { "Head", false, 7, 0, 3, 1, { [0] = "Off", "Dot", "Ring", "Cross" } },
  { "Sticks", true, 2, 0, 3, 1, { [0] = "Both", "Left", "Right", "Overlay" } },
  { "Frame", true, 3, 0, 2, 1, { [0] = "Off", "Box", "Cross" } },
  { "Invert", true, 4, 0, 1, 1, { [0] = "Off", "On" } },
  { "Reset", nil, 0, 0, 0, 0 },
}
local NI = #ITEMS
local ROWS = 7

local menu, edit, sel, top = false, false, 1, 1
local src = {}               -- field ids: lx, ly, rx, ry
local bx, by = { {}, {} }, { {}, {} }
local head = 0
local sx, sy = { 0, 0 }, { 0, 0 }
local t0

local function resetStyle(s)
  P[s] = {}
  for k = 1, NP do P[s][k] = DEFAULTS[s][k] end
end

local function save()
  local f = io.open(CFG, "w")
  if not f then return end
  local t = { CFG_VER, G[1], G[2], G[3], G[4] }
  for s = 1, #NAMES do
    for k = 1, NP do t[#t + 1] = P[s][k] end
  end
  io.write(f, table.concat(t, ","))
  io.close(f)
end

local function load()
  for s = 1, #NAMES do resetStyle(s) end
  local f = io.open(CFG, "r")
  if not f then return end
  local str = io.read(f, 512)
  io.close(f)
  local n = {}
  for v in string.gmatch(str or "", "%d+") do n[#n + 1] = tonumber(v) end
  if n[1] ~= CFG_VER or #n ~= 5 + #NAMES * NP then return end
  local function clamp(it, v)
    if v < it[4] or v > it[5] then return nil end
    return v
  end
  for _, it in ipairs(ITEMS) do
    if it[2] == true then
      G[it[3]] = clamp(it, n[1 + it[3]]) or G[it[3]]
    elseif it[2] == false then
      for s = 1, #NAMES do
        P[s][it[3]] = clamp(it, n[5 + (s - 1) * NP + it[3]]) or P[s][it[3]]
      end
    end
  end
end

local function init()
  local names = ({
    { "rud", "ele", "ail", "thr" },
    { "rud", "thr", "ail", "ele" },
    { "ail", "ele", "rud", "thr" },
    { "ail", "thr", "rud", "ele" },
  })[STICK_MODE] or { "rud", "thr", "ail", "ele" }
  for i = 1, 4 do
    local fi = getFieldInfo(names[i])
    src[i] = fi and fi.id or names[i]
  end
  for s = 1, 2 do
    for i = 1, MAXLEN do bx[s][i] = 0; by[s][i] = 0 end
  end
  load()
  t0 = getTime()
end

-- drawing primitives (FORCE so overlapping strokes never XOR each other out)
local function dot(x, y)
  lcd.drawLine(x, y, x, y, SOLID, FORCE)
end

local function blob(x, y, w)
  if w <= 1 then
    dot(x, y)
  elseif w < 4 then
    local o = floor(w / 2)
    lcd.drawFilledRectangle(x - o, y - o, w, w, FORCE)
  else -- rounded
    local o = floor(w / 2)
    lcd.drawFilledRectangle(x - o + 1, y - o, w - 2, w, FORCE)
    lcd.drawFilledRectangle(x - o, y - o + 1, w, w - 2, FORCE)
  end
end

local function ring(x, y, w)
  if w < 3 then
    blob(x, y, w)
  else
    local o = floor(w / 2)
    lcd.drawRectangle(x - o, y - o, w, w, FORCE)
  end
end

local function seg(x1, y1, x2, y2, w)
  if w <= 1 then
    lcd.drawLine(x1, y1, x2, y2, SOLID, FORCE)
    return
  end
  local o = -floor(w / 2)
  if abs(x2 - x1) >= abs(y2 - y1) then
    for i = o, o + w - 1 do lcd.drawLine(x1, y1 + i, x2, y2 + i, SOLID, FORCE) end
  else
    for i = o, o + w - 1 do lcd.drawLine(x1 + i, y1, x2 + i, y2, SOLID, FORCE) end
  end
end

local QX, QY, QW = {}, {}, {} -- trail in pixels, [0] = newest
local lx, ly, lw               -- pen position for joined shapes

local function lineTo(x, y, w)
  x, y = floor(x + 0.5), floor(y + 0.5)
  if x == lx and y == ly then return end
  seg(lx, ly, x, y, lw)
  if lw >= 3 then blob(x, y, w) end
  lx, ly, lw = x, y, w
end

-- sub-pieces per sample gap: only fast moves (long gaps) get split
local function steps(d)
  local n = floor(d / 6) + 1
  return n > 4 and 4 or n
end

-- Catmull-Rom: passes through b (t=0) and c (t=1), bends using neighbours a and d
local function cr(a, b, c, d, t)
  return b + 0.5 * t * (c - a + t * (2 * a - 5 * b + 4 * c - d + t * (3 * b - a - 3 * c + d)))
end

local function drawTrail(s, cx, cy, r, p)
  local len, size, taper, tail, shape, curve = p[1], p[2], p[3], p[4] / 100, p[6], p[8]
  local X, Y = bx[s], by[s]
  for i = 0, len - 1 do
    local idx = (head - i - 1) % MAXLEN + 1
    local x = cx + floor(X[idx] * r / 1024 + 0.5)
    local y = cy - floor(Y[idx] * r / 1024 + 0.5)
    local w = size
    if taper ~= 0 and len > 1 then
      local t = i / (len - 1)
      if taper == 2 then t = t * t * (3 - 2 * t) end
      w = floor(size * (1 - t * tail) + 0.5)
      if w < 1 then w = 1 end
    end
    QX[i], QY[i], QW[i] = x, y, w
    if shape == 2 then
      blob(x, y, w)
    elseif shape == 3 then
      ring(x, y, w)
    end
  end
  if shape == 1 then
    lx, ly, lw = QX[0], QY[0], QW[0]
    blob(lx, ly, lw) -- always draw newest point: still stick = zero-length pieces are skipped
    for k = 1, len - 1 do
      local x1, y1, w1, x2, y2, w2 = QX[k - 1], QY[k - 1], QW[k - 1], QX[k], QY[k], QW[k]
      if curve == 1 then
        local x0, y0, x3, y3 = x1, y1, x2, y2
        if k > 1 then x0, y0 = QX[k - 2], QY[k - 2] end
        if k < len - 1 then x3, y3 = QX[k + 1], QY[k + 1] end
        local n = steps(abs(x2 - x1) + abs(y2 - y1))
        for j = 1, n do
          local t = j / n
          -- clamp: overshoot on hard reversals must not leave the stick box
          local qx = max(cx - r, min(cx + r, cr(x0, x1, x2, x3, t)))
          local qy = max(cy - r, min(cy + r, cr(y0, y1, y2, y3, t)))
          lineTo(qx, qy, floor(w1 + (w2 - w1) * t + 0.5))
        end
      elseif curve == 2 then
        -- quadratic Bezier between gap midpoints, sample as control point:
        -- rounds corners, never overshoots, but cuts slightly inside the samples
        local ax, ay, ex, ey = x1, y1, x2, y2
        if k > 1 then ax, ay = (x1 + x2) / 2, (y1 + y2) / 2 end
        if k < len - 1 then ex, ey = (x2 + QX[k + 1]) / 2, (y2 + QY[k + 1]) / 2 end
        local n = steps(abs(x2 - ax) + abs(y2 - ay) + abs(ex - x2) + abs(ey - y2))
        for j = 1, n do
          local t = j / n
          local u = 1 - t
          lineTo(u * u * ax + 2 * u * t * x2 + t * t * ex, u * u * ay + 2 * u * t * y2 + t * t * ey,
            floor(w1 + (w2 - w1) * t + 0.5))
        end
      else
        lineTo(x2, y2, w2)
      end
    end
  end
  -- head marker
  local hx, hy = QX[0], QY[0]
  if p[7] == 1 then
    blob(hx, hy, size + 2)
  elseif p[7] == 2 then
    lcd.drawRectangle(hx - 3, hy - 3, 7, 7, FORCE)
  elseif p[7] == 3 then
    lcd.drawLine(hx - 3, hy, hx + 3, hy, SOLID, FORCE)
    lcd.drawLine(hx, hy - 3, hx, hy + 3, SOLID, FORCE)
  end
end

local function drawFrame(cx, cy, r)
  if G[3] == 1 then
    lcd.drawRectangle(cx - r - 4, cy - r - 4, 2 * r + 9, 2 * r + 9, FORCE)
  elseif G[3] == 2 then
    lcd.drawLine(cx - 2, cy, cx + 2, cy, SOLID, FORCE)
    lcd.drawLine(cx, cy - 2, cx, cy + 2, SOLID, FORCE)
  end
end

local function getV(it)
  if it[2] then return G[it[3]] end
  return P[G[1]][it[3]]
end

local function setV(it, v)
  if it[2] then G[it[3]] = v else P[G[1]][it[3]] = v end
end

local function drawMenu()
  -- small font, no header: one highlight bar, hairline scrollbar
  local x0 = 66
  for row = 0, ROWS - 1 do
    local i = top + row
    local it = ITEMS[i]
    if not it then break end
    local y = 1 + row * 9
    local on = (i == sel)
    lcd.drawText(x0 + 2, y, it[1], SMLSIZE)
    if it[2] ~= nil then
      local v = getV(it)
      local txt = it[7] and it[7][v] or tostring(v)
      lcd.drawText(W - 4, y, txt, SMLSIZE + RIGHT + ((on and edit) and INVERS or 0))
    end
    if on and not edit then
      lcd.drawFilledRectangle(x0, y - 1, W - 3 - x0, 9) -- XOR bar over the row
    end
  end
  -- scrollbar: thumb shows which part of the list is visible
  local th = floor(H * ROWS / NI)
  local ty = floor((H - th) * (top - 1) / (NI - ROWS) + 0.5)
  lcd.drawLine(W - 1, ty, W - 1, ty + th - 1, SOLID, FORCE)
end

local function handle(event)
  local nxt = event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_INC
  local prv = event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_DEC
  if not menu then
    if event == EVT_VIRTUAL_ENTER then
      menu = true
    elseif event == EVT_VIRTUAL_EXIT then
      save()
      return 1
    end
    return 0
  end
  local it = ITEMS[sel]
  if edit then
    if nxt or prv then
      local v = getV(it) + (nxt and it[6] or -it[6])
      if it[7] then -- lists wrap
        if v > it[5] then v = it[4] elseif v < it[4] then v = it[5] end
      else
        if v > it[5] then v = it[5] elseif v < it[4] then v = it[4] end
      end
      setV(it, v)
    elseif event == EVT_VIRTUAL_ENTER or event == EVT_VIRTUAL_EXIT then
      edit = false
    end
  else
    if nxt then
      sel = sel % NI + 1
    elseif prv then
      sel = (sel - 2) % NI + 1
    elseif event == EVT_VIRTUAL_ENTER then
      if it[2] == nil then resetStyle(G[1]) else edit = true end
    elseif event == EVT_VIRTUAL_EXIT then
      menu = false
      save()
    end
    if sel < top then top = sel elseif sel > top + ROWS - 1 then top = sel - ROWS + 1 end
  end
  return 0
end

local function run(event)
  if handle(event) ~= 0 then return 1 end
  local p = P[G[1]]

  -- sample sticks with smoothing
  local a = (10 - p[5]) / 10
  head = head % MAXLEN + 1
  for s = 1, 2 do
    sx[s] = sx[s] + (getValue(src[s * 2 - 1]) - sx[s]) * a
    sy[s] = sy[s] + (getValue(src[s * 2]) - sy[s]) * a
    bx[s][head] = sx[s]
    by[s][head] = sy[s]
  end

  lcd.clear()
  if getTime() - t0 < 100 then
    lcd.drawText(8, 16, "StickTrail", DBLSIZE)
    lcd.drawText(20, 42, "ENTER = menu", SMLSIZE)
    return 0
  end

  local r, cy = 26, floor(H / 2)
  local mode = G[2]
  if menu or mode ~= 0 then
    local cx = menu and 31 or floor(W / 2)
    drawFrame(cx, cy, r)
    if mode ~= 2 then drawTrail(1, cx, cy, r, p) end
    if mode ~= 1 then drawTrail(2, cx, cy, r, p) end
  else
    local c1, c2 = floor(W / 4), floor(W * 3 / 4)
    drawFrame(c1, cy, r)
    drawFrame(c2, cy, r)
    drawTrail(1, c1, cy, r, p)
    drawTrail(2, c2, cy, r, p)
  end
  if menu then drawMenu() end
  if G[4] == 1 then lcd.drawFilledRectangle(0, 0, W, H) end -- XOR whole screen
  return 0
end

return { init = init, run = run }
