local spriteSheet
local attackSheet
local walkSheet
local sheathSheet
local quads = {}
local attackQuads = {}
local walkQuads = {}
local sheathQuads = {}
local frameTime = 0.12
local timer = 0
local frame = 1
local frameSize = 64
local spriteScale = 2
local sheathFrameTime = 0.1
local deathFadeDuration = 1

-- 1=down, 2=up, 3=left, 4=right
local dir = 1
local isMoving = false
local isGuard = false
local isAttack = false
local wasAttack = false
local attackChoice = 1
local isArmedWalk = false
local weaponState = "armed"
local sheathFrame = 1
local sheathTimer = 0
local deathState = "none"
local deathTimer = 0
local deathAlpha = 1

function love.load()
  love.math.setRandomSeed(os.time())

  spriteSheet = love.graphics.newImage("idlewalk.png")
  spriteSheet:setFilter("nearest", "nearest")

  attackSheet = love.graphics.newImage("attack.png")
  attackSheet:setFilter("nearest", "nearest")

  walkSheet = love.graphics.newImage("walk.png")
  walkSheet:setFilter("nearest", "nearest")

  sheathSheet = love.graphics.newImage("middleDeath.png")
  sheathSheet:setFilter("nearest", "nearest")

  for row = 1, 8 do
    quads[row] = {}
    for col = 1, 8 do
      local x = (col - 1) * frameSize
      local y = (row - 1) * frameSize
      quads[row][col] = love.graphics.newQuad(
        x,
        y,
        frameSize,
        frameSize,
        spriteSheet:getDimensions()
      )
    end
  end

  for row = 1, 8 do
    attackQuads[row] = {}
    for col = 1, 8 do
      local x = (col - 1) * frameSize
      local y = (row - 1) * frameSize
      attackQuads[row][col] = love.graphics.newQuad(
        x,
        y,
        frameSize,
        frameSize,
        attackSheet:getDimensions()
      )
    end
  end

  for row = 1, 8 do
    walkQuads[row] = {}
    for col = 1, 6 do
      local x = (col - 1) * frameSize
      local y = (row - 1) * frameSize
      walkQuads[row][col] = love.graphics.newQuad(
        x,
        y,
        frameSize,
        frameSize,
        walkSheet:getDimensions()
      )
    end
  end

  for row = 1, 4 do
    sheathQuads[row] = {}
    for col = 1, 8 do
      local x = (col - 1) * frameSize
      local y = (row - 1) * frameSize
      sheathQuads[row][col] = love.graphics.newQuad(
        x,
        y,
        frameSize,
        frameSize,
        sheathSheet:getDimensions()
      )
    end
  end
end

function love.update(dt)
  if love.keyboard.isDown("down") then
    dir = 1
    isMoving = true
  elseif love.keyboard.isDown("up") then
    dir = 2
    isMoving = true
  elseif love.keyboard.isDown("left") then
    dir = 4
    isMoving = true
  elseif love.keyboard.isDown("right") then
    dir = 3
    isMoving = true
  else
    isMoving = false
  end

  isGuard = love.keyboard.isDown("g")
  isAttack = love.keyboard.isDown("a")
  isArmedWalk = love.keyboard.isDown("n")
  if isAttack and not wasAttack then
    attackChoice = love.math.random(1, 3)
  end
  wasAttack = isAttack

  if isArmedWalk then
    weaponState = "armed"
  elseif isMoving then
    if weaponState == "armed" or weaponState == "drawing" then
      weaponState = "sheathing"
      sheathFrame = 3
      sheathTimer = 0
    end
  else
    if weaponState == "sheathed" or weaponState == "sheathing" then
      weaponState = "drawing"
      sheathFrame = 1
      sheathTimer = 0
    end
  end

  if isMoving then
    deathState = "none"
    deathTimer = 0
    deathAlpha = 1
  end

  if deathState ~= "none" then
    deathTimer = deathTimer + dt
    if deathState == "hurt" and deathTimer >= 0.2 then
      deathState = "death"
      deathTimer = 0
    elseif deathState == "death" and deathTimer >= 0.2 then
      deathState = "fade"
      deathTimer = 0
      deathAlpha = 1
    elseif deathState == "fade" then
      local t = math.min(deathTimer / deathFadeDuration, 1)
      deathAlpha = 1 - t
      if t >= 1 then
        deathState = "done"
      end
    end
  end

  if weaponState == "sheathing" or weaponState == "drawing" then
    sheathTimer = sheathTimer + dt
    if sheathTimer >= sheathFrameTime then
      sheathTimer = sheathTimer - sheathFrameTime
      if weaponState == "sheathing" then
        sheathFrame = sheathFrame - 1
        if sheathFrame <= 1 then
          sheathFrame = 1
          weaponState = "sheathed"
        end
      else
        sheathFrame = sheathFrame + 1
        if sheathFrame >= 3 then
          sheathFrame = 3
          weaponState = "armed"
        end
      end
    end
  end


  local maxFrame = 4
  if isMoving and not isArmedWalk and not isAttack and not isGuard and deathState == "none" then
    maxFrame = 6
  end

  timer = timer + dt
  if timer >= frameTime then
    timer = timer - frameTime
    frame = frame + 1
    if frame > maxFrame then
      frame = 1
    end
  end
end

function love.draw()
  local w, h = love.graphics.getDimensions()
  local halfSize = (frameSize * spriteScale) / 2
  local x = math.floor(w / 2 - halfSize)
  local y = math.floor(h / 2 - halfSize)
  local row = dir
  local col = frame

  if deathState ~= "none" then
    row = dir
    if deathState == "hurt" then
      col = 6
    else
      col = 8
      if deathState == "death" then
        col = 7
      end
    end
  elseif isAttack then
    if attackChoice == 3 then
      row = dir + 4
    else
      row = dir
    end
  elseif isGuard then
    row = dir + 4
    col = 1
  elseif weaponState == "sheathing" or weaponState == "drawing" then
    row = dir
    col = sheathFrame
  elseif isMoving then
    if isArmedWalk then
      col = frame + 4
    else
      row = dir + 4
    end
  end

  if deathState ~= "none" then
    love.graphics.setColor(1, 1, 1, deathAlpha)
    love.graphics.draw(sheathSheet, sheathQuads[row][col], x, y, 0, spriteScale, spriteScale)
    love.graphics.setColor(1, 1, 1, 1)
  elseif isAttack then
    local attackCol = col
    if attackChoice == 2 then
      attackCol = col + 4
    end
    love.graphics.draw(attackSheet, attackQuads[row][attackCol], x, y, 0, spriteScale, spriteScale)
  elseif weaponState == "sheathing" or weaponState == "drawing" then
    love.graphics.draw(sheathSheet, sheathQuads[row][col], x, y, 0, spriteScale, spriteScale)
  elseif isMoving and not isArmedWalk then
    love.graphics.draw(walkSheet, walkQuads[row][col], x, y, 0, spriteScale, spriteScale)
  else
    love.graphics.draw(spriteSheet, quads[row][col], x, y, 0, spriteScale, spriteScale)
  end
end

function love.keypressed(key)
  if key == "d" then
    deathState = "hurt"
    deathTimer = 0
    deathAlpha = 1
  end
end
