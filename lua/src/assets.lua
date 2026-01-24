-- src/assets.lua
local Config = require("src.config")
local U      = require("src.util")

local Assets = {}

local function endsWith(value, suffix)
  return value:sub(-#suffix):lower() == suffix:lower()
end

local function extractNumber(value)
  local n = value:match("(%d+)")
  return n and tonumber(n) or nil
end

local function naturalSort(a, b)
  local na = extractNumber(a)
  local nb = extractNumber(b)
  if na and nb and na ~= nb then return na < nb end
  return a:lower() < b:lower()
end

local function clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function loadCropConfig(path)
  if not path or not love.filesystem.getInfo(path) then
    return nil
  end

  local chunk = love.filesystem.load(path)
  if not chunk then
    return nil
  end

  local ok, loaded = pcall(chunk)
  if ok then
    return loaded
  end

  return nil
end

function Assets.tryLoadImage(path)

  if love.filesystem.getInfo(path) then
    local img = love.graphics.newImage(path)
    img:setFilter("linear", "linear")
    return img
  end
  return nil
end

-- Tint an image onto a Canvas. Works without ImageData readback.
function Assets.makeTintedCanvas(baseImg, colorRGB, brightnessMul)
  local size = Config.PAWN_CANVAS_SIZE
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

function Assets.makeFallbackPawnCanvas(color, isFlag)
  local canvas = love.graphics.newCanvas(Config.PAWN_CANVAS_SIZE, Config.PAWN_CANVAS_SIZE)
  local prevCanvas = love.graphics.getCanvas()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)

  local r, g, b = U.rgb255(color[1], color[2], color[3], 255)

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

function Assets.loadSpriteSheet(path, frame_w, frame_h, columns, rows)
  if not love.filesystem.getInfo(path) then
    return nil
  end

  local img = love.graphics.newImage(path)
  img:setFilter("nearest", "nearest") -- crisp pixel edges; change to "linear" if you want smoothing

  local iw, ih = img:getWidth(), img:getHeight()
  local cols = columns or math.floor(iw / frame_w)
  local rws  = rows or math.floor(ih / frame_h)

  local quads = {}
  local idx = 1
  for ry = 0, rws - 1 do
    for cx = 0, cols - 1 do
      quads[idx] = love.graphics.newQuad(
        cx * frame_w, ry * frame_h, frame_w, frame_h, iw, ih
      )
      idx = idx + 1
    end
  end

  return {
    image = img,
    frame_w = frame_w,
    frame_h = frame_h,
    columns = cols,
    rows = rws,
    quads = quads,
  }
end

function Assets.loadSpriteGrid(path, frameSize, rows, cols)
  if not love.filesystem.getInfo(path) then
    return nil
  end

  local img = love.graphics.newImage(path)
  img:setFilter("nearest", "nearest")

  local quads = {}
  for row = 1, rows do
    quads[row] = {}
    for col = 1, cols do
      local x = (col - 1) * frameSize
      local y = (row - 1) * frameSize
      quads[row][col] = love.graphics.newQuad(
        x, y, frameSize, frameSize, img:getDimensions()
      )
    end
  end

  return {
    image = img,
    frameSize = frameSize,
    rows = rows,
    cols = cols,
    quads = quads,
  }
end

function Assets.loadSpriteGridByCount(path, rows, cols)
  if not love.filesystem.getInfo(path) then
    return nil
  end

  local img = love.graphics.newImage(path)
  img:setFilter("nearest", "nearest")

  local iw, ih = img:getDimensions()
  local frame_w = iw / cols
  local frame_h = ih / rows
  local quads = {}
  for row = 1, rows do
    quads[row] = {}
    for col = 1, cols do
      local x = (col - 1) * frame_w
      local y = (row - 1) * frame_h
      quads[row][col] = love.graphics.newQuad(
        x, y, frame_w, frame_h, iw, ih
      )
    end
  end

  return {
    image = img,
    frame_w = frame_w,
    frame_h = frame_h,
    rows = rows,
    cols = cols,
    quads = quads,
  }
end

function Assets.loadPawnAnimations()
  local frameSize = 64
  local frameTime = 0.12

  return {
    frameSize = frameSize,
    fps = 1 / frameTime,
    idle = Assets.loadSpriteGrid("assets/idlewalk.png", frameSize, 8, 8),
    walk = Assets.loadSpriteGrid("assets/walk.png", frameSize, 8, 6),
    attack = Assets.loadSpriteGrid("assets/attack.png", frameSize, 8, 8),
    death = Assets.loadSpriteGrid("assets/middleDeath.png", frameSize, 4, 8),
  }
end

function Assets.loadDirectionalFrames(spriteDir, cropConfigPath, fps)
  if not love.filesystem.getInfo(spriteDir) then
    return nil
  end

  local items = love.filesystem.getDirectoryItems(spriteDir)
  local pngs = {}
  for _, name in ipairs(items) do
    if endsWith(name, ".png") then
      table.insert(pngs, name)
    end
  end

  table.sort(pngs, naturalSort)
  if #pngs == 0 then
    return nil
  end

  local crop = {
    up = { x = 0, y = 0, w = 32, h = 32 },
    down = { x = 0, y = 0, w = 32, h = 32 },
    left = { x = 0, y = 0, w = 32, h = 32 },
    right = { x = 0, y = 0, w = 32, h = 32 },
  }

  local anchors = {}
  local loaded = loadCropConfig(cropConfigPath)
  if loaded then
    local loadedCrop = loaded.crop or loaded
    local loadedAnchor = loaded.anchor or {}
    for dir, data in pairs(loadedCrop or {}) do
      if crop[dir] and type(data) == "table" then
        crop[dir] = {
          x = tonumber(data.x) or crop[dir].x,
          y = tonumber(data.y) or crop[dir].y,
          w = tonumber(data.w) or crop[dir].w,
          h = tonumber(data.h) or crop[dir].h,
        }
      end
    end

    for dir, data in pairs(loadedAnchor or {}) do
      if type(data) == "table" then
        anchors[dir] = {
          x = tonumber(data.x) or 0,
          y = tonumber(data.y) or 0,
        }
      end
    end
  end

  local frames = {}
  local dirs = { "down", "left", "right", "up" }
  for _, filename in ipairs(pngs) do
    local path = spriteDir .. "/" .. filename
    local img = love.graphics.newImage(path)
    img:setFilter("nearest", "nearest")

    local iw, ih = img:getDimensions()
    local quads = {}
    for _, dir in ipairs(dirs) do
      local rect = crop[dir]
      local x = clamp(rect.x, 0, iw - 1)
      local y = clamp(rect.y, 0, ih - 1)
      local w = clamp(rect.w, 1, iw - x)
      local h = clamp(rect.h, 1, ih - y)
      quads[dir] = love.graphics.newQuad(x, y, w, h, iw, ih)
    end

    table.insert(frames, {
      image = img,
      quads = quads,
    })
  end

  return {
    frames = frames,
    crop = crop,
    anchors = anchors,
    fps = fps or 10,
  }
end

return Assets
