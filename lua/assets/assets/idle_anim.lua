local spriteSheet
local quads = {}
local frameTime = 0.15
local timer = 0
local currentFrame = 1
local direction = "down"

local directions = {
  down = 1,
  up = 2,
  left = 3,
  right = 4,
}

function love.load()
  spriteSheet = love.graphics.newImage("idlewalk.png")
  local frameW, frameH = 64, 64
  local sheetW, sheetH = spriteSheet:getDimensions()

  for row = 1, 4 do
    quads[row] = {}
    for col = 1, 4 do
      quads[row][col] = love.graphics.newQuad(
        (col - 1) * frameW,
        (row - 1) * frameH,
        frameW,
        frameH,
        sheetW,
        sheetH
      )
    end
  end
end

function love.update(dt)
  if love.keyboard.isDown("down") then
    direction = "down"
  elseif love.keyboard.isDown("up") then
    direction = "up"
  elseif love.keyboard.isDown("left") then
    direction = "left"
  elseif love.keyboard.isDown("right") then
    direction = "right"
  end

  timer = timer + dt
  if timer >= frameTime then
    timer = timer - frameTime
    currentFrame = (currentFrame % 4) + 1
  end
end

function love.draw()
  local row = directions[direction]
  local x, y = 200, 200
  love.graphics.draw(spriteSheet, quads[row][currentFrame], x, y)
end
