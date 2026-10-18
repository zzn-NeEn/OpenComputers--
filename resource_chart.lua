-- resource_chart.lua -- SELF-CONTAINED BUILD
-- GENERATED FILE. Edit resource_chart_modular.lua and the modules in lib/,
-- then rebuild with:
--   node tools/build_single.js
--
-- This single-file build is provided for easy installation on an OpenOS
-- computer. It is compatible with GTNH 2.9.0-beta-2 (OpenComputers 1.8.x,
-- Lua 5.2/5.3) and only uses documented OC APIs.

local __sources = {
  ["rc_util"] = [===[
-- rc_util.lua -- small, dependency-free helpers for the resource chart.
-- Kept Lua 5.2 / 5.3 compatible: no goto, no utf8 library, no bitwise operators.

local M = {}

local okComputer, computer = pcall(require, "computer")
if not okComputer then
  computer = { uptime = function() return os.clock() end }
end

local okUnicode, unicode = pcall(require, "unicode")
if not okUnicode then unicode = nil end

local function trimZeros(s)
  if s:find("%.") then
    s = s:gsub("(%..-)0+$", "%1")
    s = s:gsub("%.$", "")
  end
  return s
end

function M.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function M.sign(v)
  if v > 0 then return 1 end
  if v < 0 then return -1 end
  return 0
end

function M.round(v)
  if v >= 0 then return math.floor(v + 0.5) end
  return math.ceil(v - 0.5)
end

function M.isFinite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function M.formatCompact(v, precision)
  if not M.isFinite(v) then return "--" end
  if v == 0 then return "0" end

  local abs = math.abs(v)
  local suffixes = {
    { 1e15, "P" },
    { 1e12, "T" },
    { 1e9,  "B" },
    { 1e6,  "M" },
    { 1e3,  "K" },
  }

  for i = 1, #suffixes do
    local scale, suffix = suffixes[i][1], suffixes[i][2]
    if abs >= scale then
      local n = v / scale
      local s
      local a = math.abs(n)
      if a >= 100 then
        s = string.format("%.0f", n)
      elseif a >= 10 then
        s = string.format("%.1f", n)
      else
        s = string.format("%.2f", n)
      end
      return trimZeros(s) .. suffix
    end
  end

  local a = math.abs(v)
  if a >= 100 then
    return string.format("%.0f", v)
  elseif a >= 10 then
    return trimZeros(string.format("%.1f", v))
  elseif a >= 1 then
    return trimZeros(string.format("%.2f", v))
  elseif a >= 0.001 then
    return trimZeros(string.format("%.3f", v))
  end
  return string.format("%.2e", v)
end

function M.formatSigned(v)
  if not M.isFinite(v) then return "--" end
  if v > 0 then return "+" .. M.formatCompact(v) end
  return M.formatCompact(v)
end

function M.formatDelta(delta, base)
  if not M.isFinite(delta) then return "--" end
  local s = M.formatSigned(delta)
  if M.isFinite(base) and math.abs(base) > 1e-9 then
    local pct = delta / math.abs(base) * 100
    s = s .. " (" .. M.formatSigned(pct) .. "%)"
  end
  return s
end

function M.formatDuration(seconds, compact)
  if not M.isFinite(seconds) then return "--" end
  local neg = seconds < 0
  local s = math.floor(math.abs(seconds) + 0.5)
  local out

  if s < 60 then
    out = string.format("%ds", s)
  elseif s < 3600 then
    local m = math.floor(s / 60)
    local r = s % 60
    if compact or r == 0 then
      out = string.format("%dm", m)
    else
      out = string.format("%dm %02ds", m, r)
    end
  elseif s < 86400 then
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    if compact or m == 0 then
      out = string.format("%dh", h)
    else
      out = string.format("%dh %02dm", h, m)
    end
  else
    local d = math.floor(s / 86400)
    local h = math.floor((s % 86400) / 3600)
    if compact or h == 0 then
      out = string.format("%dd", d)
    else
      out = string.format("%dd %02dh", d, h)
    end
  end

  if neg then return "-" .. out end
  return out
end

function M.formatRelative(t, now, compact)
  if not M.isFinite(t) or not M.isFinite(now) then return "--" end
  local d = now - t
  if d <= 1 then return "now" end
  return "-" .. M.formatDuration(d, compact)
end

function M.formatClock(gameSeconds)
  if not M.isFinite(gameSeconds) then return "--:--" end
  local t = math.floor(gameSeconds)
  local day = math.floor(t / 86400) + 1
  local sod = t % 86400
  if sod < 0 then sod = sod + 86400 end
  local h = math.floor(sod / 3600)
  local m = math.floor((sod % 3600) / 60)
  return string.format("D%d %02d:%02d", day, h, m)
end

function M.gameNow()
  local ok, t = pcall(os.time)
  if ok and M.isFinite(t) then return t end
  return 0
end

function M.now()
  local ok, t = pcall(computer.uptime)
  if ok and M.isFinite(t) then return t end
  return os.clock()
end

function M.width(s)
  if s == nil then return 0 end
  s = tostring(s)
  if unicode and unicode.wlen then
    local ok, w = pcall(unicode.wlen, s)
    if ok and M.isFinite(w) then return w end
  end
  if unicode and unicode.charWidth then
    local total = 0
    local okLen, n = pcall(unicode.len, s)
    if okLen then
      for i = 1, n do
        local c = unicode.sub(s, i, i)
        local ok, w = pcall(unicode.charWidth, c)
        total = total + ((ok and w) or 1)
      end
      return total
    end
  end
  return #(s:gsub("[^\32-\126]", "?"))
end

local function rawTruncate(s, maxWidth)
  if maxWidth <= 0 then return "" end
  if unicode and unicode.sub and unicode.len then
    local out = {}
    local w = 0
    local okLen, n = pcall(unicode.len, s)
    if okLen then
      for i = 1, n do
        local c = unicode.sub(s, i, i)
        local cw = 1
        if unicode.charWidth then
          local ok, v = pcall(unicode.charWidth, c)
          if ok and v then cw = v end
        end
        if w + cw > maxWidth then break end
        out[#out + 1] = c
        w = w + cw
      end
      return table.concat(out)
    end
  end
  return s:sub(1, maxWidth)
end

function M.truncate(s, maxWidth)
  if s == nil then return "" end
  s = tostring(s)
  if maxWidth <= 0 then return "" end
  local w = M.width(s)
  if w <= maxWidth then return s end
  if maxWidth <= 2 then return string.rep(".", maxWidth) end
  return rawTruncate(s, maxWidth - 2) .. ".."
end

function M.sanitize(s)
  if s == nil then return "" end
  s = tostring(s)
  s = s:gsub("[\r\n\t]", " ")
  if not unicode then
    s = s:gsub("[^\32-\126]", "?")
  end
  return s
end

function M.pad(s, width, align)
  s = M.sanitize(s)
  local w = M.width(s)
  if w >= width then return M.truncate(s, width) end
  local gap = width - w
  if align == "right" then
    return string.rep(" ", gap) .. s
  elseif align == "center" then
    local left = math.floor(gap / 2)
    return string.rep(" ", left) .. s .. string.rep(" ", gap - left)
  end
  return s .. string.rep(" ", gap)
end

function M.lower(s)
  if s == nil then return "" end
  if unicode and unicode.lower then
    local ok, v = pcall(unicode.lower, s)
    if ok then return v end
  end
  return string.lower(s)
end

function M.trim(s)
  if s == nil then return "" end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.contains(haystack, needle)
  if needle == "" then return true end
  return string.find(M.lower(haystack), M.lower(needle), 1, true) ~= nil
end

function M.sanitizeFilename(s)
  if s == nil then return "resource" end
  s = tostring(s):gsub("[^%w%-_%.]", "_")
  s = s:gsub("_+", "_")
  if #s == 0 then return "resource" end
  if #s > 64 then s = s:sub(1, 64) end
  return s
end

function M.readAll(path)
  local ok, f = pcall(io.open, path, "rb")
  if not ok or not f then return nil, "cannot open " .. tostring(path) end
  local okRead, data = pcall(f.read, f, "*a")
  pcall(f.close, f)
  if not okRead then return nil, "cannot read " .. tostring(path) end
  return data
end

function M.writeAll(path, data)
  local ok, f = pcall(io.open, path, "wb")
  if not ok or not f then return false, "cannot open " .. tostring(path) end
  local okWrite, err = pcall(f.write, f, data)
  if okWrite then pcall(f.flush, f) end
  pcall(f.close, f)
  if not okWrite then return false, tostring(err) end
  return true
end

function M.deepcopy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local out = {}
  seen[v] = out
  for k, val in pairs(v) do
    out[M.deepcopy(k, seen)] = M.deepcopy(val, seen)
  end
  return out
end

function M.lowerBound(count, getTime, target)
  local lo, hi = 1, count
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local t = getTime(mid)
    if t < target then
      lo = mid + 1
    else
      hi = mid - 1
    end
  end
  return lo
end

function M.log(message)
  local ok, f = pcall(io.open, "/home/resource_chart.log", "a")
  if not ok or not f then return end
  local stamp = os.date("%Y-%m-%d %H:%M:%S")
  pcall(f.write, f, "[" .. tostring(stamp) .. "] " .. tostring(message) .. "\n")
  pcall(f.close, f)
end

return M

]===],
  ["rc_theme"] = [===[
-- rc_theme.lua -- palettes for 1-bit, 4-bit and 8-bit screens.
-- Colors are RGB values; OpenComputers approximates them on lower depths.
-- On 1-bit screens a separate monochrome theme is used.

local M = {}

local colorTheme = {
  mono = false,
  bg = 0x0B1016,
  panel = 0x111A23,
  panel2 = 0x16222D,
  panel3 = 0x1C2B38,
  border = 0x31485B,
  grid = 0x203140,
  grid2 = 0x2A4052,
  text = 0xE6EEF6,
  dim = 0x91A3B5,
  faint = 0x5D7285,
  accent = 0x46C8F2,
  accent2 = 0x7C6CFF,
  good = 0x45D483,
  bad = 0xFF6B6B,
  warn = 0xFFD166,
  area = 0x0E2B36,
  area2 = 0x102F3B,
  inverseBg = 0xD9E6F2,
  inverseText = 0x0B1016,
  selection = 0x1C3D4D,
  cursor = 0xF2F7FB,
  shadow = 0x061016,
}

local monoTheme = {
  mono = true,
  bg = 0x000000,
  panel = 0x000000,
  panel2 = 0x000000,
  panel3 = 0x000000,
  border = 0xFFFFFF,
  grid = 0x555555,
  grid2 = 0x888888,
  text = 0xFFFFFF,
  dim = 0xAAAAAA,
  faint = 0x666666,
  accent = 0xFFFFFF,
  accent2 = 0xFFFFFF,
  good = 0xFFFFFF,
  bad = 0xFFFFFF,
  warn = 0xFFFFFF,
  area = nil,
  area2 = nil,
  inverseBg = 0xFFFFFF,
  inverseText = 0x000000,
  selection = 0x333333,
  cursor = 0xFFFFFF,
  shadow = 0x000000,
}

function M.get(depth)
  if depth and depth <= 1 then
    return monoTheme
  end
  return colorTheme
end

function M.apply(gpu, theme)
  if gpu.setBackground then gpu.setBackground(theme.bg) end
  if gpu.setForeground then gpu.setForeground(theme.text) end
end

return M

]===],
  ["rc_chart"] = [===[
-- rc_chart.lua -- pure chart math (scale, ticks, interpolation, line rasterizing).
-- No OpenComputers calls live here, which keeps it easy to test.

local util = require("rc_util")

local M = {}

function M.niceStep(raw)
  if not util.isFinite(raw) or raw <= 0 then return 1 end
  local exp = math.floor(math.log(raw) / math.log(10))
  local base = 10 ^ exp
  local f = raw / base
  local n
  if f <= 1 then
    n = 1
  elseif f <= 2 then
    n = 2
  elseif f <= 5 then
    n = 5
  else
    n = 10
  end
  return n * base
end

-- Returns { lo, hi, step, ticks = { ... } }.
function M.scale(minValue, maxValue, maxTicks, includeZero)
  local lo = minValue
  local hi = maxValue
  if not util.isFinite(lo) or not util.isFinite(hi) then
    lo, hi = 0, 1
  end
  if lo > hi then lo, hi = hi, lo end

  if includeZero and lo > 0 then lo = 0 end
  if lo == hi then
    if lo == 0 then
      hi = 1
    else
      local span = math.abs(lo) * 0.15
      if span < 1 then span = 1 end
      lo = lo - span
      hi = hi + span
      if includeZero and lo > 0 then lo = 0 end
    end
  end

  local padding = (hi - lo) * 0.08
  lo = lo - padding
  hi = hi + padding
  if includeZero and minValue >= 0 and lo < 0 then lo = 0 end

  maxTicks = math.max(2, math.min(8, maxTicks or 4))
  local step = M.niceStep((hi - lo) / maxTicks)
  lo = math.floor(lo / step + 1e-9) * step
  hi = math.ceil(hi / step - 1e-9) * step
  if includeZero and minValue >= 0 and lo < 0 then lo = 0 end
  if hi <= lo then hi = lo + step end

  local ticks = {}
  local n = math.floor((hi - lo) / step + 0.5)
  for i = 0, n do
    local v = lo + i * step
    if math.abs(v) < step * 1e-7 then v = 0 end
    ticks[#ticks + 1] = v
  end
  if #ticks < 2 then
    ticks = { lo, lo + step }
    hi = lo + step
  end

  return { lo = lo, hi = hi, step = step, ticks = ticks }
end

local TIME_STEPS = {
  1, 2, 5, 10, 15, 30,
  60, 120, 300, 600, 900, 1800,
  3600, 7200, 10800, 21600, 43200, 86400,
  172800, 259200, 604800, 1209600, 2592000,
}

-- Choose a round tick interval and return times aligned to `now`.
-- Only ticks that fall inside [t0, t1] are returned.
function M.timeTicks(t0, t1, width, now)
  local range = t1 - t0
  if not util.isFinite(range) or range <= 0 then return {} end

  local maxTicks = math.max(2, math.min(7, math.floor(width / 10)))
  local step = TIME_STEPS[#TIME_STEPS]
  for i = 1, #TIME_STEPS do
    if range / TIME_STEPS[i] <= maxTicks then
      step = TIME_STEPS[i]
      break
    end
  end

  now = now or t1
  local ticks = {}
  local k = 0
  while true do
    local t = now - k * step
    if t < t0 - step * 0.001 then break end
    if t <= t1 + step * 0.001 and t >= t0 then
      ticks[#ticks + 1] = t
    end
    k = k + 1
    if k > 10000 then break end
  end
  table.sort(ticks)
  return ticks, step
end

function M.xFor(t, t0, t1, x1, x2)
  if t1 <= t0 then return x1 end
  return x1 + (t - t0) / (t1 - t0) * (x2 - x1)
end

function M.yFor(v, vmin, vmax, y1, y2)
  if vmax <= vmin then return (y1 + y2) / 2 end
  return y2 - (v - vmin) / (vmax - vmin) * (y2 - y1)
end

function M.nearestPoint(history, target)
  local count = history:count()
  if count == 0 then return nil end
  local idx = util.lowerBound(count, function(i) return history:timeAt(i) end, target)
  if idx > count then idx = count end
  if idx < 1 then idx = 1 end
  local t = history:timeAt(idx)
  if idx > 1 and math.abs(history:timeAt(idx - 1) - target) < math.abs(t - target) then
    idx = idx - 1
    t = history:timeAt(idx)
  end
  return history:valueAt(idx), t, idx
end

-- Linear interpolation, but only when the two surrounding samples are close
-- enough together. This keeps real data gaps visible instead of drawing a
-- straight line across them.
function M.interp(history, target, gapLimit)
  local count = history:count()
  if count == 0 then return nil end

  local idx = util.lowerBound(count, function(i) return history:timeAt(i) end, target)
  if idx <= count and math.abs(history:timeAt(idx) - target) < 1e-9 then
    return history:valueAt(idx)
  end

  local left = idx - 1
  local right = idx
  if left < 1 then
    left = 1
    if history:timeAt(1) - target > gapLimit then return nil end
    return history:valueAt(1)
  end
  if right > count then
    right = count
    if target - history:timeAt(count) > gapLimit then return nil end
    return history:valueAt(count)
  end

  local tl, tr = history:timeAt(left), history:timeAt(right)
  if tr - tl > gapLimit then return nil end
  local vl, vr = history:valueAt(left), history:valueAt(right)
  if tr == tl then return vr end
  local f = (target - tl) / (tr - tl)
  return vl + (vr - vl) * f
end

-- Build one column of the chart for each screen cell.
-- avg is used for the line; min/max preserve spikes in a dim envelope.
function M.aggregate(history, t0, t1, columns, gapLimit)
  local cols = {}
  for c = 1, columns do
    local t = t0 + (c - 0.5) / columns * (t1 - t0)
    local v = M.interp(history, t, gapLimit)
    if v ~= nil then
      cols[c] = { avg = v, min = v, max = v, n = 0, t = t }
    end
  end

  local count = history:count()
  if count == 0 then return cols, false end

  local first = util.lowerBound(count, function(i) return history:timeAt(i) end, t0) - 1
  local last = util.lowerBound(count, function(i) return history:timeAt(i) end, t1) + 1
  if first < 1 then first = 1 end
  if last > count then last = count end

  local has = false
  for i = first, last do
    local t, v = history:timeAt(i), history:valueAt(i)
    if t >= t0 - (t1 - t0) * 1e-6 and t <= t1 + (t1 - t0) * 1e-6 then
      local c = math.floor((t - t0) / (t1 - t0) * columns) + 1
      if c < 1 then c = 1 end
      if c > columns then c = columns end
      local col = cols[c]
      if not col then
        col = { avg = v, min = v, max = v, n = 0, t = t }
        cols[c] = col
      end
      if v < col.min then col.min = v end
      if v > col.max then col.max = v end
      col.n = col.n + 1
      has = true
    end
  end

  for c = 1, columns do
    local col = cols[c]
    if col and col.n == 0 then col.n = 1 end
  end
  return cols, has
end

-- Rasterize a line with characters that show its slope. The callback receives
-- 1-based screen coordinates and a one-character string.
function M.line(x0, y0, x1, y1, callback)
  x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
  local dx = x1 - x0
  local dy = y1 - y0
  local adx, ady = math.abs(dx), math.abs(dy)
  local ch
  if adx == 0 then
    ch = "|"
  elseif ady == 0 then
    ch = "-"
  elseif ady * 2 < adx then
    ch = "-"
  elseif adx * 2 < ady then
    ch = "|"
  elseif dx * dy > 0 then
    ch = "\\"
  else
    ch = "/"
  end

  local steps = math.max(adx, ady)
  if steps == 0 then
    callback(x0, y0, ch)
    return
  end

  local lastX, lastY
  for i = 0, steps do
    local x = math.floor(x0 + dx * i / steps + 0.5)
    local y = math.floor(y0 + dy * i / steps + 0.5)
    if x ~= lastX or y ~= lastY then
      callback(x, y, ch)
      lastX, lastY = x, y
    end
  end
end

function M.axisLabel(v)
  return util.formatCompact(v)
end

return M

]===],
  ["rc_history"] = [===[
-- rc_history.lua -- memory-friendly time series storage.
--
-- Points are stored in a flat array: { t1, v1, t2, v2, ... }.
-- A moving `head` index avoids O(n) table.remove() calls when old samples
-- are pruned. The active data can optionally be downsampled by averaging
-- time buckets, keeping RAM use bounded on small computers.

local util = require("rc_util")

local History = {}
History.__index = History

function History.new(opts)
  opts = opts or {}
  local self = setmetatable({}, History)
  self.p = {}
  self.head = 1
  self.maxPoints = math.max(32, opts.maxPoints or 3000)
  self.retention = math.max(60, opts.retention or 7 * 86400)
  self.lastT = nil
  self.lastV = nil
  self.avgSpacing = nil
  return self
end

function History:count()
  if #self.p < self.head then return 0 end
  return math.floor((#self.p - self.head) / 2) + 1
end

function History:timeAt(i)
  return self.p[self.head + (i - 1) * 2]
end

function History:valueAt(i)
  return self.p[self.head + (i - 1) * 2 + 1]
end

function History:firstTime()
  if self:count() == 0 then return nil end
  return self:timeAt(1)
end

function History:lastTime()
  local n = self:count()
  if n == 0 then return nil end
  return self:timeAt(n)
end

function History:lastValue()
  local n = self:count()
  if n == 0 then return nil end
  return self:valueAt(n)
end

function History:add(t, v)
  if not util.isFinite(t) or not util.isFinite(v) then return false end
  if self.lastT and t <= self.lastT then
    t = self.lastT + 0.001
  end

  if self.lastT then
    local dt = t - self.lastT
    if dt > 0 then
      if self.avgSpacing then
        self.avgSpacing = self.avgSpacing * 0.9 + dt * 0.1
      else
        self.avgSpacing = dt
      end
    end
  end

  self.p[#self.p + 1] = t
  self.p[#self.p + 1] = v
  self.lastT = t
  self.lastV = v

  if self:count() > self.maxPoints * 1.1 then
    self:downsample(self.maxPoints)
  end
  return true
end

function History:compact()
  local n = self:count()
  if n == 0 then
    self.p = {}
    self.head = 1
    return
  end
  local out = {}
  for i = 1, n do
    out[#out + 1] = self:timeAt(i)
    out[#out + 1] = self:valueAt(i)
  end
  self.p = out
  self.head = 1
end

function History:prune(now)
  local cutoff = now - self.retention
  local n = self:count()
  if n == 0 then return end

  local removed = 0
  while self:count() > 0 and self:timeAt(1) < cutoff do
    self.head = self.head + 2
    removed = removed + 1
  end

  if self:count() == 0 then
    self.p = {}
    self.head = 1
    self.lastT = nil
    self.lastV = nil
    self.avgSpacing = nil
    return
  end

  if removed > 0 and self.head > 2048 and self.head > #self.p * 0.5 then
    self:compact()
  end
end

function History:downsample(target)
  local n = self:count()
  target = math.max(16, target or self.maxPoints)
  if n <= target or n < 3 then return end

  local t0, t1 = self:timeAt(1), self:timeAt(n)
  local span = t1 - t0
  if span <= 0 then return end

  local buckets = target - 1
  local out = {}
  local cur = 1
  local bucketIndex = 0

  while cur <= n do
    bucketIndex = bucketIndex + 1
    local bucketStart = t0 + span * (bucketIndex - 1) / buckets
    local bucketEnd = t0 + span * bucketIndex / buckets
    local sum, count = 0, 0
    local firstT
    while cur <= n and (self:timeAt(cur) < bucketEnd or bucketIndex == buckets) do
      local t = self:timeAt(cur)
      if t >= bucketStart or bucketIndex == 1 then
        sum = sum + self:valueAt(cur)
        count = count + 1
        if not firstT then firstT = t end
      end
      cur = cur + 1
    end
    if count > 0 then
      out[#out + 1] = firstT
      out[#out + 1] = sum / count
    end
  end

  -- Always keep the newest sample exactly, so the "current" marker is honest.
  local lastT, lastV = self:timeAt(n), self:valueAt(n)
  if #out >= 2 then
    out[#out] = lastV
    out[#out - 1] = lastT
  else
    out = { lastT, lastV }
  end

  self.p = out
  self.head = 1
  self.lastT = lastT
  self.lastV = lastV
  local newCount = self:count()
  if newCount > 1 then
    self.avgSpacing = (self:timeAt(newCount) - self:timeAt(1)) / (newCount - 1)
  end
end

function History:visibleIndices(t0, t1)
  local n = self:count()
  if n == 0 then return 0, 0 end
  local first = util.lowerBound(n, function(i) return self:timeAt(i) end, t0)
  local last = util.lowerBound(n, function(i) return self:timeAt(i) end, t1 + 1e-6) - 1
  if first < 1 then first = 1 end
  if last > n then last = n end
  if first > last then return 0, 0 end
  return first, last
end

function History:stats(t0, t1)
  local first, last = self:visibleIndices(t0, t1)
  if first == 0 then return nil end

  local count = 0
  local minV, maxV = nil, nil
  local sum = 0
  local firstT, firstV, lastT, lastV

  for i = first, last do
    local t, v = self:timeAt(i), self:valueAt(i)
    if firstT == nil then
      firstT, firstV = t, v
    end
    lastT, lastV = t, v
    if minV == nil or v < minV then minV = v end
    if maxV == nil or v > maxV then maxV = v end
    sum = sum + v
    count = count + 1
  end

  return {
    count = count,
    firstT = firstT,
    lastT = lastT,
    firstV = firstV,
    lastV = lastV,
    minV = minV,
    maxV = maxV,
    avgV = count > 0 and (sum / count) or nil,
    delta = (firstV ~= nil and lastV ~= nil) and (lastV - firstV) or nil,
    span = (firstT and lastT) and (lastT - firstT) or 0,
    firstIndex = first,
    lastIndex = last,
  }
end

function History:gapLimit(window, sampleInterval, columns)
  local spacing = self.avgSpacing
  if not spacing or spacing <= 0 then
    spacing = sampleInterval or 1
  end
  return math.max(
    (sampleInterval or 1) * 3,
    spacing * 3,
    (window or 60) / math.max(1, columns or 1) * 2
  )
end

function History:serialize()
  local n = self:count()
  local out = {}
  for i = 1, n do
    out[#out + 1] = self:timeAt(i)
    out[#out + 1] = self:valueAt(i)
  end
  return out
end

function History:load(points)
  self.p = {}
  self.head = 1
  self.lastT = nil
  self.lastV = nil
  self.avgSpacing = nil

  if type(points) ~= "table" then return end

  local pairsList = {}
  for i = 1, #points - 1, 2 do
    local t, v = points[i], points[i + 1]
    if util.isFinite(t) and util.isFinite(v) then
      pairsList[#pairsList + 1] = { t, v }
    end
  end
  table.sort(pairsList, function(a, b) return a[1] < b[1] end)

  local lastT
  for i = 1, #pairsList do
    local t, v = pairsList[i][1], pairsList[i][2]
    if lastT == nil or t > lastT then
      self.p[#self.p + 1] = t
      self.p[#self.p + 1] = v
      lastT = t
    else
      -- Duplicate timestamps: keep the newest value.
      self.p[#self.p] = v
    end
  end

  local n = self:count()
  if n > 0 then
    self.lastT = self:timeAt(n)
    self.lastV = self:valueAt(n)
    if n > 1 then
      self.avgSpacing = (self.lastT - self:timeAt(1)) / (n - 1)
    end
  end
  if n > self.maxPoints * 1.1 then
    self:downsample(self.maxPoints)
  end
end

return History

]===],
  ["rc_store"] = [===[
-- rc_store.lua -- persistence for history and UI state.
-- Uses the OpenOS serialization library and plain files, no external deps.

local util = require("rc_util")

local okSer, serialization = pcall(require, "serialization")
if not okSer then serialization = nil end

local okText, textutils = pcall(require, "textutils")
if not okText then textutils = nil end

local M = {}
M.VERSION = 1

function M.defaultState()
  return {
    version = M.VERSION,
    savedAt = 0,
    clock = {
      lastMonitor = 0,
      lastUptime = 0,
      lastGame = 0,
    },
    selected = nil,
    window = 3600,
    zero = false,
    paused = false,
    resources = {},
  }
end

local function serialize(value)
  if serialization and serialization.serialize then
    local ok, data = pcall(serialization.serialize, value)
    if ok and type(data) == "string" then return data end
    return nil, tostring(data)
  end
  if textutils and textutils.serialize then
    local ok, data = pcall(textutils.serialize, value)
    if ok and type(data) == "string" then return data end
    return nil, tostring(data)
  end
  return nil, "no serialization library"
end

local function unserialize(data)
  if serialization and serialization.unserialize then
    local ok, value = pcall(serialization.unserialize, data)
    if ok then return value end
    return nil, tostring(value)
  end
  if textutils and textutils.unserialize then
    local ok, value = pcall(textutils.unserialize, data)
    if ok then return value end
    return nil, tostring(value)
  end
  return nil, "no serialization library"
end

local function validate(state)
  if type(state) ~= "table" then return nil, "not a table" end
  local version = tonumber(state.version) or 0
  if version > M.VERSION then
    return nil, "newer data format"
  end

  state.version = M.VERSION
  state.savedAt = tonumber(state.savedAt) or 0
  state.window = tonumber(state.window) or 3600
  if not util.isFinite(state.window) or state.window < 10 then state.window = 3600 end
  state.zero = state.zero == true
  state.paused = state.paused == true
  if type(state.resources) ~= "table" then state.resources = {} end
  if type(state.clock) ~= "table" then state.clock = {} end
  state.clock.lastMonitor = tonumber(state.clock.lastMonitor) or 0
  state.clock.lastUptime = tonumber(state.clock.lastUptime) or 0
  state.clock.lastGame = tonumber(state.clock.lastGame) or 0

  for key, entry in pairs(state.resources) do
    if type(entry) ~= "table" or type(entry.meta) ~= "table" then
      state.resources[key] = nil
    else
      entry.points = type(entry.points) == "table" and entry.points or {}
      entry.lastUsed = tonumber(entry.lastUsed) or 0
    end
  end

  return state
end

function M.load(path)
  local data, err = util.readAll(path)
  if not data then return nil, err or "missing" end
  local value, decodeErr = unserialize(data)
  if value == nil then return nil, decodeErr or "invalid data" end
  local state, validateErr = validate(value)
  if not state then return nil, validateErr or "invalid state" end
  return state
end

function M.save(path, state)
  state.version = M.VERSION
  local data, err = serialize(state)
  if not data then return false, err end

  local tmp = path .. ".tmp"
  local ok, writeErr = util.writeAll(tmp, data)
  if not ok then
    -- Last resort: write directly. Useful on read-only/odd filesystems.
    local ok2, err2 = util.writeAll(path, data)
    if ok2 then return true end
    return false, writeErr or err2
  end

  os.remove(path)
  local okRename = os.rename(tmp, path)
  if not okRename then
    local ok2, err2 = util.writeAll(path, data)
    os.remove(tmp)
    if ok2 then return true end
    return false, err2 or "rename failed"
  end
  return true
end

function M.quarantine(path)
  local backup = path .. ".bad"
  os.remove(backup)
  local ok = os.rename(path, backup)
  if ok then return backup end
  return nil
end

return M

]===],
  ["rc_sources"] = [===[
-- rc_sources.lua -- data providers.
--
-- Built-in providers:
--   * AE2 items  (me_controller / me_interface)
--   * AE2 fluids (me_controller / me_interface)
--   * AE2 stored power
--   * synthetic demo series (so the UI can be tested without an ME network)
--   * user-defined custom sources from rc_config.lua / resource_chart.cfg
--
-- Item history is keyed by unlocalized name + damage. NBT variants of the same
-- item are summed; this is intentional, because the AE2 OC API exposes NBT as
-- compressed bytes and treating every variant separately would make the picker
-- unreadable for most GTNH items.

local component = require("component")
local util = require("rc_util")

local Sources = {}
Sources.__index = Sources

local KIND_ORDER = { power = 1, item = 2, fluid = 3, custom = 4, demo = 5 }

local function shortAddress(address)
  if type(address) ~= "string" then return "?" end
  return address:sub(1, 4)
end

-- component.methods() returns method names as keys, and a boolean value that
-- indicates whether the method is *direct*. A value of false still means the
-- method exists; checking truthiness here would incorrectly reject AE2
-- components whose callbacks are not direct.
local function hasMethod(methods, name)
  return type(methods) == "table" and methods[name] ~= nil
end

local function newMeta(kind, key, label, unit, extra)
  local meta = {
    kind = kind,
    key = key,
    label = util.sanitize(label or key),
    unit = unit or "units",
  }
  if extra then
    for k, v in pairs(extra) do meta[k] = v end
  end
  return meta
end

function Sources.new(cfg)
  local self = setmetatable({}, Sources)
  self.cfg = cfg
  self.me = nil
  self.meAddress = nil
  self.meType = nil
  self.methods = nil
  self.lastError = nil
  self.scanError = nil
  self.cached = nil
  self.cachedAt = nil
  self.cacheTTL = 30

  self.demoEnabled = (cfg.demo == true) or (cfg.demo == "auto" and cfg.includeDemo ~= false)
  self:detect()
  return self
end

function Sources:detect(force)
  if self.me and not force then return true end

  local candidates = {}
  local function addCandidate(address, typ)
    if not address then return end
    local ok, methods = pcall(component.methods, address)
    if not ok or type(methods) ~= "table" then methods = {} end
    candidates[#candidates + 1] = {
      address = address,
      type = typ,
      methods = methods,
    }
  end

  if self.cfg.meAddress then
    local ok, typ = pcall(component.type, self.cfg.meAddress)
    if ok and typ then
      addCandidate(self.cfg.meAddress, typ)
    end
  end

  if #candidates == 0 then
    for address, typ in component.list() do
      if typ == "me_interface" then
        addCandidate(address, typ)
      end
    end
    for address, typ in component.list() do
      if typ == "me_controller" then
        addCandidate(address, typ)
      end
    end
  end

  local chosen = nil
  for i = 1, #candidates do
    local c = candidates[i]
    if c.type == "me_interface" or c.type == "me_controller" then
      local has = hasMethod(c.methods, "getItemsInNetwork")
        or hasMethod(c.methods, "getFluidsInNetwork")
        or hasMethod(c.methods, "getStoredPower")
      if not has then
        -- Fallback for components whose methods table is unavailable/empty.
        local okProxy, proxy = pcall(component.proxy, c.address)
        if okProxy and proxy then
          has = proxy.getItemsInNetwork ~= nil
            or proxy.getFluidsInNetwork ~= nil
            or proxy.getStoredPower ~= nil
        end
      end
      if has then
        chosen = c
        break
      end
    end
  end

  if not chosen then
    self.me = nil
    self.meAddress = nil
    self.meType = nil
    self.methods = nil
    self.cached = nil
    self.lastError = "no AE2 ME controller/interface"
    return false, self.lastError
  end

  local ok, proxy = pcall(component.proxy, chosen.address)
  if not ok or not proxy then
    self.me = nil
    self.lastError = "cannot proxy " .. tostring(chosen.address)
    return false, self.lastError
  end

  self.me = proxy
  self.meAddress = chosen.address
  self.meType = chosen.type
  self.methods = chosen.methods
  self.lastError = nil
  self.cached = nil
  return true
end

function Sources:refresh()
  self.cached = nil
  self:detect(true)
  return self:list(true)
end

function Sources:hasMethod(name)
  if hasMethod(self.methods, name) then return true end
  -- Some OC builds do not list every environment callback in
  -- component.methods(), even though the proxy exposes it. Fall back to the
  -- proxy field itself.
  return self.me ~= nil and self.me[name] ~= nil
end

function Sources:sourceName()
  if self.me then
    return self.meType .. " " .. shortAddress(self.meAddress)
  end
  return "demo"
end

function Sources:isAE2()
  return self.me ~= nil
end

function Sources:demoValue(key, t)
  local v, max
  if key == "demo:sine" then
    v = 600 + 260 * math.sin(t / 90) + 60 * math.sin(t / 13)
    max = 900
  elseif key == "demo:square" then
    v = (math.floor(t / 45) % 2 == 0) and 880 or 240
    max = 900
  elseif key == "demo:drift" then
    v = 1200 - (t % 3600) / 3 + 35 * math.sin(t / 7)
    max = 1300
  else
    local seed = math.floor(t / 15)
    local frac = math.abs(math.sin(seed * 12.9898) * 43758.5453) % 1
    v = 380 + frac * 260 + 25 * math.sin(t / 5)
    max = 700
  end
  return v, max
end

function Sources:addDemo(resources)
  local demos = {
    { key = "demo:sine", label = "Demo: sine wave", unit = "units" },
    { key = "demo:square", label = "Demo: square wave", unit = "units" },
    { key = "demo:drift", label = "Demo: drifting load", unit = "units" },
    { key = "demo:random", label = "Demo: noisy signal", unit = "units" },
  }
  for i = 1, #demos do
    resources[#resources + 1] = newMeta("demo", demos[i].key, demos[i].label, demos[i].unit)
  end
end

function Sources:addCustom(resources)
  local custom = self.cfg.customSources
  if type(custom) ~= "table" then return end
  for i = 1, #custom do
    local item = custom[i]
    if type(item) == "table" and type(item.key) == "string" and type(item.sample) == "function" then
      resources[#resources + 1] = newMeta(
        "custom",
        item.key,
        item.label or item.key,
        item.unit or "units",
        { sample = item.sample }
      )
    end
  end
end

function Sources:list(force)
  local now = util.now()
  if not force and self.cached and self.cachedAt and now - self.cachedAt < self.cacheTTL then
    return self.cached, self.scanError
  end

  if not self.me then self:detect(true) end

  local resources = {}
  local seen = {}
  self.scanError = nil

  local function put(meta, amount)
    local existing = seen[meta.key]
    if existing then
      existing.amount = (existing.amount or 0) + (amount or 0)
    else
      meta.amount = amount
      seen[meta.key] = meta
      resources[#resources + 1] = meta
    end
  end

  if self.me then
    -- Some AE2/OC builds return nil instead of an empty table when the
    -- network has no item inventory (for example a fluids-only network).
    -- Retry with an explicit empty filter before treating it as "no items".
    local okItems, items = pcall(self.me.getItemsInNetwork)
    if not okItems or type(items) ~= "table" then
      local okRetry, retry = pcall(self.me.getItemsInNetwork, {})
      if okRetry and type(retry) == "table" then
        items = retry
        okItems = true
      elseif not okItems then
        self.scanError = "items: " .. tostring(items)
      else
        -- nil is a valid "no item storage" response; do not mark the whole
        -- source as broken. Fluids/power can still be listed below.
        items = nil
      end
    end

    if type(items) == "table" then
      for i = 1, #items do
        local stack = items[i]
        if type(stack) == "table" and type(stack.name) == "string" then
          local amount = tonumber(stack.size) or 0
          if amount > 0 then
            local damage = tonumber(stack.damage) or 0
            local key = "item:" .. stack.name .. ":" .. tostring(damage)
            local label = stack.label or stack.name
            put(newMeta("item", key, label, "items", {
              name = stack.name,
              damage = damage,
              hasTag = stack.hasTag == true,
            }), amount)
          end
        end
      end
    end

    local okFluids, fluids = pcall(self.me.getFluidsInNetwork)
    if not okFluids then
      if not self.scanError then self.scanError = "fluids: " .. tostring(fluids) end
    elseif type(fluids) == "table" then
      for i = 1, #fluids do
        local stack = fluids[i]
        if type(stack) == "table" and type(stack.name) == "string" then
          local amount = tonumber(stack.amount) or tonumber(stack.size) or 0
          if amount > 0 then
            local key = "fluid:" .. stack.name
            put(newMeta("fluid", key, stack.label or stack.name, "mB", {
              name = stack.name,
            }), amount)
          end
        end
      end
    else
      if not self.scanError then self.scanError = "fluids: invalid response" end
    end

    if self.cfg.includePower ~= false and self:hasMethod("getStoredPower") then
      local okPower, stored = pcall(self.me.getStoredPower)
      if okPower and util.isFinite(tonumber(stored)) then
        local okMax, maxPower = pcall(self.me.getMaxStoredPower)
        put(newMeta("power", "power:stored", "ME Network Power", "AE", {
          max = (okMax and tonumber(maxPower)) or nil,
        }), tonumber(stored))
      end
    end
  end

  self:addCustom(resources)
  if self.demoEnabled then
    self:addDemo(resources)
  end

  table.sort(resources, function(a, b)
    local oa = KIND_ORDER[a.kind] or 99
    local ob = KIND_ORDER[b.kind] or 99
    if oa ~= ob then return oa < ob end
    local aa = a.amount or -1
    local ab = b.amount or -1
    if aa ~= ab then return aa > ab end
    return util.lower(a.label) < util.lower(b.label)
  end)

  self.cached = resources
  self.cachedAt = now
  return resources, self.scanError
end

function Sources:sample(meta, now)
  if type(meta) ~= "table" or type(meta.key) ~= "string" then
    return nil, nil, "invalid resource"
  end

  if meta.kind == "custom" and type(meta.sample) == "function" then
    local ok, value, max = pcall(meta.sample, meta, now)
    if not ok then return nil, nil, tostring(value) end
    if type(value) == "table" then
      max = value.max
      value = value.value
    end
    value = tonumber(value)
    if not util.isFinite(value) then
      return nil, nil, tostring(max or "custom source returned no value")
    end
    return value, tonumber(max), nil
  end

  if meta.kind == "demo" then
    local value, max = self:demoValue(meta.key, now)
    return value, max, nil
  end

  if meta.kind == "power" then
    if not self.me then self:detect(true) end
    if not self.me then return nil, nil, "AE2 offline" end
    local ok, stored = pcall(self.me.getStoredPower)
    if not ok or not util.isFinite(tonumber(stored)) then
      return nil, nil, "getStoredPower failed"
    end
    local okMax, maxPower = pcall(self.me.getMaxStoredPower)
    return tonumber(stored), (okMax and util.isFinite(tonumber(maxPower))) and tonumber(maxPower) or nil, nil
  end

  if meta.kind == "item" then
    if type(meta.name) ~= "string" then return nil, nil, "invalid item metadata" end
    if not self.me then self:detect(true) end
    if not self.me then return nil, nil, "AE2 offline" end

    local filter = { name = meta.name }
    if meta.damage ~= nil then filter.damage = tonumber(meta.damage) or 0 end

    local ok, list = pcall(self.me.getItemsInNetwork, filter)
    if not ok or type(list) ~= "table" then
      -- Some AE2/OC builds behave differently for filtered calls, and some
      -- return nil for a network without item storage. Try an explicit empty
      -- filter, then a full scan, before reporting an error.
      local okRetry, retry = pcall(self.me.getItemsInNetwork, {})
      if okRetry and type(retry) == "table" then
        list = retry
      elseif ok and list == nil then
        list = {}
      else
        local okAll, all = pcall(self.me.getItemsInNetwork)
        if not okAll or type(all) ~= "table" then
          return nil, nil, "getItemsInNetwork failed"
        end
        list = all
      end
    end

    local total = 0
    local damage = tonumber(meta.damage) or 0
    for i = 1, #list do
      local stack = list[i]
      if type(stack) == "table"
        and stack.name == meta.name
        and (tonumber(stack.damage) or 0) == damage
      then
        total = total + (tonumber(stack.size) or 0)
      end
    end
    return total, nil, nil
  end

  if meta.kind == "fluid" then
    if type(meta.name) ~= "string" then return nil, nil, "invalid fluid metadata" end
    if not self.me then self:detect(true) end
    if not self.me then return nil, nil, "AE2 offline" end

    if self:hasMethod("getFluidInNetwork") then
      local ok, stack = pcall(self.me.getFluidInNetwork, meta.name)
      if ok then
        if type(stack) == "table" then
          return tonumber(stack.amount) or tonumber(stack.size) or 0, nil, nil
        end
        return 0, nil, nil
      end
    end

    local ok, fluids = pcall(self.me.getFluidsInNetwork)
    if not ok or type(fluids) ~= "table" then
      return nil, nil, "getFluidsInNetwork failed"
    end
    local total = 0
    for i = 1, #fluids do
      local stack = fluids[i]
      if type(stack) == "table" and stack.name == meta.name then
        total = total + (tonumber(stack.amount) or tonumber(stack.size) or 0)
      end
    end
    return total, nil, nil
  end

  return nil, nil, "unsupported resource kind: " .. tostring(meta.kind)
end

function Sources:kindLabel(meta)
  if not meta then return "?" end
  if meta.kind == "item" then return "ITEM" end
  if meta.kind == "fluid" then return "FLUID" end
  if meta.kind == "power" then return "POWER" end
  if meta.kind == "custom" then return "CUSTOM" end
  if meta.kind == "demo" then return "DEMO" end
  return string.upper(tostring(meta.kind))
end

return Sources

]===],
  ["rc_ui"] = [===[
-- rc_ui.lua -- adaptive, mostly-ASCII dashboard and chart renderer.
--
-- The layout has three modes:
--   full    : wide screen, chart + statistics side panel
--   medium  : chart + compact header, no side panel
--   compact : 50x16 tier-1 friendly layout
--
-- Only the GPU is used for drawing. Touch/keyboard handling lives in rc_app.lua;
-- this module registers hitboxes and renders overlays.

local util = require("rc_util")
local chart = require("rc_chart")
local themeLib = require("rc_theme")

local UI = {}
UI.__index = UI

function UI.new(app)
  local self = setmetatable({
    app = app,
    gpu = app.gpu,
    buttons = {},
    W = 80,
    H = 25,
  }, UI)
  self:resize()
  return self
end

function UI:resize()
  local ok, w, h = pcall(self.gpu.getResolution)
  if ok and util.isFinite(w) and util.isFinite(h) and w > 0 and h > 0 then
    self.W, self.H = w, h
  end
end

function UI:put(x, y, text, fg, bg, maxW)
  if not self.W or not self.H then return 0 end
  x, y = math.floor(x), math.floor(y)
  if x < 1 or y < 1 or y > self.H or x > self.W then return 0 end
  local widthLimit = maxW or (self.W - x + 1)
  widthLimit = math.min(widthLimit, self.W - x + 1)
  if widthLimit <= 0 then return 0 end
  text = util.truncate(util.sanitize(text), widthLimit)
  if bg then self.gpu.setBackground(bg) end
  if fg then self.gpu.setForeground(fg) end
  self.gpu.set(x, y, text)
  return util.width(text)
end

function UI:fill(x, y, w, h, ch, fg, bg)
  x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
  if w <= 0 or h <= 0 then return end
  if x < 1 then w = w + x - 1; x = 1 end
  if y < 1 then h = h + y - 1; y = 1 end
  if x + w - 1 > self.W then w = self.W - x + 1 end
  if y + h - 1 > self.H then h = self.H - y + 1 end
  if w <= 0 or h <= 0 then return end
  if bg then self.gpu.setBackground(bg) end
  if fg then self.gpu.setForeground(fg) end
  self.gpu.fill(x, y, w, h, ch or " ")
end

function UI:hline(x1, x2, y, ch, fg, bg)
  if x2 < x1 then return end
  local w = x2 - x1 + 1
  self:put(x1, y, string.rep(ch, w), fg, bg, w)
end

function UI:box(x1, y1, x2, y2, fg, bg, fillChar)
  if x2 - x1 < 1 or y2 - y1 < 1 then return end
  self:fill(x1, y1, x2 - x1 + 1, y2 - y1 + 1, fillChar or " ", fg, bg)
  self.gpu.setForeground(fg)
  self.gpu.setBackground(bg or themeLib.get(8).panel)
  self.gpu.set(x1, y1, "+" .. string.rep("-", x2 - x1 - 1) .. "+")
  self.gpu.set(x1, y2, "+" .. string.rep("-", x2 - x1 - 1) .. "+")
  for y = y1 + 1, y2 - 1 do
    self.gpu.set(x1, y, "|")
    self.gpu.set(x2, y, "|")
  end
end

function UI:button(x, y, label, opts)
  opts = opts or {}
  label = util.truncate(util.sanitize(label), math.max(1, self.W - x - 2))
  local width = util.width(label) + 2
  if opts.width then width = opts.width end
  if x + width - 1 > self.W then return x end

  local active = opts.active == true
  local bg = active and self.theme.accent or (opts.bg or self.theme.panel2)
  local fg = active and self.theme.bg or (opts.fg or self.theme.text)
  local bracket = active and self.theme.bg or self.theme.faint

  self:fill(x, y, width, 1, " ", fg, bg)
  self.gpu.setForeground(bracket)
  self.gpu.setBackground(bg)
  self.gpu.set(x, y, "[")
  self.gpu.set(x + width - 1, y, "]")
  self:put(x + 1, y, util.pad(label, width - 2, "center"), fg, bg, width - 2)

  self.buttons[#self.buttons + 1] = {
    x1 = x,
    y1 = y,
    x2 = x + width - 1,
    y2 = y,
    action = opts.action,
    arg = opts.arg,
  }
  return x + width
end

function UI:hit(x, y)
  for i = #self.buttons, 1, -1 do
    local b = self.buttons[i]
    if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
      return b.action, b.arg
    end
  end
  return nil
end

function UI:rangeLabel(seconds)
  if seconds == 86400 then return "24h" end
  if seconds == 172800 then return "2d" end
  if seconds == 604800 then return "7d" end
  return util.formatDuration(seconds, true)
end

function UI:layout()
  local W, H = self.W, self.H
  local compact = W < 64 or H < 18
  local side = (W >= 76 and H >= 22)

  local headerH = compact and 2 or 3
  local footerH = 3
  local bodyY1 = headerH + 1
  local bodyY2 = H - footerH

  local sideW = 0
  local chartX2 = W
  local sideX1 = nil
  if side then
    sideW = math.max(18, math.min(32, math.floor(W * 0.24)))
    chartX2 = W - sideW - 1
    sideX1 = chartX2 + 1
  end

  local chartBox = { x1 = 1, y1 = bodyY1, x2 = chartX2, y2 = bodyY2 }
  local sideBox = nil
  if side then
    sideBox = { x1 = sideX1, y1 = bodyY1, x2 = W, y2 = bodyY2 }
  end

  return {
    W = W,
    H = H,
    compact = compact,
    side = side,
    headerH = headerH,
    footerH = footerH,
    bodyY1 = bodyY1,
    bodyY2 = bodyY2,
    chart = chartBox,
    sideBox = sideBox,
  }
end

function UI:drawHeader(L)
  local W = self.W
  local state = self.app.state
  local meta = state.selected

  self:fill(1, 1, W, 1, " ", self.theme.text, self.theme.panel3)
  local title = self.app.config.title or "RESOURCE MONITOR"
  self:put(1, 1, " " .. title, self.theme.accent, self.theme.panel3, W - 2)

  local status
  local statusColor
  if state.paused then
    status = "PAUSED"
    statusColor = self.theme.warn
  elseif state.follow then
    status = "LIVE"
    statusColor = self.theme.good
  else
    status = "HISTORY"
    statusColor = self.theme.accent2
  end

  local clock = util.formatClock(self.app:gameNow())
  local clockW = util.width(clock) + 1
  local clockX = W - clockW + 1
  self:put(clockX, 1, clock .. " ", self.theme.dim, self.theme.panel3, clockW)

  local statusW = util.width(status) + 1
  local statusX = clockX - statusW - 1
  self:put(statusX, 1, status .. " ", statusColor, self.theme.panel3, statusW)

  -- The status label doubles as a touch target: tapping HISTORY returns the
  -- view to live mode on touch-only setups.
  self.buttons[#self.buttons + 1] = {
    x1 = statusX,
    y1 = 1,
    x2 = statusX + util.width(status) - 1,
    y2 = 1,
    action = "follow",
  }

  self:fill(1, 2, W, 1, " ", self.theme.text, self.theme.panel)

  local label = meta and meta.label or "No resource selected"
  local kind = meta and self.app.sources:kindLabel(meta) or "NONE"
  local badgeW = util.width(kind) + 2

  local value = self.app:currentValue()
  local stats = self.app:windowStats()
  local unit = meta and meta.unit or ""
  local valueText = value ~= nil and (util.formatCompact(value) .. " " .. unit) or "--"
  local deltaText = ""
  if stats and stats.delta ~= nil then
    deltaText = util.formatDelta(stats.delta, stats.firstV)
  end

  local valueW = util.width(valueText)
  local deltaW = util.width(deltaText)
  local maxValueW = math.max(8, math.floor(W * 0.42))
  if valueW > maxValueW then
    valueText = util.formatCompact(value) .. " " .. unit
    valueW = util.width(valueText)
  end

  local vx = W - valueW
  local dx = vx - deltaW - 2
  if dx < badgeW + 5 then
    deltaText = ""
    deltaW = 0
    dx = vx
  end

  local labelX = 1 + badgeW + 1
  local labelMax = dx - labelX - 1
  self:put(1, 2, " " .. kind .. " ", self.theme.bg, self.theme.accent2, badgeW)
  if labelMax >= 3 then
    self:put(labelX, 2, label, self.theme.text, self.theme.panel, labelMax)
  end

  if deltaW > 0 then
    local dcolor = self.theme.dim
    if stats and stats.delta then
      dcolor = stats.delta > 0 and self.theme.good or (stats.delta < 0 and self.theme.bad or self.theme.dim)
    end
    self:put(dx, 2, deltaText, dcolor, self.theme.panel, deltaW)
  end
  self:put(vx, 2, valueText, self.theme.accent, self.theme.panel, valueW)

  if L.headerH >= 3 then
    self:hline(1, W, 3, "-", self.theme.border, self.theme.panel)

    local source = self.app:sourceName()
    local left = " " .. kind .. " | " .. source .. " | " .. tostring(self.app.config.sampleInterval) .. "s"
    local totalPoints = state.history and state.history:count() or 0
    left = left .. " | " .. tostring(totalPoints) .. " pts "
    local leftW = util.width(left)
    self:put(1, 3, left, state.lastError and self.theme.bad or self.theme.dim, self.theme.panel, math.floor(W * 0.62))

    local updated = "--"
    if state.lastSampleAt then
      updated = util.formatDuration(math.max(0, self.app:now() - state.lastSampleAt), true) .. " ago"
    end
    local rangeText = self:rangeLabel(state.window)
    local right = " " .. rangeText .. " | " .. updated .. " "
    local rw = util.width(right)
    if W - rw > leftW then
      self:put(W - rw + 1, 3, right, state.lastError and self.theme.bad or self.theme.faint, self.theme.panel, rw)
    end
  end
end

function UI:drawSideBox(L)
  local box = L.sideBox
  if not box then return end
  local x, y1, y2 = box.x1, box.y1, box.y2
  local theme = self.theme
  local state = self.app.state
  local meta = state.selected

  self:fill(x, y1, self.W - x + 1, y2 - y1 + 1, " ", theme.text, theme.panel2)
  self:fill(x, y1, 1, y2 - y1 + 1, "|", theme.border, theme.panel2)

  local cx = x + 2
  local cw = self.W - cx
  local y = y1 + 1
  local stats = self.app:windowStats()
  local value = self.app:currentValue()
  local unit = meta and meta.unit or ""

  local function label(text)
    if y > y2 then return end
    self:put(cx, y, text, theme.dim, theme.panel2, cw)
    y = y + 1
  end

  local function valueLine(text, color)
    if y > y2 then return end
    self:put(cx, y, text, color or theme.text, theme.panel2, cw)
    y = y + 1
  end

  label("CURRENT")
  if value ~= nil then
    valueLine(util.formatCompact(value), theme.accent)
    valueLine(unit, theme.dim)
  else
    valueLine("--", theme.dim)
  end

  y = y + 1
  label("TREND")
  if stats and stats.delta ~= nil then
    local c = stats.delta > 0 and theme.good or (stats.delta < 0 and theme.bad or theme.dim)
    valueLine(util.formatSigned(stats.delta) .. " " .. unit, c)
    if stats.firstV and math.abs(stats.firstV) > 1e-9 then
      valueLine(util.formatSigned(stats.delta / math.abs(stats.firstV) * 100) .. "%", c)
    end
  else
    valueLine("--", theme.dim)
  end

  y = y + 1
  label("WINDOW")
  valueLine(self:rangeLabel(state.window) .. "  " .. tostring(stats and stats.count or 0) .. " pts", theme.text)

  if y + 5 <= y2 then
    y = y + 1
    label("MIN / MAX")
    if stats then
      valueLine(util.formatCompact(stats.minV) .. " / " .. util.formatCompact(stats.maxV), theme.text)
    else
      valueLine("--", theme.dim)
    end

    label("AVERAGE")
    valueLine(stats and util.formatCompact(stats.avgV) or "--", theme.text)

    label("SPAN")
    valueLine(stats and util.formatDuration(stats.span, true) or "--", theme.text)
  end

  if y + 3 <= y2 then
    y = y + 1
    label("SOURCE")
    valueLine(self.app:sourceName(), theme.text)
    label("DATA")
    valueLine(tostring(state.history and state.history:count() or 0) .. " samples", theme.dim)
  end

  if state.lastError and y <= y2 then
    y = y + 1
    self:put(cx, y, util.truncate(state.lastError, cw), theme.bad, theme.panel2, cw)
  end
end

function UI:drawNoData(plot, message, sub)
  local cx = math.floor((plot.x1 + plot.x2) / 2)
  local cy = math.floor((plot.y1 + plot.y2) / 2)
  local maxW = math.max(1, plot.x2 - plot.x1 + 1)
  message = util.truncate(message, maxW)
  local w = util.width(message)
  self:put(util.clamp(cx - math.floor(w / 2), plot.x1, plot.x2 - w + 1), cy,
    message, self.theme.dim, self.theme.panel, maxW)
  if sub and cy + 1 <= plot.y2 then
    sub = util.truncate(sub, maxW)
    local sw = util.width(sub)
    self:put(util.clamp(cx - math.floor(sw / 2), plot.x1, plot.x2 - sw + 1), cy + 1,
      sub, self.theme.faint, self.theme.panel, maxW)
  end
end

function UI:drawTooltip(px, py, value, cursorT, now, plot)
  local unit = self.app.state.selected and self.app.state.selected.unit or ""
  local lines = {
    util.formatDuration(math.max(0, now - cursorT), false) .. " ago",
    util.formatCompact(value) .. " " .. unit,
    util.formatClock(self.app:gameNow() - (now - cursorT) * 72),
  }
  local w = 22
  for i = 1, #lines do w = math.max(w, util.width(lines[i]) + 2) end
  w = math.min(w, self.W - 2)
  local h = #lines + 2
  local x = px + 2
  if x + w - 1 > plot.x2 then x = px - w - 1 end
  if x < plot.x1 then x = plot.x1 end
  local y = plot.y1 + 1
  if y + h - 1 > plot.y2 then y = plot.y2 - h + 1 end
  if y < plot.y1 then y = plot.y1 end

  self:box(x, y, x + w - 1, y + h - 1, self.theme.accent, self.theme.panel3, " ")
  for i = 1, #lines do
    self:put(x + 1, y + i, lines[i], i == 2 and self.theme.accent or self.theme.text, self.theme.panel3, w - 2)
  end
end

function UI:drawChart(L)
  local box = L.chart
  local theme = self.theme
  local state = self.app.state
  local meta = state.selected
  local now = self.app:now()
  local t0, t1 = self.app:visibleRange()

  self:fill(box.x1, box.y1, box.x2 - box.x1 + 1, box.y2 - box.y1 + 1, " ", theme.text, theme.panel)
  self:box(box.x1, box.y1, box.x2, box.y2, theme.border, theme.panel, " ")
  self.lastPlot = nil

  local unit = meta and meta.unit or "VALUE"
  self:put(box.x1 + 2, box.y1, " " .. unit .. " ", theme.dim, theme.panel, 20)
  local rangeText = self:rangeLabel(state.window)
  if not state.follow then rangeText = rangeText .. " HIST" end
  if state.zero then rangeText = rangeText .. " Z" end
  local rw = util.width(rangeText) + 2
  self:put(box.x2 - rw, box.y1, " " .. rangeText .. " ", state.follow and theme.faint or theme.accent2, theme.panel, rw)

  local gridH = theme.mono and "." or "-"
  local gridV = theme.mono and ":" or "|"

  local stats = self.app:windowStats()
  if not stats then
    local history = state.history
    local sub
    if history and history:count() > 0 and history:firstTime() then
      sub = "oldest sample: " .. util.formatRelative(history:firstTime(), now, true)
    elseif state.lastError then
      sub = state.lastError
    else
      sub = "waiting for the first sample"
    end
    self:drawNoData({ x1 = box.x1 + 1, x2 = box.x2 - 1, y1 = box.y1 + 1, y2 = box.y2 - 1 },
      "No samples in this window", util.truncate(sub, box.x2 - box.x1 - 2))
    return
  end

  local plotH = math.max(1, (box.y2 - 2) - (box.y1 + 1) + 1)
  local maxTicks = math.max(2, math.min(6, math.floor(plotH / 3)))
  local yscale = chart.scale(stats.minV, stats.maxV, maxTicks, state.zero)

  local gutter = 5
  for i = 1, #yscale.ticks do
    gutter = math.max(gutter, util.width(chart.axisLabel(yscale.ticks[i])) + 2)
  end
  gutter = math.min(gutter, 10)

  local px1 = box.x1 + 1 + gutter
  local px2 = box.x2 - 1
  local py1 = box.y1 + 1
  local py2 = box.y2 - 2
  local plot = { x1 = px1, x2 = px2, y1 = py1, y2 = py2 }
  local plotW = px2 - px1 + 1
  self.lastPlot = plot

  if plotW < 8 or plotH < 3 then
    self:drawNoData(plot, "Screen too small", "increase screen resolution")
    return
  end

  -- Left axis and horizontal grid.
  local axisX = px1 - 1
  self:fill(axisX, py1, 1, plotH, "|", theme.border, theme.panel)
  for i = 1, #yscale.ticks do
    local v = yscale.ticks[i]
    local y = util.round(chart.yFor(v, yscale.lo, yscale.hi, py1, py2))
    if y >= py1 and y <= py2 then
      self:put(box.x1 + 1, y, util.pad(chart.axisLabel(v), gutter - 2, "right"), theme.dim, theme.panel, gutter - 2)
      self:hline(px1, px2, y, gridH, theme.grid, theme.panel)
    end
  end

  -- Vertical time grid and labels.
  local ticks = chart.timeTicks(t0, t1, plotW, now)
  local lastLabelEnd = -100
  for i = 1, #ticks do
    local t = ticks[i]
    local x = util.round(chart.xFor(t, t0, t1, px1, px2))
    if x >= px1 and x <= px2 then
      self:fill(x, py1, 1, plotH, gridV, theme.grid, theme.panel)
      local label = util.formatRelative(t, now, true)
      local lw = util.width(label)
      local lx = util.clamp(x - math.floor(lw / 2), box.x1 + 1, box.x2 - lw)
      if lx > lastLabelEnd + 1 then
        self:put(lx, box.y2 - 1, label, theme.faint, theme.panel, lw)
        lastLabelEnd = lx + lw - 1
      end
    end
  end

  local gap = state.history:gapLimit(t1 - t0, self.app.config.sampleInterval, plotW)
  local cols, has = chart.aggregate(state.history, t0, t1, plotW, gap)

  if not has then
    self:drawNoData(plot, "No samples in this window", "try a longer range")
    return
  end

  -- Min/max envelope for spikes between samples. It is drawn before the
  -- filled area, so the lower part is covered by the area and only visible
  -- spikes remain. One GPU fill per column keeps the cost low.
  for c = 1, plotW do
    local col = cols[c]
    if col and col.n > 1 and not theme.mono then
      local x = px1 + c - 1
      local yTop = util.round(chart.yFor(col.max, yscale.lo, yscale.hi, py1, py2))
      local yBottom = util.round(chart.yFor(col.min, yscale.lo, yscale.hi, py1, py2))
      if yBottom - yTop >= 2 then
        self:fill(x, yTop, 1, yBottom - yTop + 1, "|", theme.accent2, theme.panel)
      end
    end
  end

  -- Filled area under the line.
  if theme.area then
    self.gpu.setBackground(theme.area)
    for c = 1, plotW do
      local col = cols[c]
      if col then
        local x = px1 + c - 1
        local y = util.round(chart.yFor(col.avg, yscale.lo, yscale.hi, py1, py2))
        if y < py2 then
          self.gpu.fill(x, y + 1, 1, py2 - y, " ")
        end
      end
    end
    self.gpu.setBackground(theme.panel)
  end

  -- Redraw the grid over the filled area so the axes stay readable.
  for i = 1, #yscale.ticks do
    local y = util.round(chart.yFor(yscale.ticks[i], yscale.lo, yscale.hi, py1, py2))
    if y >= py1 and y <= py2 then
      self:hline(px1, px2, y, gridH, theme.grid, theme.panel)
    end
  end
  for i = 1, #ticks do
    local x = util.round(chart.xFor(ticks[i], t0, t1, px1, px2))
    if x >= px1 and x <= px2 then
      self:fill(x, py1, 1, plotH, gridV, theme.grid, theme.panel)
    end
  end

  -- Main line. Set colors once; the callback only writes characters.
  self.gpu.setForeground(theme.accent)
  self.gpu.setBackground(theme.panel)
  local prev = nil
  for c = 1, plotW do
    local col = cols[c]
    if col then
      local x = px1 + c - 1
      local y = util.round(chart.yFor(col.avg, yscale.lo, yscale.hi, py1, py2))
      if prev then
        chart.line(prev.x, prev.y, x, y, function(lx, ly, ch)
          if lx >= px1 and lx <= px2 and ly >= py1 and ly <= py2 then
            self.gpu.set(lx, ly, theme.mono and "*" or ch)
          end
        end)
      else
        self.gpu.set(x, y, theme.mono and "*" or "o")
      end
      prev = { x = x, y = y }
    else
      prev = nil
    end
  end

  -- Newest point.
  local lastValue = state.history:lastValue()
  if lastValue ~= nil and state.history:lastTime() and state.history:lastTime() >= t0 and state.history:lastTime() <= t1 then
    local x = util.round(chart.xFor(state.history:lastTime(), t0, t1, px1, px2))
    local y = util.round(chart.yFor(lastValue, yscale.lo, yscale.hi, py1, py2))
    if x >= px1 and x <= px2 and y >= py1 and y <= py2 then
      self:put(x, y, "o", theme.good, theme.panel, 1)
    end
  end

  -- Cursor / crosshair.
  if state.cursorT and state.cursorT >= t0 and state.cursorT <= t1 then
    local x = util.round(chart.xFor(state.cursorT, t0, t1, px1, px2))
    if x >= px1 and x <= px2 then
      self:fill(x, py1, 1, plotH, ":", theme.cursor, theme.panel)
      local v = chart.interp(state.history, state.cursorT, gap)
      if v ~= nil then
        local y = util.round(chart.yFor(v, yscale.lo, yscale.hi, py1, py2))
        if y >= py1 and y <= py2 then
          self:put(x, y, "x", theme.cursor, theme.panel, 1)
          self:drawTooltip(x, y, v, state.cursorT, now, plot)
        end
      end
    end
  end

  if state.lastError then
    self:put(box.x1 + 2, box.y2 - 1, util.truncate("SOURCE ERROR: " .. state.lastError, box.x2 - box.x1 - 3),
      theme.bad, theme.panel, box.x2 - box.x1 - 3)
  end
end

function UI:drawFooter(L)
  local W, H = self.W, self.H
  local theme = self.theme
  local state = self.app.state
  local y = H - 1

  self:fill(1, H - 2, W, 3, " ", theme.text, theme.panel)
  self:hline(1, W, H - 2, "-", theme.border, theme.panel)

  local items = {}
  local function add(label, action, arg, active)
    items[#items + 1] = { label = label, action = action, arg = arg, active = active }
  end

  if L.compact then
    for i = 1, math.min(5, #self.app.config.ranges) do
      local r = self.app.config.ranges[i]
      add(self:rangeLabel(r), "range", r, math.abs(state.window - r) < 0.5)
    end
    add("<", "cycle", -1)
    add(">", "cycle", 1)
    add(state.paused and "Play" or "Pause", "pause")
    add("Pick", "picker")
  else
    for i = 1, #self.app.config.ranges do
      local r = self.app.config.ranges[i]
      add(self:rangeLabel(r), "range", r, math.abs(state.window - r) < 0.5)
    end
    add("<", "cycle", -1)
    add(">", "cycle", 1)
    add(state.paused and "Play" or "Pause", "pause")
    add("Live", "follow", nil, state.follow)
    add("Pick", "picker")
    add("CSV", "export")
    add("?", "help")
  end

  -- Drop optional buttons from the end until they fit.
  local function totalWidth()
    local w = 0
    for i = 1, #items do
      w = w + util.width(items[i].label) + 3
    end
    return w
  end

  while #items > 4 and totalWidth() > W do
    table.remove(items)
  end

  local x = 1
  for i = 1, #items do
    local it = items[i]
    local w = util.width(it.label) + 2
    if x + w - 1 > W then break end
    x = self:button(x, y, it.label, { active = it.active, action = it.action, arg = it.arg })
    x = x + 1
  end

  if L.compact then
    local hints = {
      { "P pause", "pause" },
      { "T pick", "picker" },
      { "E csv", "export" },
      { "? help", "help" },
      { "Q quit", "quit" },
    }
    local hx = 1
    for i = 1, #hints do
      local label = hints[i][1]
      local w = util.width(label)
      if hx + w - 1 > W then break end
      self:put(hx, H, label, theme.faint, theme.panel, w)
      self.buttons[#self.buttons + 1] = {
        x1 = hx, y1 = H, x2 = hx + w - 1, y2 = H,
        action = hints[i][2],
      }
      hx = hx + w + 2
    end
  else
    local hints = "DRAG PAN  SCROLL ZOOM  Z ZERO  P PAUSE  E CSV  H HELP  Q QUIT"
    self:put(1, H, util.truncate(hints, W), theme.faint, theme.panel, W)
    local touchHints = {
      { "E CSV", "export" },
      { "H HELP", "help" },
    }
    for i = 1, #touchHints do
      local label = touchHints[i][1]
      local pos = hints:find(label, 1, true)
      if pos and pos + util.width(label) - 1 <= W then
        self.buttons[#self.buttons + 1] = {
          x1 = pos, y1 = H, x2 = pos + util.width(label) - 1, y2 = H,
          action = touchHints[i][2],
        }
      end
    end
  end
end

function UI:helpLines()
  if self.H < 20 then
    return {
      "RESOURCE CHART -- HELP",
      "KEYS",
      "  Left/Right ... pan time",
      "  Up/Down ..... resource",
      "  +/- ......... zoom",
      "  R / Z ....... live / zero",
      "  P ........... pause",
      "  T / E ....... picker / export",
      "  H / ? ....... help",
      "  Q ........... quit",
      "TOUCH: tap buttons/chart; drag pans; scroll zooms",
    }
  end
  local lines = {
    "RESOURCE CHART -- HELP",
    "",
    "KEYS",
    "  Left / Right ........ pan time",
    "  Up / Down .......... previous / next resource",
    "  + / - .............. zoom in / out",
    "  R .................. live / reset view",
    "  P or Space ......... pause sampling",
    "  Z .................. zero baseline",
    "  T .................. resource picker",
    "  E .................. export CSV",
    "  H or ? ............. this help",
    "  Q or Ctrl+C ........ quit",
    "",
    "TOUCH",
    "  Tap a button. Tap the chart for a value.",
    "  Drag the chart to pan. Scroll to zoom.",
    "",
    "DATA",
    "  Sample interval: " .. tostring(self.app.config.sampleInterval) .. "s",
    "  File: " .. tostring(self.app.dataPath or self.app.config.dataPath),
    "  Items are aggregated by name + damage.",
  }
  return lines
end

function UI:drawHelp(L)
  local W, H = self.W, self.H
  local theme = self.theme
  local w = math.min(W - 2, 70)
  local h = math.min(H - 2, 25)
  local x = math.floor((W - w) / 2) + 1
  local y = math.floor((H - h) / 2) + 1
  self:fill(1, 1, W, H, " ", theme.text, theme.bg)
  self:box(x, y, x + w - 1, y + h - 1, theme.accent, theme.panel3, " ")

  local lines = self:helpLines()
  local maxLines = h - 3
  local start = 1
  if #lines > maxLines then
    start = math.max(1, math.min(#lines - maxLines + 1, self.app.helpScroll or 1))
  end
  for i = 1, maxLines do
    local line = lines[start + i - 1]
    if line then
      local color = theme.text
      if i == 1 then color = theme.accent end
      if line:match("^KEYS") or line:match("^TOUCH") or line:match("^DATA") then color = theme.accent2 end
      self:put(x + 2, y + i, line, color, theme.panel3, w - 3)
    end
  end
  self:button(x + w - 9, y + h - 2, "Close", { action = "close" })
end

function UI:drawPicker(L)
  local W, H = self.W, self.H
  local theme = self.theme
  local view = self.app:getPickerView()

  self:fill(1, 1, W, H, " ", theme.text, theme.bg)
  self:box(1, 1, W, H, theme.border, theme.panel, " ")

  self:fill(2, 1, W - 2, 1, " ", theme.bg, theme.accent)
  self:put(2, 1, " SELECT RESOURCE", theme.bg, theme.accent, W - 20)
  local esc = "ESC close"
  local escW = util.width(esc)
  local escX = W - escW - 1
  self:put(escX, 1, esc, theme.bg, theme.accent, escW)
  self.buttons[#self.buttons + 1] = {
    x1 = escX, y1 = 1, x2 = escX + escW - 1, y2 = 1,
    action = "close",
  }

  self:fill(2, 2, W - 2, 1, " ", theme.text, theme.panel3)
  local query = view.query ~= "" and view.query or ""
  local cursor = view.searchFocused and "_" or ""
  self:put(2, 2, " Search: " .. query .. cursor, theme.text, theme.panel3, W - 4)
  self.buttons[#self.buttons + 1] = { x1 = 2, y1 = 2, x2 = W - 1, y2 = 2, action = "picker_search" }

  local kinds = { { "all", "ALL" }, { "item", "ITEM" }, { "fluid", "FLUID" }, { "power", "POWER" }, { "custom", "CUSTOM" }, { "demo", "DEMO" } }
  local x = 2
  for i = 1, #kinds do
    local k, label = kinds[i][1], kinds[i][2]
    local bw = util.width(label) + 2
    if x + bw - 1 > W - 1 then break end
    x = self:button(x, 3, label, {
      active = view.kind == k,
      action = "picker_kind",
      arg = k,
    })
    x = x + 1
  end

  local listY1 = 4
  local listY2 = H - 2
  local rows = math.max(1, listY2 - listY1 + 1)

  if view.loading then
    self:put(3, listY1, "Scanning network...", theme.dim, theme.panel, W - 4)
  elseif view.error then
    self:put(3, listY1, util.truncate("No resources: " .. view.error, W - 4), theme.bad, theme.panel, W - 4)
  elseif #view.items == 0 then
    self:put(3, listY1, "No matching resources.", theme.dim, theme.panel, W - 4)
  else
    local start = math.max(1, math.min(view.selected - math.floor(rows / 2), #view.items - rows + 1))
    if start < 1 then start = 1 end
    view.scroll = start
    for r = 0, rows - 1 do
      local idx = start + r
      local item = view.items[idx]
      if item then
        local y = listY1 + r
        local selected = idx == view.selected
        local bg, fg
        if selected and theme.mono then
          bg, fg = theme.inverseBg, theme.inverseText
        elseif selected then
          bg, fg = theme.selection, theme.text
        else
          bg = (r % 2 == 0) and theme.panel or theme.panel2
          fg = theme.text
        end
        self:fill(2, y, W - 2, 1, " ", fg, bg)
        local kind = self.app.sources:kindLabel(item)
        local kindColor = selected and fg or theme.accent2
        self:put(3, y, kind, kindColor, bg, 6)
        local amount = item.amount ~= nil and util.formatCompact(item.amount) or ""
        local amountW = util.width(amount)
        local labelW = W - 12 - amountW
        self:put(10, y, item.label, fg, bg, math.max(4, labelW))
        if amount ~= "" then
          self:put(W - amountW - 1, y, amount, selected and fg or theme.dim, bg, amountW)
        end
        self.buttons[#self.buttons + 1] = {
          x1 = 2, y1 = y, x2 = W - 1, y2 = y,
          action = "picker_pick", arg = item,
        }
      end
    end
    local total = #view.items
    self:put(W - 10, H - 1, tostring(view.selected) .. "/" .. tostring(total), theme.faint, theme.panel, 10)
  end

  local by = H - 1
  self:button(2, by, "Refresh", { action = "picker_refresh" })
  self:button(12, by, "Close", { action = "close" })
  self:button(20, by, "PgUp", { action = "picker_pageup" })
  self:button(27, by, "PgDn", { action = "picker_pagedown" })
  if W >= 80 then
    self:put(35, by, "Up/Down select   Enter use   / search", theme.faint, theme.panel, W - 45)
  end
end

function UI:drawToast()
  local toast = self.app.state.toast
  if not toast then return end
  if self.app:now() > (toast.expires or 0) then
    self.app.state.toast = nil
    return
  end
  local text = tostring(toast.text or "")
  local w = math.min(self.W - 2, util.width(text) + 4)
  local x = self.W - w - 1
  local y = self.H - (self.currentLayout and self.currentLayout.footerH or 3) - 2
  if y < 2 then y = 2 end
  self:fill(x, y, w, 1, " ", self.theme.bg, toast.kind == "error" and self.theme.bad or self.theme.accent2)
  self:put(x + 1, y, util.truncate(text, w - 2), self.theme.bg, toast.kind == "error" and self.theme.bad or self.theme.accent2, w - 2)
end

function UI:render()
  if not self.W or not self.H then return end
  self.buttons = {}
  self.theme = themeLib.get(self.gpu.getDepth and self.gpu.getDepth() or 8)
  local L = self:layout()
  self.currentLayout = L

  self.gpu.setBackground(self.theme.bg)
  self.gpu.setForeground(self.theme.text)
  self.gpu.fill(1, 1, self.W, self.H, " ")

  self:drawHeader(L)
  self:drawChart(L)
  self:drawSideBox(L)
  self:drawFooter(L)

  if self.app.state.overlay == "help" then
    self.buttons = {}
    self:drawHelp(L)
  elseif self.app.state.overlay == "picker" then
    self.buttons = {}
    self:drawPicker(L)
  end

  self:drawToast()
end

return UI

]===],
  ["rc_app"] = [===[
-- rc_app.lua -- controller: sampling, input, persistence, export and the event loop.

local component = require("component")
local event = require("event")
local util = require("rc_util")
local History = require("rc_history")
local store = require("rc_store")
local Sources = require("rc_sources")
local UI = require("rc_ui")

local App = {}
App.__index = App

local K = {
  escape = 0x01,
  enter = 0x1C,
  back = 0x0E,
  tab = 0x0F,
  space = 0x39,
  left = 0xCB,
  right = 0xCD,
  up = 0xC8,
  down = 0xD0,
  pageUp = 0xC9,
  pageDown = 0xD1,
  home = 0xC7,
  ["end"] = 0xCF,
}

local PICKER_KINDS = { "all", "item", "fluid", "power", "custom", "demo" }

function App.new(config)
  local self = setmetatable({}, App)
  self.config = config
  self.state = store.defaultState()
  self.entries = {}
  self.pickerItems = {}
  self.pickerError = nil
  self.running = true
  self.dirty = true
  self.unsaved = false
  self.clockBase = 0
  self.dataPath = config.dataPath
  self.lastDraw = -math.huge
  self.lastSave = 0
  self.nextSampleAt = 0
  self.keyDebounce = {}
  self.helpScroll = 1
  self.liveValue = nil
  self.currentMax = nil
  self.lastSampleAt = nil
  self.lastError = nil
  self.drag = nil
  self.saveErrorShown = false
  return self
end

-- ---------------------------------------------------------------------------
-- Screen / GPU setup
-- ---------------------------------------------------------------------------

function App:setupScreen()
  local gpuAddress, gpu
  for address in component.list("gpu", true) do
    local ok, proxy = pcall(component.proxy, address)
    if ok and proxy then
      local okScreen, bound = pcall(proxy.getScreen)
      if okScreen and bound then
        gpuAddress, gpu = address, proxy
        break
      end
      if not gpuAddress then
        gpuAddress, gpu = address, proxy
      end
    end
  end
  if not gpuAddress then
    return false, "No GPU found. Install a graphics card and a screen."
  end
  if not gpu then
    return false, "Cannot access the GPU component."
  end

  local screenAddress
  local okScreen, bound = pcall(gpu.getScreen)
  if okScreen and bound then screenAddress = bound end
  if not screenAddress then
    for address in component.list("screen", true) do
      screenAddress = address
      break
    end
  end
  if not screenAddress then
    return false, "No screen found. Place a screen next to / around the computer."
  end

  local function validScreen(address)
    local ok, proxy = pcall(component.proxy, address)
    return ok and proxy ~= nil
  end
  if not validScreen(screenAddress) then
    screenAddress = nil
    for address in component.list("screen", true) do
      if validScreen(address) then
        screenAddress = address
        break
      end
    end
  end
  if not screenAddress then
    return false, "No usable screen found."
  end

  if not (okScreen and bound == screenAddress) then
    local okBind, bindResult = pcall(gpu.bind, screenAddress)
    if not okBind or bindResult == false then
      return false, "Cannot bind the GPU to the screen."
    end
  end

  local okRes, maxW, maxH = pcall(gpu.maxResolution)
  if okRes and maxW and maxH then
    pcall(gpu.setResolution, maxW, maxH)
  end
  local okDepth, maxDepth = pcall(gpu.maxDepth)
  if okDepth and maxDepth then
    pcall(gpu.setDepth, maxDepth)
  end

  local okProxy, screen = pcall(component.proxy, screenAddress)
  if okProxy and screen then
    pcall(screen.turnOn)
    pcall(screen.setTouchModeInverted, false)
  end

  pcall(function()
    local term = require("term")
    term.setCursorBlink(false)
  end)

  self.gpu = gpu
  self.screen = screen
  self.screenAddress = screenAddress
  return true
end

function App:refreshResolution()
  local ok, maxW, maxH = pcall(self.gpu.maxResolution)
  if ok and maxW and maxH then
    local okCur, curW, curH = pcall(self.gpu.getResolution)
    if not okCur or curW ~= maxW or curH ~= maxH then
      pcall(self.gpu.setResolution, maxW, maxH)
    end
  end
  if self.ui then self.ui:resize() end
  self.dirty = true
end

-- ---------------------------------------------------------------------------
-- Clock
-- ---------------------------------------------------------------------------

function App:now()
  return self.clockBase + util.now()
end

function App:gameNow()
  return util.gameNow()
end

function App:gameAt(t)
  return self:gameNow() - (self:now() - t) * 72
end

function App:initClock(clock)
  clock = clock or {}
  local lastMonitor = tonumber(clock.lastMonitor) or 0
  local lastUptime = tonumber(clock.lastUptime) or 0
  local lastGame = tonumber(clock.lastGame) or 0
  local currentUptime = util.now()
  local currentGame = util.gameNow()

  local base
  if lastUptime > 0 and currentUptime >= lastUptime then
    -- Same computer boot: preserve continuity exactly.
    base = lastMonitor - lastUptime
  else
    -- Reboot: estimate the off-time from in-game time. The game clock advances
    -- 86400 game-seconds per 20 real minutes, i.e. 72x real time.
    local gap = 0
    if lastGame > 0 and currentGame > lastGame then
      gap = math.min((currentGame - lastGame) / 72, 30 * 86400)
    end
    base = lastMonitor + gap
  end
  if base < 0 then base = 0 end
  self.clockBase = base
  self.lastGame = currentGame
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function App:loadState()
  local primary = self.config.dataPath
  local fallback = self.config.fallbackDataPath
  local state, err = store.load(primary)

  if state then
    self.dataPath = primary
  else
    if err and err ~= "missing" and not err:find("cannot open", 1, true) then
      store.quarantine(primary)
    end
    if fallback and fallback ~= primary then
      local fallbackState, fallbackErr = store.load(fallback)
      if fallbackState then
        state = fallbackState
        self.dataPath = fallback
      elseif fallbackErr and fallbackErr ~= "missing" and not fallbackErr:find("cannot open", 1, true) then
        store.quarantine(fallback)
      end
    end
  end

  local savedKey = nil
  if state then
    self.state = state
    savedKey = self.state.selectedKey or self.state.selected
    self.state.window = util.clamp(
      tonumber(self.state.window) or self.config.defaultWindow,
      self.config.minWindow,
      self.config.maxWindow
    )
  else
    self.state = store.defaultState()
    self.state.window = util.clamp(self.config.defaultWindow, self.config.minWindow, self.config.maxWindow)
    self.state.zero = self.config.zeroBaseline == true
    self.state.paused = false
    self.state.selectedKey = nil
  end

  self.state.history = nil
  self.state.selected = nil
  self.state.cursorT = nil
  self.state.overlay = nil
  self.state.picker = nil
  self.state.toast = nil
  self.state.follow = true
  self.state.lastError = nil
  self.state.selectedKey = savedKey
end

function App:loadEntries()
  self.entries = {}
  local resources = self.state.resources or {}
  for key, entry in pairs(resources) do
    if type(entry) == "table" and type(entry.meta) == "table" then
      local history = History.new({
        maxPoints = self.config.maxPoints,
        retention = self.config.retention,
      })
      history:load(entry.points)
      history:prune(self:now())
      self.entries[key] = {
        meta = entry.meta,
        history = history,
        lastUsed = tonumber(entry.lastUsed) or 0,
      }
    end
  end
  self.state.resources = nil
  self:trimEntries()
end

function App:metaForSave(meta)
  local out = {}
  for k, v in pairs(meta or {}) do
    if type(v) ~= "function" then out[k] = v end
  end
  return out
end

function App:save(force)
  if self.entries then self:trimEntries() end
  local data = store.defaultState()
  data.savedAt = self:gameNow()
  data.selected = self.state.selectedKey
  data.window = self.state.window
  data.zero = self.state.zero == true
  data.paused = self.state.paused == true
  data.clock = {
    lastMonitor = self:now(),
    lastUptime = util.now(),
    lastGame = self:gameNow(),
  }

  for key, entry in pairs(self.entries) do
    data.resources[key] = {
      meta = self:metaForSave(entry.meta),
      points = entry.history:serialize(),
      lastUsed = entry.lastUsed or 0,
    }
  end

  local ok, err = store.save(self.dataPath, data)
  if not ok and self.config.fallbackDataPath and self.dataPath ~= self.config.fallbackDataPath then
    local okFallback, fallbackErr = store.save(self.config.fallbackDataPath, data)
    if okFallback then
      self.dataPath = self.config.fallbackDataPath
      ok = true
      err = nil
    else
      err = fallbackErr or err
    end
  end

  if ok then
    self.unsaved = false
    self.saveErrorShown = false
    self.lastSave = self:now()
    if force then self:toast("Saved to " .. self.dataPath) end
    return true
  end

  if not self.saveErrorShown then
    self:toast("Save failed: " .. tostring(err), "error")
    self.saveErrorShown = true
  end
  self.lastSave = self:now()
  return false
end

function App:trimEntries()
  local maxResources = self.config.maxResources
  local function count()
    local n = 0
    for _ in pairs(self.entries) do n = n + 1 end
    return n
  end

  while count() > maxResources do
    local oldestKey, oldestUsed = nil, nil
    for key, entry in pairs(self.entries) do
      if key ~= self.state.selectedKey then
        local used = entry.lastUsed or 0
        if oldestUsed == nil or used < oldestUsed then
          oldestKey, oldestUsed = key, used
        end
      end
    end
    if not oldestKey then break end
    self.entries[oldestKey] = nil
  end
end

-- ---------------------------------------------------------------------------
-- Resources
-- ---------------------------------------------------------------------------

function App:mergeMeta(a, b)
  if not a then return b end
  if not b then return a end
  local out = {}
  for k, v in pairs(a) do out[k] = v end
  for k, v in pairs(b) do out[k] = v end
  if not out.sample and a.sample then out.sample = a.sample end
  out.key = b.key or a.key
  return out
end

function App:findSourceMeta(key)
  if not key then return nil end
  for i = 1, #self.pickerItems do
    if self.pickerItems[i].key == key then return self.pickerItems[i] end
  end
  if self.sources then
    local list = self.sources:list()
    for i = 1, #list do
      if list[i].key == key then return list[i] end
    end
  end
  return nil
end

function App:historyFor(meta)
  local key = meta.key
  local entry = self.entries[key]
  if not entry then
    self:trimEntries()
    entry = {
      meta = meta,
      history = History.new({
        maxPoints = self.config.maxPoints,
        retention = self.config.retention,
      }),
      lastUsed = self:now(),
    }
    self.entries[key] = entry
  else
    entry.meta = self:mergeMeta(entry.meta, meta)
  end
  return entry
end

function App:selectResource(meta, noSave)
  if not meta or not meta.key then return end
  local key = meta.key
  local sourceMeta = self:findSourceMeta(key)
  local entry = self.entries[key]
  if entry and sourceMeta then
    meta = self:mergeMeta(entry.meta, sourceMeta)
  elseif entry then
    meta = self:mergeMeta(entry.meta, meta)
  end

  entry = self:historyFor(meta)
  entry.meta = meta
  entry.lastUsed = self:now()

  self.state.selectedKey = key
  self.state.selected = entry.meta
  self.state.history = entry.history
  self.state.cursorT = nil
  self.state.follow = true
  self.state.viewEnd = self:now()
  self.state.lastError = nil
  self.lastError = nil
  self.liveValue = entry.history:lastValue()
  self.lastSampleAt = entry.history:lastTime()
  self.state.lastSampleAt = self.lastSampleAt
  self.state.selected = entry.meta
  self.nextSampleAt = self:now()
  self.unsaved = true
  self.dirty = true

  if not noSave then
    self:trimEntries()
    self:save(false)
  end
end

function App:refreshStartup()
  local list, err = self.sources:list(true)
  self.pickerItems = list or {}
  self.pickerError = (err and #self.pickerItems == 0) and err or nil
  self.scanError = err
end

function App:selectInitial()
  local key = self.state.selectedKey
  local meta = nil
  if key and self.entries[key] then
    meta = self.entries[key].meta
    local sourceMeta = self:findSourceMeta(key)
    if sourceMeta then meta = self:mergeMeta(meta, sourceMeta) end
  end

  -- A demo resource can get saved as the selected resource when the computer
  -- started without AE2. Once AE2 is connected, do not keep restoring that
  -- synthetic selection unless demo mode was explicitly requested with
  -- --demo or config.demo = true.
  if meta and meta.kind == "demo" and self.config.demo ~= true
    and self.sources and self.sources:isAE2()
  then
    meta = nil
  end

  if not meta then
    for i = 1, #self.pickerItems do
      if self.pickerItems[i].kind == "item" then meta = self.pickerItems[i]; break end
    end
  end
  if not meta then
    for i = 1, #self.pickerItems do
      if self.pickerItems[i].kind == "fluid" then meta = self.pickerItems[i]; break end
    end
  end
  if not meta then
    for i = 1, #self.pickerItems do
      if self.pickerItems[i].kind == "power" then meta = self.pickerItems[i]; break end
    end
  end
  if not meta then meta = self.pickerItems[1] end

  if meta then
    self:selectResource(meta, true)
  else
    self.state.selectedKey = nil
    self.state.selected = nil
    self.state.history = nil
    self.liveValue = nil
  end
end

function App:sourceName()
  local meta = self.state.selected
  if not meta then return self.sources and self.sources:sourceName() or "none" end
  if (meta.kind == "item" or meta.kind == "fluid" or meta.kind == "power") and self.sources and not self.sources:isAE2() then
    return "AE2 offline"
  end
  if meta.kind == "custom" then return "custom" end
  if meta.kind == "demo" then
    if self.sources and self.sources:isAE2() then return "demo" end
    return "demo (no AE2)"
  end
  return self.sources and self.sources:sourceName() or "?"
end

function App:hasRealSource()
  for i = 1, #self.pickerItems do
    local kind = self.pickerItems[i].kind
    if kind == "item" or kind == "fluid" or kind == "power" then return true end
  end
  return false
end

function App:demoForced()
  return self.config.demo == true
end

function App:currentValue()
  if self.liveValue ~= nil then return self.liveValue end
  if self.state.history then return self.state.history:lastValue() end
  return nil
end

function App:visibleRange()
  local now = self:now()
  local w = self.state.window
  if self.state.follow then
    return now - w, now
  end
  local endT = self.state.viewEnd or now
  local history = self.state.history
  local minEnd = now - w
  if history and history:firstTime() then
    minEnd = math.min(now, history:firstTime() + w)
  end
  endT = util.clamp(endT, minEnd, now)
  return endT - w, endT
end

function App:viewEnd()
  local _, t1 = self:visibleRange()
  return t1
end

function App:windowStats()
  local history = self.state.history
  if not history then return nil end
  local t0, t1 = self:visibleRange()
  return history:stats(t0, t1)
end

-- ---------------------------------------------------------------------------
-- Sampling
-- ---------------------------------------------------------------------------

function App:sampleNow()
  local meta = self.state.selected
  if not meta then return false end
  local now = self:now()
  local value, max, err = self.sources:sample(meta, now)
  if value == nil then
    self.lastError = err or "source error"
    self.state.lastError = self.lastError
    self.dirty = true
    return false
  end
  if not util.isFinite(value) then
    self.lastError = "source returned a non-finite value"
    self.state.lastError = self.lastError
    self.dirty = true
    return false
  end

  self.lastError = nil
  self.state.lastError = nil
  self.liveValue = value
  self.currentMax = max
  self.lastSampleAt = now
  self.state.lastSampleAt = now

  local entry = self:historyFor(meta)
  entry.history:add(now, value)
  entry.history:prune(now)
  entry.lastUsed = now
  self.state.history = entry.history
  self.unsaved = true
  self.dirty = true
  return true
end

-- ---------------------------------------------------------------------------
-- View helpers
-- ---------------------------------------------------------------------------

function App:minViewEnd(window)
  local now = self:now()
  local w = window or self.state.window
  local history = self.state.history
  if history and history:firstTime() then
    return math.min(now, history:firstTime() + w)
  end
  return now
end

function App:setViewEnd(value)
  local now = self:now()
  local e = util.clamp(value, self:minViewEnd(), now)
  self.state.viewEnd = e
  self.state.follow = e >= now - 0.5
  self.state.cursorT = nil
  self.dirty = true
end

function App:panBy(seconds)
  if self.state.follow then
    self.state.viewEnd = self:now()
    self.state.follow = false
  end
  self:setViewEnd((self.state.viewEnd or self:now()) + seconds)
end

function App:zoom(factor, anchorX)
  local oldWindow = self.state.window
  local newWindow = util.clamp(oldWindow * factor, self.config.minWindow, self.config.maxWindow)
  if math.abs(newWindow - oldWindow) < 0.001 then return end

  local now = self:now()
  local plot = self.ui and self.ui.lastPlot
  local follow = self.state.follow
  if not follow and plot and anchorX then
    local t0 = self:visibleRange()
    local f = util.clamp((anchorX - plot.x1) / math.max(1, plot.x2 - plot.x1), 0, 1)
    local anchorT = t0 + f * oldWindow
    local newEnd = anchorT + (1 - f) * newWindow
    self.state.window = newWindow
    self:setViewEnd(newEnd)
  else
    self.state.window = newWindow
    self.state.viewEnd = now
    self.state.follow = true
    self.state.cursorT = nil
    self.dirty = true
  end
end

function App:timeAtX(x)
  local plot = self.ui and self.ui.lastPlot
  if not plot then return nil end
  local t0, t1 = self:visibleRange()
  local f = util.clamp((x - plot.x1) / math.max(1, plot.x2 - plot.x1), 0, 1)
  return t0 + f * (t1 - t0)
end

function App:touchChart(x, y)
  local plot = self.ui and self.ui.lastPlot
  if not plot then return false end
  if x < plot.x1 or x > plot.x2 or y < plot.y1 or y > plot.y2 then return false end
  self.state.cursorT = self:timeAtX(x)
  self.drag = {
    startX = x,
    startEnd = self:viewEnd(),
    moved = false,
    plotW = math.max(1, plot.x2 - plot.x1),
  }
  self.dirty = true
  return true
end

function App:onDrag(x)
  local drag = self.drag
  if not drag then return end
  local dx = x - drag.startX
  if math.abs(dx) < 1 then return end
  drag.moved = true
  local now = self:now()
  local e = util.clamp(drag.startEnd - dx * self.state.window / drag.plotW, self:minViewEnd(), now)
  self.state.viewEnd = e
  self.state.follow = e >= now - 0.5
  if self.state.follow then self.state.viewEnd = now end
  self.state.cursorT = self:timeAtX(x)
  self.dirty = true
end

function App:cursorFromTouch(x, y)
  return self:touchChart(x, y)
end

-- ---------------------------------------------------------------------------
-- Picker
-- ---------------------------------------------------------------------------

function App:pickerFiltered()
  local picker = self.state.picker
  if not picker then return {} end
  local out = {}
  local q = util.trim(picker.query or "")
  for i = 1, #self.pickerItems do
    local item = self.pickerItems[i]
    local kindOk = picker.kind == "all" or item.kind == picker.kind
    if kindOk then
      local queryOk = q == ""
        or util.contains(item.label or "", q)
        or util.contains(item.name or "", q)
        or util.contains(item.key or "", q)
        or util.contains(item.kind or "", q)
      if queryOk then out[#out + 1] = item end
    end
  end
  return out
end

function App:getPickerView()
  local picker = self.state.picker
  if not picker then
    return { items = {}, selected = 1, scroll = 1, query = "", kind = "all", loading = false }
  end
  local items = self:pickerFiltered()
  local selected = util.clamp(tonumber(picker.selected) or 1, 1, math.max(1, #items))
  picker.selected = selected
  return {
    items = items,
    selected = selected,
    scroll = tonumber(picker.scroll) or 1,
    query = picker.query or "",
    kind = picker.kind or "all",
    searchFocused = picker.searchFocused == true,
    loading = picker.loading == true,
    error = (#self.pickerItems == 0) and self.pickerError or nil,
    note = self.scanError,
  }
end

function App:openPicker()
  self.state.overlay = "picker"
  self.state.picker = {
    query = "",
    kind = "all",
    selected = 1,
    scroll = 1,
    searchFocused = false,
    loading = true,
  }
  self.pickerError = nil
  self.dirty = true
  self:render()

  local list, err = self.sources:list(true)
  self.pickerItems = list or {}
  self.pickerError = (#self.pickerItems == 0) and (err or "no resources found") or nil
  self.scanError = err
  self.state.picker.loading = false
  self.state.picker.selected = 1
  self.state.picker.scroll = 1
  if not self.sources:isAE2() and not self:demoForced() then
    self:toast("AE2 not detected - only demo/custom sources are listed", "error")
  end
  self.dirty = true
end

function App:refreshPicker()
  if self.state.overlay ~= "picker" then return end
  self.state.picker.loading = true
  self.dirty = true
  self:render()
  local list, err = self.sources:refresh()
  self.pickerItems = list or {}
  self.pickerError = (#self.pickerItems == 0) and (err or "no resources found") or nil
  self.scanError = err
  self.state.picker.loading = false
  self.state.picker.selected = 1
  if not self.sources:isAE2() and not self:demoForced() then
    self:toast("AE2 not detected - only demo/custom sources are listed", "error")
  end
  self.dirty = true
end

function App:movePicker(delta)
  local view = self:getPickerView()
  if #view.items == 0 then return end
  self.state.picker.selected = util.clamp(view.selected + delta, 1, #view.items)
  self.dirty = true
end

function App:pickSelected()
  local view = self:getPickerView()
  local item = view.items[view.selected]
  if not item then return end
  self:selectResource(item)
  self.state.overlay = nil
  self.state.picker = nil
  self:toast("Selected " .. util.truncate(item.label, 40))
  self.dirty = true
end

function App:cycleResource(delta)
  if #self.pickerItems == 0 then
    local list = self.sources:list()
    self.pickerItems = list or {}
  end
  if #self.pickerItems == 0 then
    self:toast("No resources available", "error")
    return
  end
  local current = self.state.selectedKey
  local index = nil
  for i = 1, #self.pickerItems do
    if self.pickerItems[i].key == current then index = i; break end
  end
  if not index then index = delta > 0 and 0 or 1 end
  local n = #self.pickerItems
  index = ((index - 1 + delta) % n) + 1
  self:selectResource(self.pickerItems[index])
end

function App:appendPickerQuery(text)
  local picker = self.state.picker
  if not picker then return end
  picker.query = (picker.query or "") .. text
  picker.selected = 1
  self.dirty = true
end

function App:backspacePickerQuery()
  local picker = self.state.picker
  if not picker then return end
  local q = picker.query or ""
  if q == "" then return end
  local okU, unicode = pcall(require, "unicode")
  if okU and unicode and unicode.sub and unicode.len then
    q = unicode.sub(q, 1, math.max(0, unicode.len(q) - 1))
  else
    q = q:sub(1, -2)
  end
  picker.query = q
  picker.selected = 1
  self.dirty = true
end

function App:cyclePickerKind()
  local picker = self.state.picker
  if not picker then return end
  local current = picker.kind or "all"
  local index = 1
  for i = 1, #PICKER_KINDS do
    if PICKER_KINDS[i] == current then index = i; break end
  end
  picker.kind = PICKER_KINDS[(index % #PICKER_KINDS) + 1]
  picker.selected = 1
  self.dirty = true
end

-- ---------------------------------------------------------------------------
-- Export
-- ---------------------------------------------------------------------------

local function csvQuote(value)
  local s = tostring(value or "")
  if s:find('[,"\n\r]') then
    return '"' .. s:gsub('"', '""') .. '"'
  end
  return s
end

function App:exportCSV()
  local meta = self.state.selected
  local history = self.state.history
  if not meta or not history or history:count() == 0 then
    self:toast("Nothing to export yet", "error")
    return
  end

  local okDate, stamp = pcall(os.date, "%Y%m%d_%H%M%S")
  if not okDate or not stamp then stamp = tostring(math.floor(self:now())) end
  local name = util.sanitizeFilename(meta.key)
  local dir = self.config.exportDir or "/home"
  local path = dir .. "/resource_" .. name .. "_" .. stamp .. ".csv"

  local function writeTo(target)
    local ok, f = pcall(io.open, target, "w")
    if not ok or not f then return false, "cannot open " .. target end
    local okWrite = pcall(f.write, f,
      "elapsed_seconds,game_seconds,game_clock,value,unit,label\n")
    if okWrite then
      for i = 1, history:count() do
        local t = history:timeAt(i)
        local v = history:valueAt(i)
        local g = self:gameAt(t)
        local line = string.format("%.3f,%.3f,%s,%.6f,%s,%s\n",
          t, g, util.formatClock(g), v, csvQuote(meta.unit), csvQuote(meta.label))
        local okLine = pcall(f.write, f, line)
        if not okLine then
          okWrite = false
          break
        end
      end
    end
    pcall(f.close, f)
    return okWrite
  end

  local ok, err = writeTo(path)
  if not ok and self.config.fallbackDataPath then
    local alt = "/tmp/resource_" .. name .. "_" .. stamp .. ".csv"
    local okAlt = writeTo(alt)
    if okAlt then
      path, ok, err = alt, true, nil
    end
  end

  if ok then
    self:toast("Exported " .. tostring(history:count()) .. " rows to " .. path)
  else
    self:toast("Export failed: " .. tostring(err), "error")
  end
end

-- ---------------------------------------------------------------------------
-- Actions and input
-- ---------------------------------------------------------------------------

function App:toast(text, kind)
  self.state.toast = {
    text = text,
    kind = kind or "info",
    expires = self:now() + 3.5,
  }
  self.dirty = true
end

function App:togglePause()
  self.state.paused = not self.state.paused
  if not self.state.paused then
    self.nextSampleAt = self:now()
    self:toast("Sampling resumed")
  else
    self:toast("Sampling paused")
  end
  self.dirty = true
end

function App:action(name, arg)
  if name == "range" then
    self.state.window = util.clamp(tonumber(arg) or self.state.window, self.config.minWindow, self.config.maxWindow)
    self.state.follow = true
    self.state.viewEnd = self:now()
    self.state.cursorT = nil
    self.dirty = true
  elseif name == "cycle" then
    self:cycleResource(tonumber(arg) or 1)
  elseif name == "pause" then
    self:togglePause()
  elseif name == "picker" then
    self:openPicker()
  elseif name == "picker_refresh" then
    self:refreshPicker()
  elseif name == "picker_search" then
    if self.state.picker then self.state.picker.searchFocused = true end
    self.dirty = true
  elseif name == "picker_pageup" then
    self:movePicker(-8)
  elseif name == "picker_pagedown" then
    self:movePicker(8)
  elseif name == "picker_kind" then
    if self.state.picker then
      self.state.picker.kind = arg or "all"
      self.state.picker.selected = 1
    end
    self.dirty = true
  elseif name == "picker_pick" then
    if arg then
      self:selectResource(arg)
      self.state.overlay = nil
      self.state.picker = nil
      self:toast("Selected " .. util.truncate(arg.label or arg.key, 40))
    end
    self.dirty = true
  elseif name == "export" then
    self:exportCSV()
  elseif name == "help" then
    self.state.overlay = "help"
    self.helpScroll = 1
    self.dirty = true
  elseif name == "zero" then
    self.state.zero = not self.state.zero
    self.dirty = true
  elseif name == "follow" then
    self.state.follow = true
    self.state.viewEnd = self:now()
    self.state.cursorT = nil
    self.dirty = true
  elseif name == "close" then
    self.state.overlay = nil
    self.state.picker = nil
    self.dirty = true
  elseif name == "quit" then
    self.running = false
  end
end

function App:keyAllowed(code)
  local now = util.now()
  local last = self.keyDebounce[code]
  if last and now - last < 0.25 then return false end
  self.keyDebounce[code] = now
  return true
end

function App:onKey(char, code)
  local c = type(char) == "number" and char or 0
  local ch = (c >= 32 and c <= 126) and string.char(c) or ""
  local lower = ch ~= "" and string.lower(ch) or ""

  if self.state.overlay == "help" then
    if code == K.up then
      self.helpScroll = math.max(1, (self.helpScroll or 1) - 1)
      self.dirty = true
    elseif code == K.down then
      self.helpScroll = (self.helpScroll or 1) + 1
      self.dirty = true
    elseif code == K.escape or code == K.enter or lower == "q" or lower == "h" or ch == "?" then
      self:action("close")
    end
    return
  end

  if self.state.overlay == "picker" then
    local picker = self.state.picker
    if not picker then return end
    if code == K.escape then
      if picker.searchFocused and (picker.query or "") ~= "" then
        picker.searchFocused = false
      else
        self:action("close")
      end
      self.dirty = true
      return
    elseif code == K.enter then
      self:pickSelected()
      return
    elseif code == K.up then
      self:movePicker(-1)
      return
    elseif code == K.down then
      self:movePicker(1)
      return
    elseif code == K.pageUp then
      self:movePicker(-8)
      return
    elseif code == K.pageDown then
      self:movePicker(8)
      return
    elseif code == K.back then
      self:backspacePickerQuery()
      return
    elseif code == K.tab then
      self:cyclePickerKind()
      return
    end

    if ch == "/" and not picker.searchFocused then
      picker.searchFocused = true
      self.dirty = true
      return
    end
    if ch ~= "" then
      picker.searchFocused = true
      self:appendPickerQuery(ch)
    end
    return
  end

  if code == K.left then
    self:panBy(-self.state.window * 0.1)
  elseif code == K.right then
    self:panBy(self.state.window * 0.1)
  elseif code == K.up then
    self:cycleResource(-1)
  elseif code == K.down then
    self:cycleResource(1)
  elseif code == K.escape then
    self.state.cursorT = nil
    self.dirty = true
  elseif code == K.space then
    if self:keyAllowed(code) then self:togglePause() end
  elseif ch == "+" or ch == "=" then
    if self:keyAllowed(code) then self:zoom(1 / 1.25) end
  elseif ch == "-" or ch == "_" then
    if self:keyAllowed(code) then self:zoom(1.25) end
  elseif lower == "p" then
    if self:keyAllowed(code) then self:togglePause() end
  elseif lower == "r" then
    if self:keyAllowed(code) then self:action("follow") end
  elseif lower == "z" then
    if self:keyAllowed(code) then self:action("zero") end
  elseif lower == "t" then
    if self:keyAllowed(code) then self:action("picker") end
  elseif lower == "e" then
    if self:keyAllowed(code) then self:action("export") end
  elseif lower == "h" or ch == "?" then
    if self:keyAllowed(code) then self:action("help") end
  elseif lower == "q" then
    if self:keyAllowed(code) then self:action("quit") end
  end
end

function App:handleEvent(name, a, b, c, d, e)
  if name == "interrupted" then
    self:save(false)
    self.running = false
    return
  end

  if name == "term_unavailable" then
    self.running = false
    return
  end

  if name == "screen_resized" then
    if not a or a == self.screenAddress then
      self:refreshResolution()
    end
    return
  end

  if name == "component_removed" then
    if a == self.screenAddress or b == "gpu" or b == "screen" or (self.gpu and a == self.gpu.address) then
      local ok = self:setupScreen()
      if not ok then self.running = false end
      if self.ui then self.ui:resize() end
      self.dirty = true
      return
    end
    if self.sources and (b == "me_controller" or b == "me_interface" or a == self.sources.meAddress) then
      self.sources:detect(true)
      self.scanError = self.sources.lastError
      self:toast("AE2 component removed", "error")
      self.dirty = true
    end
    return
  end

  if name == "component_added" then
    if b == "me_controller" or b == "me_interface" then
      self.sources:detect(true)
      self.scanError = nil
      if not self.state.selected then
        local list = self.sources:list(true)
        self.pickerItems = list or {}
        self:selectInitial()
      end
      self:toast("AE2 component connected")
      self.dirty = true
    end
    return
  end

  if name == "touch" then
    if a and self.screenAddress and a ~= self.screenAddress then return end
    if self.state.overlay == "help" then
      local action = self.ui:hit(b, c)
      if action then self:action(action) else self:action("close") end
      return
    end
    if self.state.overlay == "picker" then
      local action, arg = self.ui:hit(b, c)
      if action then self:action(action, arg) end
      return
    end
    local action, arg = self.ui:hit(b, c)
    if action then
      self:action(action, arg)
    else
      self.cursorFromTouch(b, c)
    end
    return
  end

  if name == "drag" then
    if a and self.screenAddress and a ~= self.screenAddress then return end
    if self.state.overlay == nil then self:onDrag(b) end
    return
  end

  if name == "drop" then
    self.drag = nil
    return
  end

  if name == "scroll" then
    if a and self.screenAddress and a ~= self.screenAddress then return end
    local direction = d or 0
    if self.state.overlay == "picker" then
      self:movePicker(direction > 0 and -3 or 3)
      return
    end
    if self.state.overlay then return end
    local plot = self.ui and self.ui.lastPlot
    if plot and b >= plot.x1 and b <= plot.x2 and c >= plot.y1 and c <= plot.y2 then
      self:zoom(direction > 0 and (1 / 1.25) or 1.25, b)
    end
    return
  end

  if name == "key_down" then
    self:onKey(b, c)
    return
  end
end

-- ---------------------------------------------------------------------------
-- Rendering / main loop
-- ---------------------------------------------------------------------------

function App:render()
  if not self.ui then return end
  self.ui:render()
end

function App:splash(text)
  if not self.gpu then return end
  pcall(function()
    local w, h = self.gpu.getResolution()
    self.gpu.setBackground(0x0B1016)
    self.gpu.setForeground(0xE6EEF6)
    self.gpu.fill(1, 1, w, h, " ")
    self.gpu.set(2, 2, tostring(text))
  end)
end

function App:run()
  local ok, err = self:setupScreen()
  if not ok then return false, err end

  self.ui = UI.new(self)
  self:splash("Loading resource chart...")
  self:loadState()
  self:initClock(self.state.clock)
  self:loadEntries()

  self.sources = Sources.new(self.config)
  self:refreshStartup()
  self:selectInitial()

  local selectedKind = self.state.selected and self.state.selected.kind or nil
  if not self:demoForced() and (selectedKind == nil or selectedKind == "demo") then
    if not self.sources:isAE2() then
      self:toast("No AE2 component found - demo mode. Press T to pick.", "error")
    elseif not self:hasRealSource() then
      self:toast("AE2 connected but no items/fluids/power - demo mode.", "error")
    end
  end

  self.nextSampleAt = self:now()
  self.lastSave = self:now()
  self.lastDraw = -math.huge
  self.dirty = true

  if self.config.showHelpOnStart then
    self.state.overlay = "help"
  end

  self:render()

  while self.running do
    local now = self:now()
    if not self.state.paused and now >= self.nextSampleAt then
      self:sampleNow()
      self.nextSampleAt = now + self.config.sampleInterval
    end

    local timeout = 0.25
    if not self.state.paused then
      local untilSample = self.nextSampleAt - self:now()
      if untilSample < timeout then timeout = math.max(0.02, untilSample) end
    end

    local name, a, b, c, d, e = event.pull(timeout)
    if name then self:handleEvent(name, a, b, c, d, e) end

    now = self:now()
    if self.running and (self.dirty or now - self.lastDraw >= 1) then
      self:render()
      self.lastDraw = now
      self.dirty = false
    end

    if self.unsaved and now - self.lastSave >= self.config.saveInterval then
      self:save(false)
    end
  end

  self:save(false)
  return true
end

function App:fatal(err)
  util.log("FATAL: " .. tostring(err))
  pcall(function() self:save(false) end)
  if not self.gpu then
    print(tostring(err))
    return
  end
  if self.gpu then
    pcall(function()
      local w, h = self.gpu.getResolution()
      self.gpu.setBackground(0x200000)
      self.gpu.setForeground(0xFFFFFF)
      self.gpu.fill(1, 1, w, h, " ")
      self.gpu.set(2, 2, "Resource chart crashed:")
      local y = 4
      for line in tostring(err):gmatch("[^\n]+") do
        if y > h - 1 then break end
        self.gpu.set(2, y, util.truncate(line, w - 3))
        y = y + 1
      end
      self.gpu.set(2, h, "See /home/resource_chart.log")
    end)
  end
end

return App

]===],
  ["rc_config"] = [===[
-- rc_config.lua -- defaults and optional user overrides.
--
-- You normally do not need to edit this file. If you want to change settings
-- without touching the program, create /home/resource_chart.cfg containing a
-- table, for example:
--
--   return {
--     sampleInterval = 30,
--     defaultWindow  = 3600,
--     dataPath       = "/home/.resource_chart.dat",
--   }
--
-- Custom data sources can be added there too (see the example at the bottom
-- of this file). A custom source is sampled by a Lua function, so it can read
-- any OpenComputers component available to the computer.

local M = {}

M.defaults = {
  -- Sampling and retention.
  sampleInterval = 15,          -- real seconds between samples
  retention = 7 * 86400,        -- keep seven real days
  maxPoints = 2400,             -- per resource; older data is averaged down
  maxResources = 4,             -- histories kept on disk / in RAM
  saveInterval = 60,            -- seconds between automatic saves

  -- View.
  defaultWindow = 3600,         -- one hour
  minWindow = 60,
  maxWindow = 30 * 86400,
  zeroBaseline = false,         -- set true to always include zero on the Y axis
  follow = true,

  -- Data source options.
  meAddress = nil,              -- optional component address to force
  includePower = true,          -- add ME network stored power as a resource
  includeDemo = true,           -- add synthetic demo resources
  demo = "auto",                -- "auto" | true | false
  customSources = {},           -- see example below

  -- Storage / export.
  dataPath = "/home/.resource_chart.dat",
  fallbackDataPath = "/tmp/resource_chart.dat",
  exportDir = "/home",

  -- Ranges shown as buttons. Keep these sorted, smallest first.
  ranges = { 300, 1800, 3600, 21600, 86400, 604800 },

  -- UI.
  title = "RESOURCE MONITOR",
  showHelpOnStart = false,
}

-- User config loader. Missing or broken files are ignored (the program still
-- starts with defaults), so a typo in the config cannot brick the display.
function M.load(path)
  local cfg = {}
  for k, v in pairs(M.defaults) do cfg[k] = v end

  if not path then return cfg end
  local ok, chunk = pcall(loadfile, path)
  if not ok or not chunk then return cfg end
  local okRun, user = pcall(chunk)
  if not okRun or type(user) ~= "table" then return cfg end

  for k, v in pairs(user) do
    cfg[k] = v
  end

  -- Basic sanity checks. Bad values fall back to defaults instead of crashing
  -- in the middle of a chart redraw.
  cfg.sampleInterval = tonumber(cfg.sampleInterval) or M.defaults.sampleInterval
  if cfg.sampleInterval < 1 then cfg.sampleInterval = 1 end
  cfg.retention = tonumber(cfg.retention) or M.defaults.retention
  cfg.maxPoints = math.floor(tonumber(cfg.maxPoints) or M.defaults.maxPoints)
  cfg.maxResources = math.floor(tonumber(cfg.maxResources) or M.defaults.maxResources)
  cfg.saveInterval = tonumber(cfg.saveInterval) or M.defaults.saveInterval
  cfg.defaultWindow = tonumber(cfg.defaultWindow) or M.defaults.defaultWindow
  cfg.minWindow = tonumber(cfg.minWindow) or M.defaults.minWindow
  cfg.maxWindow = tonumber(cfg.maxWindow) or M.defaults.maxWindow
  if cfg.maxPoints < 64 then cfg.maxPoints = 64 end
  if cfg.maxResources < 1 then cfg.maxResources = 1 end
  if cfg.maxWindow < cfg.minWindow then cfg.maxWindow = cfg.minWindow end
  if cfg.defaultWindow < cfg.minWindow then cfg.defaultWindow = cfg.minWindow end
  if cfg.defaultWindow > cfg.maxWindow then cfg.defaultWindow = cfg.maxWindow end
  if type(cfg.ranges) ~= "table" or #cfg.ranges == 0 then
    cfg.ranges = M.defaults.ranges
  else
    local ranges = {}
    for i = 1, #cfg.ranges do
      local value = tonumber(cfg.ranges[i])
      if value and value > 0 then ranges[#ranges + 1] = value end
    end
    if #ranges == 0 then
      cfg.ranges = M.defaults.ranges
    else
      table.sort(ranges)
      cfg.ranges = ranges
    end
  end

  return cfg
end

-- ---------------------------------------------------------------------------
-- CUSTOM SOURCE EXAMPLE
-- ---------------------------------------------------------------------------
-- Put this in /home/resource_chart.cfg. `sample` must return value[, max].
-- Returning nil, "reason" records a source error without adding a fake zero.
--
-- return {
--   customSources = {
--     {
--       key = "custom:computer_energy",
--       label = "Computer Energy",
--       unit = "OC",
--       kind = "custom",
--       sample = function()
--         local computer = require("computer")
--         return computer.energy(), computer.maxEnergy()
--       end,
--     },
--   },
-- }
--
-- For a GT machine/battery, first inspect its real method names with:
--   local component = require("component")
--   local addr = component.list("gt_machine")()
--   for name in pairs(component.methods(addr)) do print(name) end
-- then call the getter you found inside sample(). Method names differ between
-- GTNH addons/machine versions, so they are intentionally not hard-coded here.

return M

]===],
}

local __order = { "rc_util", "rc_theme", "rc_chart", "rc_history", "rc_store", "rc_sources", "rc_ui", "rc_app", "rc_config" }
for __i = 1, #__order do
  local __name = __order[__i]
  local __chunk, __err = load(__sources[__name], "@" .. __name .. ".lua")
  if not __chunk then
    error("Cannot load embedded module '" .. __name .. "': " .. tostring(__err))
  end
  package.loaded[__name] = __chunk()
end
__sources = nil
__order = nil

-- resource_chart.lua -- entry point for the OpenComputers resource chart.
--
-- Target: GTNH 2.9.0-beta-2 (Minecraft 1.7.10, OpenComputers 1.8.x / OpenOS).
-- The program only uses documented OC APIs and Lua 5.2/5.3 compatible syntax.
--
-- Usage (in the OpenOS shell):
--   cd /home/oc-resource-chart
--   lua resource_chart.lua
--
-- Options:
--   --demo      force the synthetic demo sources
--   --no-demo   hide demo sources
--   --reset     delete the saved history before starting
--   --help      show command line help

local function scriptDirectory()
  if debug and debug.getinfo then
    local info = debug.getinfo(1, "S")
    if info and info.source then
      local source = info.source
      source = source:gsub("^@", "")
      local dir = source:match("^(.*[/\\])")
      if dir and dir ~= "" then return dir end
    end
  end
  return "./"
end

local base = scriptDirectory()
package.path = base .. "?.lua;" .. base .. "lib/?.lua;" .. package.path

local args = { ... }
local options = {}
for i = 1, #args do
  local a = args[i]
  if a == "--demo" then
    options.demo = true
  elseif a == "--no-demo" then
    options.demo = false
  elseif a == "--reset" then
    options.reset = true
  elseif a == "--help" or a == "-h" then
    options.help = true
  end
end

if options.help then
  print("resource_chart.lua -- OpenComputers resource history chart")
  print("")
  print("  lua resource_chart.lua [--demo|--no-demo] [--reset]")
  print("")
  print("  --demo      use synthetic demo series only")
  print("  --no-demo   hide synthetic demo series")
  print("  --reset     delete saved history before starting")
  print("")
  print("Controls: T picker, P pause, E export, H help, Q quit.")
  return
end

local okConfig, configModule = pcall(require, "rc_config")
if not okConfig or not configModule then
  print("Cannot load rc_config.lua: " .. tostring(configModule))
  return
end

local config = configModule.load("/home/resource_chart.cfg")
if options.demo ~= nil then
  config.demo = options.demo
  config.includeDemo = true
end

if options.reset then
  os.remove(config.dataPath)
  os.remove(config.fallbackDataPath)
  print("Saved history deleted.")
end

local okApp, App = pcall(require, "rc_app")
if not okApp or not App then
  print("Cannot load rc_app.lua: " .. tostring(App))
  return
end

local app = App.new(config)
local ok, result, err = xpcall(function()
  return app:run()
end, function(message)
  if debug and debug.traceback then
    return debug.traceback(tostring(message), 2)
  end
  return tostring(message)
end)

if not ok then
  app:fatal(result)
  return
end

if result == false then
  print(err or "Startup failed.")
end

