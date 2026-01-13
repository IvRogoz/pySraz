-- src/assets.lua
local Config = require("src.config")
local U      = require("src.util")

local Assets = {}

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

return Assets
