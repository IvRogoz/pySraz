-- Trivia Strategy Game (LÖVE) with Galaxy Shader BG + Audio FFT texture
-- Drop this folder onto love.exe
-- Requires: questions.csv + shadertoy.mp3 + pawn.png + flag.png next to this file.

local DEFAULT_W, DEFAULT_H = 900, 700
local FPS = 60
local HOLE_COUNT = 6

-- -----------------------------
-- Helpers
-- -----------------------------
local function clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

local function rgb255(r, g, b, a)
  return (r or 0) / 255, (g or 0) / 255, (b or 0) / 255, (a == nil and 1 or (a / 255))
end

local function setColor255(r, g, b, a)
  love.graphics.setColor(rgb255(r, g, b, a))
end

local function pointInRect(px, py, x, y, w, h)
  return px >= x and px <= x + w and py >= y and py <= y + h
end

local function shuffle(t)
  for i = #t, 2, -1 do
    local j = love.math.random(i)
    t[i], t[j] = t[j], t[i]
  end
end

-- Minimal CSV splitter (handles simple quoted fields)
local function csvSplitLine(line)
  local out = {}
  local i = 1
  local len = #line
  while i <= len do
    local c = line:sub(i, i)
    if c == '"' then
      local j = i + 1
      local buf = {}
      while j <= len do
        local cj = line:sub(j, j)
        if cj == '"' then
          if line:sub(j + 1, j + 1) == '"' then
            table.insert(buf, '"')
            j = j + 2
          else
            j = j + 1
            break
          end
        else
          table.insert(buf, cj)
          j = j + 1
        end
      end
      table.insert(out, table.concat(buf))
      if line:sub(j, j) == "," then j = j + 1 end
      i = j
    else
      local j = i
      while j <= len and line:sub(j, j) ~= "," do j = j + 1 end
      table.insert(out, (line:sub(i, j - 1)):match("^%s*(.-)%s*$"))
      i = j + 1
    end
  end
  return out
end

-- -----------------------------
-- Colors / Categories
-- -----------------------------
local CATEGORY_COLORS = {
  Sport   = {0, 200, 0},
  History = {139, 69, 19},
  Music   = {128, 0, 128},
  Science = {0, 255, 255},
  Art     = {255, 192, 203},
  Random  = {128, 128, 128},
}

local PLAYER_COLORS = {
  {220, 20, 60},
  {30, 144, 255},
  {34, 139, 34},
  {255, 215, 0},
}

-- -----------------------------
-- Audio FFT -> iChannel0 Image
-- -----------------------------
local AudioFFT = {}
AudioFFT.__index = AudioFFT

local function isPixelFormatSupported(fmt)
  local ok = pcall(function()
    love.image.newImageData(2, 2, fmt)
  end)
  return ok
end

function AudioFFT.new(filename)
  local self = setmetatable({}, AudioFFT)

  self.filename = filename

  self.source = love.audio.newSource(filename, "stream")
  self.source:setLooping(true)
  self.source:play()

  self.soundData = love.sound.newSoundData(filename)
  self.sampleRate = self.soundData:getSampleRate()
  self.channels = self.soundData:getChannels()
  self.sampleCount = self.soundData:getSampleCount()

  self.frameCount = math.floor(self.sampleCount / self.channels)

  self.FFT_TEX_W = 512
  self.FFT_TEX_H = 2
  self.FFT_WINDOW = 4096
  self.SMOOTH = 0.25

  self.prev = {}
  self.now = {}
  for i = 1, self.FFT_TEX_W do
    self.prev[i] = 0.0
    self.now[i] = 0.0
  end

  self.fftHz = 30
  self.fftAccum = 0

  self.hann = {}
  local N = self.FFT_WINDOW
  for n = 0, N - 1 do
    self.hann[n + 1] = 0.5 * (1.0 - math.cos((2.0 * math.pi * n) / (N - 1)))
  end

  self.re = {}
  self.im = {}
  for i = 1, N do
    self.re[i] = 0.0
    self.im[i] = 0.0
  end

  self.bitrev = {}
  do
    local bits = math.floor(math.log(N) / math.log(2) + 0.5)
    for i = 0, N - 1 do
      local x = i
      local y = 0
      for _ = 1, bits do
        y = y * 2 + (x % 2)
        x = math.floor(x / 2)
      end
      self.bitrev[i + 1] = y + 1
    end
  end

  self.twiddle = {}
  do
    local m = 2
    while m <= N do
      local half = m / 2
      local step = (2 * math.pi) / m
      local cosT = {}
      local sinT = {}
      for k = 0, half - 1 do
        cosT[k + 1] = math.cos(step * k)
        sinT[k + 1] = -math.sin(step * k)
      end
      self.twiddle[m] = {cos = cosT, sin = sinT}
      m = m * 2
    end
  end

  self.pixelFormat = isPixelFormatSupported("r8") and "r8" or "rgba8"
  self.imageData = love.image.newImageData(self.FFT_TEX_W, self.FFT_TEX_H, self.pixelFormat)
  self.image = love.graphics.newImage(self.imageData)
  self.image:setFilter("linear", "linear")
  self.image:setWrap("clamp", "clamp")

  return self
end

function AudioFFT:getTimeSeconds()
  local ok, pos = pcall(function() return self.source:tell("seconds") end)
  if ok and pos then return pos end
  return 0
end

function AudioFFT:getMonoSample(frameIndex)
  if self.channels == 1 then
    return self.soundData:getSample(frameIndex)
  else
    local base = frameIndex * self.channels
    local l = self.soundData:getSample(base)
    local r = self.soundData:getSample(base + 1)
    return 0.5 * (l + r)
  end
end

function AudioFFT:fftInPlace()
  local N = self.FFT_WINDOW
  local re, im = self.re, self.im

  local m = 2
  while m <= N do
    local half = m / 2
    local tw = self.twiddle[m]
    local cosT, sinT = tw.cos, tw.sin

    for start = 1, N, m do
      for k = 0, half - 1 do
        local i1 = start + k
        local i2 = i1 + half

        local wr = cosT[k + 1]
        local wi = sinT[k + 1]

        local tr = wr * re[i2] - wi * im[i2]
        local ti = wr * im[i2] + wi * re[i2]

        local ur = re[i1]
        local ui = im[i1]

        re[i1] = ur + tr
        im[i1] = ui + ti
        re[i2] = ur - tr
        im[i2] = ui - ti
      end
    end

    m = m * 2
  end
end

function AudioFFT:update(dt)
  self.fftAccum = self.fftAccum + dt
  local period = 1 / self.fftHz
  if self.fftAccum < period then
    return
  end
  self.fftAccum = self.fftAccum - period

  local t = self:getTimeSeconds()
  local centerFrame = math.floor((t * self.sampleRate)) % self.frameCount
  local half = math.floor(self.FFT_WINDOW / 2)
  local startFrame = centerFrame - half

  local N = self.FFT_WINDOW
  for i = 0, N - 1 do
    local f = startFrame + i
    f = f % self.frameCount
    if f < 0 then f = f + self.frameCount end

    local s = self:getMonoSample(f)
    s = s * self.hann[i + 1]

    local j = self.bitrev[i + 1]
    self.re[j] = s
    self.im[j] = 0.0
  end

  self:fftInPlace()

  local bins = (N / 2) + 1
  local mag = {}
  local maxv = 1e-9
  for k = 1, bins do
    local rr = self.re[k]
    local ii = self.im[k]
    local m = math.sqrt(rr * rr + ii * ii)
    m = math.log(1.0 + m)
    mag[k] = m
    if m > maxv then maxv = m end
  end
  for k = 1, bins do
    mag[k] = mag[k] / maxv
  end

  local take = math.max(32, math.floor(bins * 0.35))
  local W = self.FFT_TEX_W

  for x = 0, W - 1 do
    local pos = (x * (take - 1)) / (W - 1)
    local i0 = math.floor(pos)
    local frac = pos - i0
    local a = mag[i0 + 1] or 0
    local b = mag[i0 + 2] or a
    local v = a * (1 - frac) + b * frac

    v = clamp(v * 1.25, 0, 1)
    v = math.sqrt(v)
    self.now[x + 1] = v
  end

  for i = 1, W do
    self.prev[i] = (1 - self.SMOOTH) * self.prev[i] + self.SMOOTH * self.now[i]
  end

  if self.pixelFormat == "r8" then
    for x = 0, W - 1 do
      local v = self.prev[x + 1]
      self.imageData:setPixel(x, 0, v, 0, 0, 1)
      self.imageData:setPixel(x, 1, v, 0, 0, 1)
    end
  else
    for x = 0, W - 1 do
      local v = self.prev[x + 1]
      self.imageData:setPixel(x, 0, v, v, v, 1)
      self.imageData:setPixel(x, 1, v, v, v, 1)
    end
  end

  self.image:replacePixels(self.imageData)
end

-- -----------------------------
-- Galaxy shader (LÖVE GLSL)
-- -----------------------------
local GALAXY_SHADER = [[
extern float iTime;
extern vec3  iResolution;
extern Image iChannel0;

float field(vec3 p, float s) {
  float strength = 7. + .03 * log(1.e-6 + fract(sin(iTime) * 4373.11));
  float accum = s/4.;
  float prev = 0.;
  float tw = 0.;
  for (int i = 0; i < 26; ++i) {
    float mag = dot(p, p);
    p = abs(p) / mag + vec3(-.5, -.4, -1.5);
    float w = exp(-float(i) / 7.);
    accum += w * exp(-strength * pow(abs(mag - prev), 2.2));
    tw += w;
    prev = mag;
  }
  return max(0., 5. * accum / tw - .7);
}

float field2(vec3 p, float s) {
  float strength = 7. + .03 * log(1.e-6 + fract(sin(iTime) * 4373.11));
  float accum = s/4.;
  float prev = 0.;
  float tw = 0.;
  for (int i = 0; i < 18; ++i) {
    float mag = dot(p, p);
    p = abs(p) / mag + vec3(-.5, -.4, -1.5);
    float w = exp(-float(i) / 7.);
    accum += w * exp(-strength * pow(abs(mag - prev), 2.2));
    tw += w;
    prev = mag;
  }
  return max(0., 5. * accum / tw - .7);
}

vec3 nrand3(vec2 co) {
  vec3 a = fract( cos( co.x*8.3e-3 + co.y )*vec3(1.3e5, 4.7e5, 2.9e5) );
  vec3 b = fract( sin( co.x*0.3e-3 + co.y )*vec3(8.1e5, 1.0e5, 0.1e5) );
  return mix(a, b, 0.5);
}

vec4 effect(vec4 color, Image base, vec2 tc, vec2 sc) {
  vec4 baseColor = Texel(base, tc);

  vec2 fragCoord = sc;
  vec2 uv = 2. * fragCoord.xy / iResolution.xy - 1.;
  vec2 uvs = uv * iResolution.xy / max(iResolution.x, iResolution.y);

  vec3 p = vec3(uvs / 4., 0.) + vec3(1., -1.3, 0.);
  p += .2 * vec3(sin(iTime / 16.), sin(iTime / 12.),  sin(iTime / 128.));

  float freqs0 = Texel(iChannel0, vec2(0.01, 0.25)).r;
  float freqs1 = Texel(iChannel0, vec2(0.07, 0.25)).r;
  float freqs2 = Texel(iChannel0, vec2(0.15, 0.25)).r;
  float freqs3 = Texel(iChannel0, vec2(0.30, 0.25)).r;

  float bass = pow(freqs0, 0.6);
  float mid  = pow(freqs1, 0.8);
  float hi   = pow(freqs3, 0.9);

  float t = field(p, freqs2 + 0.08 + 0.35 * mid);
  float v = (1. - exp((abs(uv.x) - 1.) * 6.)) * (1. - exp((abs(uv.y) - 1.) * 6.));

  vec3 p2 = vec3(uvs / (4.+sin(iTime*0.11)*0.2+0.2+sin(iTime*0.15)*0.3+0.4), 1.5) + vec3(2., -1.3, -1.);
  p2 += 0.25 * vec3(sin(iTime / 16.), sin(iTime / 12.),  sin(iTime / 128.));
  float t2 = field2(p2, freqs3 + 0.10 + 0.45 * hi);

  vec4 c2 = mix(.4, 1., v) * vec4(1.3 * t2 * t2 * t2,
                                  1.8 * t2 * t2,
                                  t2 * (freqs0 + 0.15 + 0.6*bass),
                                  1.0);

  vec2 seed = p.xy * 2.0;
  seed = floor(seed * iResolution.x);
  vec3 rnd = nrand3(seed);
  vec4 starcolor = vec4(pow(rnd.y,40.0));

  vec2 seed2 = p2.xy * 2.0;
  seed2 = floor(seed2 * iResolution.x);
  vec3 rnd2 = nrand3(seed2);
  starcolor += vec4(pow(rnd2.y,40.0));

  vec4 col = mix(freqs3-.3, 1., v) * vec4(1.5*freqs2 * t * t* t ,
                                          1.2*freqs1 * t * t,
                                          freqs3*t, 1.0)
            + c2 + starcolor;

  col.a = 1.0;
  return col;
}
]]

-- -----------------------------
-- Game data
-- -----------------------------
local questionsByCategory = {}

local function loadQuestionsCSV(filename)
  questionsByCategory = {}
  if not love.filesystem.getInfo(filename) then
    print("Warning: missing " .. filename)
    return
  end
  for line in love.filesystem.lines(filename) do
    if line and #line > 0 then
      local row = csvSplitLine(line)
      if #row >= 6 then
        local cat, q, correct, w1, w2, w3 = row[1], row[2], row[3], row[4], row[5], row[6]
        cat = (cat or ""):match("^%s*(.-)%s*$")
        questionsByCategory[cat] = questionsByCategory[cat] or {}
        table.insert(questionsByCategory[cat], {
          question = q,
          correct = correct,
          wrong = {w1, w2, w3},
        })
      end
    end
  end
end

local function getRandomQuestionAny()
  local cats = {}
  for k, v in pairs(questionsByCategory) do
    if v and #v > 0 then table.insert(cats, k) end
  end
  if #cats == 0 then return nil end
  local cat = cats[love.math.random(#cats)]
  local list = questionsByCategory[cat]
  return list[love.math.random(#list)], cat
end

local function getRandomQuestionFrom(category)
  local list = questionsByCategory[category]
  if list and #list > 0 then
    return list[love.math.random(#list)], category
  end
  return getRandomQuestionAny()
end

-- -----------------------------
-- UI / Buttons
-- -----------------------------
local Button = {}
Button.__index = Button

function Button.new(relx, rely, w, h, text, color, hoverColor, action)
  local self = setmetatable({}, Button)
  self.relx, self.rely = relx, rely
  self.w, self.h = w, h
  self.text = text
  self.color = color
  self.hoverColor = hoverColor
  self.action = action
  self.x, self.y = 0, 0
  self.hovered = false
  return self
end

function Button:updatePos(cx, cy)
  self.x = cx + self.relx - self.w / 2
  self.y = cy + self.rely - self.h / 2
end

function Button:updateHover(mx, my)
  self.hovered = pointInRect(mx, my, self.x, self.y, self.w, self.h)
end

function Button:mousepressed(mx, my, button)
  if button == 1 and self.hovered and self.action then
    self.action()
    return true
  end
  return false
end

function Button:draw(font, glitchx, glitchy)
  local gx, gy = glitchx or 0, glitchy or 0
  local x, y = self.x + gx, self.y + gy

  setColor255(245, 235, 220, 255)
  love.graphics.rectangle("fill", x, y, self.w, self.h, 8, 8)

  local c = self.hovered and self.hoverColor or self.color
  setColor255(c[1], c[2], c[3], 255)
  love.graphics.rectangle("fill", x + 3, y + 3, self.w - 6, self.h - 6, 6, 6)

  setColor255(20, 20, 20, 255)
  love.graphics.rectangle("line", x, y, self.w, self.h, 8, 8)

  love.graphics.setFont(font)
  setColor255(20, 20, 20, 255)
  local ty = y + self.h / 2 - font:getHeight() / 2
  love.graphics.printf(self.text, x, ty, self.w, "center")
end

-- -----------------------------
-- Pawn/Flag assets (THIS IS THE FIX)
-- -----------------------------
local pawnBaseImg = nil
local flagBaseImg = nil
local PAWN_CANVAS_SIZE = 40

local function tryLoadImage(path)
  if love.filesystem.getInfo(path) then
    local img = love.graphics.newImage(path)
    img:setFilter("linear", "linear")
    return img
  end
  return nil
end

-- Tint an image onto a Canvas. This works in ALL LÖVE versions (no ImageData readback).
-- It assumes pawn/flag art is mostly white/gray with alpha (so multiply tint looks correct).
local function makeTintedCanvas(baseImg, colorRGB, brightnessMul)
  local size = PAWN_CANVAS_SIZE
  local canvas = love.graphics.newCanvas(size, size)
  local prevCanvas = love.graphics.getCanvas()

  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)

  local mul = brightnessMul or 1.0
  local r = (colorRGB[1] / 255) * mul
  local g = (colorRGB[2] / 255) * mul
  local b = (colorRGB[3] / 255) * mul

  love.graphics.setColor(r, g, b, 1)

  local iw, ih = baseImg:getWidth(), baseImg:getHeight()
  local scale = math.min(size / iw, size / ih)
  local dx = (size - iw * scale) * 0.5
  local dy = (size - ih * scale) * 0.5

  love.graphics.draw(baseImg, dx, dy, 0, scale, scale)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setCanvas(prevCanvas)

  return canvas
end

-- Fallback (only if images missing)
local function makeFallbackPawnCanvas(color, isFlag)
  local canvas = love.graphics.newCanvas(PAWN_CANVAS_SIZE, PAWN_CANVAS_SIZE)
  local prevCanvas = love.graphics.getCanvas()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)

  local r, g, b = rgb255(color[1], color[2], color[3], 255)

  if isFlag then
    love.graphics.setColor(0.4, 0.4, 0.4, 1)
    love.graphics.setLineWidth(3)
    love.graphics.line(10, 35, 10, 5)
    love.graphics.setColor(r * 0.6, g * 0.6, b * 0.6, 1)
    love.graphics.polygon("fill", 10, 6, 35, 12, 10, 20)
  else
    love.graphics.setColor(r, g, b, 1)
    love.graphics.circle("fill", 20, 20, 18)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", 20, 20, 18)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", 15, 15, 5)
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setCanvas(prevCanvas)
  return canvas
end

-- -----------------------------
-- States
-- -----------------------------
local state = { mode = "splash" } -- splash | menu | game

local cfg = {
  numPlayers = 2,
  timeLimit = 30,
  boardSize = 8,
}

local players = {}
local pawns = {}
local board = {}

local currentPlayerIndex = 1
local selectedPawn = nil

local fonts = {}
local bgShader = nil
local audioFFT = nil

local questionUI = nil
local feedbackUI = nil
local pendingAction = nil

-- -----------------------------
-- Board / gameplay helpers
-- -----------------------------
local function buildPlayersAndPawns(numPlayers, boardSize)
  players = {}
  pawns = {}

  local corners = {
    {1, 1},
    {boardSize, boardSize},
    {1, boardSize},
    {boardSize, 1},
  }
  local baseOffsets = {
    {0, 0}, {1, 0}, {0, 1}, {1, 1}, {2, 0}, {0, 2}
  }

  for i = 1, numPlayers do
    local p = {
      name = "Player " .. i,
      color = PLAYER_COLORS[i],
      score = 0,
      pawnCanvas = nil,
      flagCanvas = nil,
    }

    if pawnBaseImg and flagBaseImg then
      p.pawnCanvas = makeTintedCanvas(pawnBaseImg, p.color, 1.0)
      -- darker/“light” flag like your python (so flags don't scream)
      p.flagCanvas = makeTintedCanvas(flagBaseImg, p.color, 0.35)
    else
      p.pawnCanvas = makeFallbackPawnCanvas(p.color, false)
      p.flagCanvas = makeFallbackPawnCanvas(p.color, true)
    end

    table.insert(players, p)

    local cr, cc = corners[i][1], corners[i][2]
    for j = 1, #baseOffsets do
      local dr, dc = baseOffsets[j][1], baseOffsets[j][2]
      local isFlag = (j == 1)
      local r, c
      if i == 1 then
        r, c = cr + dr, cc + dc
      elseif i == 2 then
        r, c = cr - dr, cc - dc
      elseif i == 3 then
        r, c = cr + dr, cc - dc
      else
        r, c = cr - dr, cc + dc
      end
      if r >= 1 and r <= boardSize and c >= 1 and c <= boardSize then
        table.insert(pawns, {
          player = p,
          row = r,
          col = c,
          isFlag = isFlag,
        })
      end
    end
  end
end

local function initBoard(boardSize)
  board = {}
  local cats = {}
  for k, _ in pairs(CATEGORY_COLORS) do table.insert(cats, k) end
  table.sort(cats)

  for r = 1, boardSize do
    board[r] = {}
    for c = 1, boardSize do
      local cat = cats[((r + c - 2) % #cats) + 1]
      board[r][c] = {
        isHole = false,
        pawn = nil,
        category = cat,
      }
    end
  end

  for _, p in ipairs(pawns) do
    board[p.row][p.col].pawn = p
  end

  local free = {}
  for r = 1, boardSize do
    for c = 1, boardSize do
      if board[r][c].pawn == nil then
        table.insert(free, {r, c})
      end
    end
  end
  local count = math.min(HOLE_COUNT, #free)
  for i = 1, count do
    local idx = love.math.random(#free)
    local pos = table.remove(free, idx)
    board[pos[1]][pos[2]].isHole = true
  end
end

local function getValidMoves(pawn, boardSize)
  if not pawn then return {} end
  local moves = {}
  local r, c = pawn.row, pawn.col
  local dirs = {{0,1},{0,-1},{1,0},{-1,0}}
  for _, d in ipairs(dirs) do
    local nr, nc = r + d[1], c + d[2]
    if nr >= 1 and nr <= boardSize and nc >= 1 and nc <= boardSize then
      local cell = board[nr][nc]
      if not cell.isHole then
        if not (cell.pawn and cell.pawn.player == pawn.player) then
          table.insert(moves, {nr, nc})
        end
      end
    end
  end
  return moves
end

local function startFeedback(ok, onDone)
  feedbackUI = {
    ok = ok,
    t = 0,
    duration = 0.9,
    onDone = onDone,
  }
end

local function beginQuestion(category, timeLimit, requiredCorrect, onFinish)
  local qdata = getRandomQuestionFrom(category)
  if not qdata then
    onFinish(true)
    return
  end

  local q = qdata.question
  local correct = qdata.correct
  local answers = {correct, qdata.wrong[1], qdata.wrong[2], qdata.wrong[3]}
  shuffle(answers)

  questionUI = {
    question = q,
    correct = correct,
    answers = answers,
    category = category,
    timeLimit = timeLimit,
    t = 0,
    required = requiredCorrect or 1,
    correctSoFar = 0,
    onFinish = onFinish,
  }
end

local function applyPendingAction(success)
  if not pendingAction then return end
  local act = pendingAction
  pendingAction = nil

  local current = players[currentPlayerIndex]

  if not success then
    startFeedback(false, function()
      selectedPawn = nil
      currentPlayerIndex = (currentPlayerIndex % #players) + 1
    end)
    return
  end

  local fromPawn = act.pawn
  local tr, tc = act.toR, act.toC
  local targetCell = board[tr][tc]

  if act.type == "attack" and targetCell.pawn and targetCell.pawn.player ~= fromPawn.player then
    local victim = targetCell.pawn
    board[victim.row][victim.col].pawn = nil
    for i = #pawns, 1, -1 do
      if pawns[i] == victim then table.remove(pawns, i) break end
    end
    current.score = current.score + 5
  else
    current.score = current.score + 1
  end

  board[fromPawn.row][fromPawn.col].pawn = nil
  fromPawn.row, fromPawn.col = tr, tc
  targetCell.pawn = fromPawn

  startFeedback(true, function()
    selectedPawn = nil
    currentPlayerIndex = (currentPlayerIndex % #players) + 1
  end)
end

local function askForAction(actType, pawn, toR, toC, category)
  pendingAction = {
    type = actType,
    pawn = pawn,
    toR = toR,
    toC = toC,
    category = category,
  }

  local needed = (actType == "attack") and 2 or 1
  beginQuestion(category, cfg.timeLimit, needed, function(ok)
    applyPendingAction(ok)
  end)
end

-- -----------------------------
-- Drawing helpers
-- -----------------------------
local function drawDim(alpha255)
  local w, h = love.graphics.getDimensions()
  setColor255(0, 0, 0, alpha255)
  love.graphics.rectangle("fill", 0, 0, w, h)
end

local function drawTimerBar(x, y, w, h, pct)
  pct = clamp(pct, 0, 1)
  local fill = math.floor(w * pct)

  setColor255(180, 180, 180, 220)
  love.graphics.rectangle("fill", x, y, w, h, 6, 6)

  local r, g, b
  if pct > 0.5 then
    r, g, b = 50, 205, 50
  elseif pct > 0.2 then
    r, g, b = 255, 215, 0
  else
    r, g, b = 220, 20, 60
  end

  setColor255(r, g, b, 255)
  love.graphics.rectangle("fill", x, y, fill, h, 6, 6)

  setColor255(10, 10, 10, 255)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, w, h, 6, 6)
end

local function drawLegend(x, y)
  love.graphics.setFont(fonts.small)
  setColor255(255, 255, 255, 255)
  love.graphics.print("Legend", x + 70, y)
  local yy = y + 35

  local keys = {}
  for k, _ in pairs(CATEGORY_COLORS) do table.insert(keys, k) end
  table.sort(keys)

  for _, cat in ipairs(keys) do
    local col = CATEGORY_COLORS[cat]
    setColor255(col[1], col[2], col[3], 255)
    love.graphics.rectangle("fill", x, yy, 20, 20)
    setColor255(255, 255, 255, 255)
    love.graphics.rectangle("line", x, yy, 20, 20)
    love.graphics.print(cat, x + 30, yy)
    yy = yy + 25
  end

  yy = yy + 20
  local labels = {
    {"Selected", {255, 255, 0}},
    {"Move Empty", {150, 255, 150}},
    {"Attack", {255, 150, 150}},
    {"Hole", {255, 255, 255}},
  }
  for _, it in ipairs(labels) do
    local lab, col = it[1], it[2]
    setColor255(col[1], col[2], col[3], 255)
    love.graphics.rectangle("fill", x, yy, 20, 20)
    setColor255(255, 255, 255, 255)
    love.graphics.rectangle("line", x, yy, 20, 20)
    love.graphics.print(lab, x + 30, yy)
    yy = yy + 25
  end
end

local function drawCurrentPlayerPanel(x, y)
  local p = players[currentPlayerIndex]
  if not p then return end

  setColor255(255, 255, 255, 255)
  love.graphics.setFont(fonts.small)
  love.graphics.print("Current Turn", x + 60, y)

  setColor255(255, 255, 255, 255)
  love.graphics.draw(p.pawnCanvas, x + 60, y + 45, 0, 2.2, 2.2)

  love.graphics.setFont(fonts.name)
  setColor255(p.color[1], p.color[2], p.color[3], 255)
  love.graphics.printf(p.name, x, y + 130, 200, "center")

  love.graphics.setFont(fonts.small)
  setColor255(255, 255, 255, 255)
  love.graphics.printf("Score: " .. p.score, x, y + 165, 200, "center")
end

-- -----------------------------
-- Main draw of background + UI overlay
-- -----------------------------
local function drawBackground()
  local w, h = love.graphics.getDimensions()

  love.graphics.setShader(bgShader)
  bgShader:send("iTime", love.timer.getTime())
  bgShader:send("iResolution", {w, h, 1.0})
  bgShader:send("iChannel0", audioFFT.image)

  setColor255(255, 255, 255, 255)
  love.graphics.rectangle("fill", 0, 0, w, h)

  love.graphics.setShader()
end

-- -----------------------------
-- Splash / Menu / Game rendering
-- -----------------------------
local menuButtons = nil

local function drawSplash()
  local w, h = love.graphics.getDimensions()
  drawDim(110)

  love.graphics.setFont(fonts.title)
  setColor255(255, 255, 255, 255)
  love.graphics.printf("TRIVIA STRATEGY", 0, h * 0.5 - 90, w, "center")

  love.graphics.setFont(fonts.medium)
  setColor255(200, 200, 200, 255)
  love.graphics.printf("Capture the Flag", 0, h * 0.5 - 10, w, "center")

  love.graphics.setFont(fonts.small)
  setColor255(255, 215, 0, 255)
  love.graphics.printf("Click anywhere to start", 0, h * 0.5 + 50, w, "center")
end

local function buildMenuButtons()
  local function clampPlayers(delta)
    cfg.numPlayers = clamp(cfg.numPlayers + delta, 2, 4)
  end
  local function clampTime(delta)
    cfg.timeLimit = clamp(cfg.timeLimit + delta, 5, 120)
  end
  local function clampBoard(delta)
    cfg.boardSize = clamp(cfg.boardSize + delta, 6, 32)
  end
  local function startGame()
    buildPlayersAndPawns(cfg.numPlayers, cfg.boardSize)
    initBoard(cfg.boardSize)
    currentPlayerIndex = 1
    selectedPawn = nil
    questionUI = nil
    feedbackUI = nil
    pendingAction = nil
    state.mode = "game"
  end

  menuButtons = {
    Button.new(-100, -120, 50, 50, "-", {20,20,20}, {200,50,50}, function() clampPlayers(-1) end),
    Button.new( 100, -120, 50, 50, "+", {20,20,20}, {200,50,50}, function() clampPlayers( 1) end),
    Button.new(-100,  -40, 50, 50, "-", {20,20,20}, {200,50,50}, function() clampTime(-5) end),
    Button.new( 100,  -40, 50, 50, "+", {20,20,20}, {200,50,50}, function() clampTime( 5) end),
    Button.new(-100,   40, 50, 50, "-", {20,20,20}, {200,50,50}, function() clampBoard(-1) end),
    Button.new( 100,   40, 50, 50, "+", {20,20,20}, {200,50,50}, function() clampBoard( 1) end),
    Button.new(  -80,  130, 160, 60, "PLAY", {50,50,200}, {100,149,237}, startGame),
  }
end

local function drawMenu()
  local w, h = love.graphics.getDimensions()
  drawDim(105)

  local cx, cy = w / 2, h / 2
  local mx, my = love.mouse.getPosition()

  for _, b in ipairs(menuButtons) do
    b:updatePos(cx, cy)
    b:updateHover(mx, my)
  end

  local ticks = math.floor(love.timer.getTime() * 60)
  local glitchx, glitchy = 0, 0
  if ticks % 60 == 0 and love.math.random() < 0.3 then
    glitchx = love.math.random(-4, 4)
    glitchy = love.math.random(-2, 2)
  end

  love.graphics.setFont(fonts.title)
  setColor255(255, 255, 255, 255)
  love.graphics.printf("MAIN MENU", 0, cy - 260 + glitchy, w, "center")

  love.graphics.setFont(fonts.medium)
  setColor255(255, 255, 255, 255)
  love.graphics.printf("Number of Players:", 0, cy - 190, w, "center")
  love.graphics.setFont(fonts.title)
  love.graphics.printf(tostring(cfg.numPlayers), 0, cy - 155, w, "center")

  love.graphics.setFont(fonts.medium)
  love.graphics.printf("Time (sec):", 0, cy - 110, w, "center")
  love.graphics.setFont(fonts.title)
  love.graphics.printf(tostring(cfg.timeLimit), 0, cy - 75, w, "center")

  love.graphics.setFont(fonts.medium)
  love.graphics.printf(("Board Size (%dx%d):"):format(cfg.boardSize, cfg.boardSize), 0, cy - 25, w, "center")
  love.graphics.setFont(fonts.title)
  love.graphics.printf(tostring(cfg.boardSize), 0, cy + 10, w, "center")

  for _, b in ipairs(menuButtons) do
    b:draw(fonts.medium, glitchx, glitchy)
  end
end

local function drawHUD()
  local w, h = love.graphics.getDimensions()

  setColor255(0, 0, 0, 180)
  love.graphics.rectangle("fill", 10, 10, 220, 150, 10, 10)
  love.graphics.setFont(fonts.small)

  local yy = 18
  for _, p in ipairs(players) do
    setColor255(p.color[1], p.color[2], p.color[3], 255)
    love.graphics.print(("%s (Score: %d)"):format(p.name, p.score), 20, yy)
    yy = yy + 28
  end

  drawLegend(10, 200)
  drawCurrentPlayerPanel(w - 210, 50)
end

local function drawBoard()
  local w, h = love.graphics.getDimensions()
  drawDim(70)

  local boardSize = cfg.boardSize

  local margin_x = 480
  local margin_y = 230
  local avail_w = math.max(50, w - margin_x)
  local avail_h = math.max(50, h - margin_y)
  local cellSize = math.floor(math.min(avail_w / boardSize, avail_h / boardSize))

  local startX = math.floor((w - (boardSize * cellSize)) / 2)
  local startY = math.floor((h - (boardSize * cellSize)) / 2)
  local pawnSize = math.floor(cellSize * 0.7)

  local moves = selectedPawn and getValidMoves(selectedPawn, boardSize) or {}
  local moveSet = {}
  for _, m in ipairs(moves) do
    moveSet[m[1] .. "," .. m[2]] = true
  end

  for r = 1, boardSize do
    for c = 1, boardSize do
      local cell = board[r][c]
      local x = startX + (c - 1) * cellSize
      local y = startY + (r - 1) * cellSize

      local cellR, cellG, cellB = 180, 180, 180
      if cell.isHole then
        cellR, cellG, cellB = 0, 0, 0
      end

      if selectedPawn and r == selectedPawn.row and c == selectedPawn.col then
        cellR, cellG, cellB = 255, 255, 0
      elseif moveSet[r .. "," .. c] then
        if cell.pawn and cell.pawn.player ~= selectedPawn.player then
          cellR, cellG, cellB = 255, 150, 150
        else
          cellR, cellG, cellB = 150, 255, 150
        end
      end

      setColor255(cellR, cellG, cellB, 240)
      love.graphics.rectangle("fill", x, y, cellSize, cellSize, 6, 6)
      setColor255(10, 10, 10, 255)
      love.graphics.rectangle("line", x, y, cellSize, cellSize, 6, 6)

      if not cell.isHole then
        local col = CATEGORY_COLORS[cell.category] or {128, 128, 128}
        setColor255(col[1], col[2], col[3], 255)
        local s = math.floor(cellSize * 0.16)
        love.graphics.rectangle("fill", x + 4, y + 4, s, s, 4, 4)
      end

      if cell.pawn then
        local p = cell.pawn
        local canvas = p.isFlag and p.player.flagCanvas or p.player.pawnCanvas

        local scale = pawnSize / PAWN_CANVAS_SIZE
        if selectedPawn and p == selectedPawn then
          scale = scale * (1.0 + 0.1 * math.sin(love.timer.getTime() * 10))
        end

        setColor255(255, 255, 255, 255)
        love.graphics.draw(canvas,
          x + cellSize / 2, y + cellSize / 2,
          0,
          scale, scale,
          PAWN_CANVAS_SIZE / 2, PAWN_CANVAS_SIZE / 2
        )
      end
    end
  end

  drawHUD()
  return startX, startY, cellSize
end

local function drawQuestionModal()
  local w, h = love.graphics.getDimensions()
  drawDim(150)

  local ui = questionUI
  if not ui then return end

  local boxW = math.min(640, w - 60)
  local boxH = 340
  local boxX = (w - boxW) / 2
  local boxY = 90

  local barW = math.min(520, w - 80)
  local barH = 25
  local barX = (w - barW) / 2
  local barY = 40

  local timeLeft = math.max(0, ui.timeLimit - ui.t)
  local pct = timeLeft / ui.timeLimit
  drawTimerBar(barX, barY, barW, barH, pct)

  setColor255(245, 245, 245, 240)
  love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 12, 12)
  setColor255(10, 10, 10, 255)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 12, 12)

  love.graphics.setFont(fonts.small)
  setColor255(10, 10, 10, 255)

  local margin = 20
  local maxWidth = boxW - margin * 2
  local _, lines = fonts.small:getWrap(ui.question, maxWidth)
  local y = boxY + margin
  for i = 1, #lines do
    love.graphics.print(lines[i], boxX + margin, y)
    y = y + 26
  end

  ui.answerRects = {}

  local startY = y + 18
  local mx, my = love.mouse.getPosition()

  for i = 1, #ui.answers do
    local ans = ui.answers[i]
    local label = string.char(64 + i) .. ": " .. ans

    local ay = startY + (i - 1) * 40
    local rectX = boxX + margin
    local rectY = ay - 4
    local rectW = boxW - margin * 2
    local rectH = 32

    local hover = pointInRect(mx, my, rectX, rectY, rectW, rectH)
    if hover then
      setColor255(230, 230, 230, 255)
      love.graphics.rectangle("fill", rectX, rectY, rectW, rectH, 6, 6)
    end

    setColor255(10, 10, 10, 255)
    love.graphics.print(label, rectX + 6, ay)

    table.insert(ui.answerRects, {x=rectX, y=rectY, w=rectW, h=rectH, ans=ans})
  end
end

local function drawFeedbackOverlay()
  local w, h = love.graphics.getDimensions()
  drawDim(120)

  local rectW, rectH = 420, 320
  local x = (w - rectW) / 2
  local y = (h - rectH) / 2

  setColor255(245, 245, 245, 240)
  love.graphics.rectangle("fill", x, y, rectW, rectH, 12, 12)
  setColor255(10, 10, 10, 255)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", x, y, rectW, rectH, 12, 12)

  love.graphics.setFont(fonts.big)
  if feedbackUI.ok then
    setColor255(0, 200, 0, 255)
    love.graphics.printf("✓", 0, y + 40, w, "center")
  else
    setColor255(200, 0, 0, 255)
    love.graphics.printf("X", 0, y + 55, w, "center")
  end
end

-- -----------------------------
-- LÖVE callbacks
-- -----------------------------
function love.load()
  love.window.setMode(DEFAULT_W, DEFAULT_H, {resizable=true, vsync=0})
  love.graphics.setBackgroundColor(0, 0, 0, 1)
  love.math.setRandomSeed(os.time())

  fonts.title = love.graphics.newFont(48)
  fonts.medium = love.graphics.newFont(24)
  fonts.small = love.graphics.newFont(20)
  fonts.big = love.graphics.newFont(200)
  fonts.name = love.graphics.newFont(30)

  loadQuestionsCSV("questions.csv")

  -- Load pawn/flag images (THIS IS WHAT YOU WANTED)
  pawnBaseImg = tryLoadImage("pawn.png")
  flagBaseImg = tryLoadImage("flag.png")
  if not pawnBaseImg then print("Warning: pawn.png missing -> using fallback") end
  if not flagBaseImg then print("Warning: flag.png missing -> using fallback") end

  audioFFT = AudioFFT.new("shadertoy.mp3")
  bgShader = love.graphics.newShader(GALAXY_SHADER)

  buildMenuButtons()
end

function love.update(dt)
  audioFFT:update(dt)

  if feedbackUI then
    feedbackUI.t = feedbackUI.t + dt
    if feedbackUI.t >= feedbackUI.duration then
      local done = feedbackUI.onDone
      feedbackUI = nil
      if done then done() end
    end
    return
  end

  if questionUI then
    questionUI.t = questionUI.t + dt
    if questionUI.t >= questionUI.timeLimit then
      local finish = questionUI.onFinish
      questionUI = nil
      if finish then finish(false) end
    end
    return
  end
end

function love.draw()
  drawBackground()

  if state.mode == "splash" then
    drawSplash()
  elseif state.mode == "menu" then
    drawMenu()
  elseif state.mode == "game" then
    drawBoard()
  end

  if questionUI then
    drawQuestionModal()
  end

  if feedbackUI then
    drawFeedbackOverlay()
  end
end

function love.mousepressed(x, y, button)
  if feedbackUI then return end

  if state.mode == "splash" then
    if button == 1 then state.mode = "menu" end
    return
  end

  if state.mode == "menu" then
    if button == 1 then
      for _, b in ipairs(menuButtons) do
        if b:mousepressed(x, y, button) then break end
      end
    end
    return
  end

  if questionUI then
    if button == 1 and questionUI.answerRects then
      for _, r in ipairs(questionUI.answerRects) do
        if pointInRect(x, y, r.x, r.y, r.w, r.h) then
          local correct = (r.ans == questionUI.correct)

          if correct then
            questionUI.correctSoFar = questionUI.correctSoFar + 1
          end

          if not correct then
            local finish = questionUI.onFinish
            questionUI = nil
            if finish then finish(false) end
            return
          end

          if questionUI.correctSoFar >= questionUI.required then
            local finish = questionUI.onFinish
            questionUI = nil
            if finish then finish(true) end
            return
          else
            local cat = questionUI.category
            local tl = questionUI.timeLimit
            local required = questionUI.required
            local soFar = questionUI.correctSoFar
            local finish = questionUI.onFinish

            questionUI = nil
            beginQuestion(cat, tl, required, finish)
            if questionUI then
              questionUI.correctSoFar = soFar
            end
            return
          end
        end
      end
    end
    return
  end

  if state.mode == "game" then
    if button ~= 1 then return end

    local boardSize = cfg.boardSize

    local w, h = love.graphics.getDimensions()
    local margin_x = 480
    local margin_y = 230
    local avail_w = math.max(50, w - margin_x)
    local avail_h = math.max(50, h - margin_y)
    local cellSize = math.floor(math.min(avail_w / boardSize, avail_h / boardSize))
    local startX = math.floor((w - (boardSize * cellSize)) / 2)
    local startY = math.floor((h - (boardSize * cellSize)) / 2)

    local current = players[currentPlayerIndex]

    local function cellAt(mx, my)
      if mx < startX or my < startY then return nil end
      local cx = math.floor((mx - startX) / cellSize) + 1
      local cy = math.floor((my - startY) / cellSize) + 1
      if cx < 1 or cx > boardSize or cy < 1 or cy > boardSize then return nil end
      return cy, cx
    end

    local r, c = cellAt(x, y)
    if not r then return end

    local cell = board[r][c]

    if not selectedPawn then
      if cell.pawn and cell.pawn.player == current then
        selectedPawn = cell.pawn
      end
      return
    end

    local dist = math.abs(selectedPawn.row - r) + math.abs(selectedPawn.col - c)
    if dist ~= 1 then
      selectedPawn = nil
      return
    end

    if cell.isHole then
      selectedPawn = nil
      return
    end

    if not cell.pawn then
      askForAction("move", selectedPawn, r, c, cell.category)
      return
    else
      if cell.pawn.player ~= current then
        askForAction("attack", selectedPawn, r, c, cell.category)
      else
        selectedPawn = nil
      end
      return
    end
  end
end

function love.keypressed(key)
  if key == "escape" then
    if questionUI then
      local finish = questionUI.onFinish
      questionUI = nil
      if finish then finish(false) end
      return
    end
    if state.mode == "game" then
      state.mode = "menu"
      return
    end
  end
end
