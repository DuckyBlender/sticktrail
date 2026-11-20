-- StickTrail logger. Special Function: <arm switch> -> Lua Script -> stlog.
-- Each arm writes /LOGS/stNNN.csv: t_ms,yaw,pitch,throttle,roll (sticks -1024..1024, t_ms from arm).

local PERIOD = 5   -- ticks (10 ms) between samples: 5 = 20 Hz
local FLUSH = 100  -- ticks between SD writes (buffer ~1 s in RAM)
local GAP = 50     -- no run() for this long = disarmed, next run() starts a new file

local ids
local buf = {}
local name
local idx = 0
local t0, last, nextS, lastFlush = 0, -10000, 0, 0
local dead = false -- SD error (card full?): stop quietly, never throw

local function flush()
  if not name or #buf == 0 then return end
  local f = io.open(name, "a")
  if not f then dead = true; buf = {}; return end
  io.write(f, table.concat(buf))
  io.close(f) -- close every burst: a power loss costs at most ~1 s
  buf = {}
end

local function newFile()
  for i = idx + 1, 999 do
    local n = string.format("/LOGS/st%03d.csv", i)
    local f = io.open(n, "r")
    if not f then
      idx, name = i, n
      return true
    end
    io.close(f)
  end
  return false
end

local function run()
  if dead then return end
  local now = getTime()
  if now - last > GAP then -- just armed
    flush()
    if not ids then
      ids = {}
      for i, n in ipairs({ "rud", "ele", "thr", "ail" }) do -- EdgeTX source names = yaw, pitch, throttle, roll
        local fi = getFieldInfo(n)
        ids[i] = fi and fi.id or n
      end
    end
    name = nil
    if not newFile() then dead = true; return end
    t0, nextS, lastFlush = now, now, now
    buf = { "t_ms,yaw,pitch,throttle,roll\n" }
  end
  last = now
  if now >= nextS then
    buf[#buf + 1] = string.format("%d,%d,%d,%d,%d\n", (now - t0) * 10,
      getValue(ids[1]), getValue(ids[2]), getValue(ids[3]), getValue(ids[4]))
    nextS = nextS + PERIOD
    if nextS <= now then nextS = now + PERIOD end -- fell behind: skip, don't burst
  end
  if now - lastFlush >= FLUSH then
    flush()
    lastFlush = now
  end
end

-- called while the switch is off (if the firmware supports it): write the tail right away
local function background()
  if not dead then flush() end
end

return { run = run, background = background }
