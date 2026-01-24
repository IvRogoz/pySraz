-- src/draw.lua
local Config = require("src.config")
local U      = require("src.util")
local Game   = require("src.game")

local Draw = {}

local function drawDim(alpha255)
  local w, h = love.graphics.getDimensions()
  U.setColor255(0, 0, 0, alpha255)
  love.graphics.rectangle("fill", 0, 0, w, h)
end

local function drawTimerBar(x, y, w, h, pct)
  pct = U.clamp(pct, 0, 1)
  local fill = math.floor(w * pct)

  U.setColor255(180, 180, 180, 220)
  love.graphics.rectangle("fill", x, y, w, h, 6, 6)

  local r, g, b
  if pct > 0.5 then
    r, g, b = 50, 205, 50
  elseif pct > 0.2 then
    r, g, b = 255, 215, 0
  else
    r, g, b = 220, 20, 60
  end

  U.setColor255(r, g, b, 255)
  love.graphics.rectangle("fill", x, y, fill, h, 6, 6)

  U.setColor255(10, 10, 10, 255)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, w, h, 6, 6)
end

local function getPawnIdleDir(pawn, boardSize)
  if pawn.homeSide == "left" then
    return "right"
  elseif pawn.homeSide == "right" then
    return "left"
  end

  if pawn.col <= boardSize / 2 then
    return "right"
  end
  return "left"
end


local function getPawnIdleFrame(anim, t, offsetFrames)
  if not anim or not anim.idle then
    return 1
  end
  local frameCount = 4
  local fps = (anim.fps or 8) * 0.5
  local offset = offsetFrames or 0
  return ((math.floor(t * fps) + offset) % frameCount) + 1
end

local function getPawnMoveFrame(anim, t)
  if not anim or not anim.walk then
    return 1
  end
  local frameCount = 6
  local fps = (anim.fps or 8) * 0.5
  return (math.floor(t * fps) % frameCount) + 1
end

local function getPawnAttackFrame(anim, t, duration)
  if not anim or not anim.attack then
    return 1
  end
  local frameCount = 4
  local progress = 0
  if duration and duration > 0 then
    progress = U.clamp(t / duration, 0, 1)
  end
  return 1 + math.floor(progress * (frameCount - 1))
end

local function getPawnDeathFrame(anim, t, duration)
  if not anim or not anim.death then
    return 6
  end
  local frameCount = 3
  local progress = 0
  if duration and duration > 0 then
    progress = U.clamp(t / duration, 0, 1)
  end
  return 6 + math.floor(progress * (frameCount - 1))
end

local function getPawnSheathFrame(anim, t, duration, reverse)
  if not anim or not anim.death then
    return 1
  end
  local frameCount = 3
  local progress = 0
  if duration and duration > 0 then
    progress = U.clamp(t / duration, 0, 1)
  end
  local frame = 1 + math.floor(progress * (frameCount - 1))
  if reverse then
    frame = frameCount - frame + 1
  end
  return frame
end


local function getDirRow(dir)
  if dir == "down" then
    return 1
  elseif dir == "up" then
    return 2
  elseif dir == "right" then
    return 3
  end
  return 4
end

local pawnTintShader = nil

local function getPawnTintShader()
  if pawnTintShader then
    return pawnTintShader
  end

  pawnTintShader = love.graphics.newShader([[
    extern vec3 targetColor;
    extern vec3 replaceColor;
    extern float threshold;

    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec4 px = Texel(tex, tc);
      float dist = distance(px.rgb, targetColor);
      if (dist <= threshold) {
        px.rgb = replaceColor;
      }
      return px * color;
    }
  ]])

  return pawnTintShader
end

local function drawLegend(S, x, y)

  love.graphics.setFont(S.fonts.small)
  U.setColor255(255, 255, 255, 255)
  love.graphics.print("Legend", x + 70, y)
  local yy = y + 35

  local keys = {}
  for k, _ in pairs(Config.CATEGORY_COLORS) do table.insert(keys, k) end
  table.sort(keys)

  for _, cat in ipairs(keys) do
    local col = Config.CATEGORY_COLORS[cat]
    U.setColor255(col[1], col[2], col[3], 255)
    love.graphics.rectangle("fill", x, yy, 20, 20)
    U.setColor255(255, 255, 255, 255)
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
    U.setColor255(col[1], col[2], col[3], 255)
    love.graphics.rectangle("fill", x, yy, 20, 20)
    U.setColor255(255, 255, 255, 255)
    love.graphics.rectangle("line", x, yy, 20, 20)
    love.graphics.print(lab, x + 30, yy)
    yy = yy + 25
  end
end

local drawAnimatedPawn

local function drawCurrentPlayerPanel(S, x, y)

  local p = S.players[S.currentPlayerIndex]
  if not p then return end

  U.setColor255(255, 255, 255, 255)
  love.graphics.setFont(S.fonts.small)
  love.graphics.print("Current Turn", x + 60, y)

  local frameIndex = getPawnIdleFrame(S.pawnAnim, love.timer.getTime())
  local previewPawn = {
    player = {
      name = p.name,
      color = p.color,
      score = p.score,
      scaleBoost = 1.0,
    },
  }
  local row = getDirRow("left")
  drawAnimatedPawn(S, previewPawn, x + 110, y + 240, 300, S.pawnAnim and S.pawnAnim.idle, row, frameIndex, true)


  love.graphics.setFont(S.fonts.name)

  U.setColor255(p.color[1], p.color[2], p.color[3], 255)
  love.graphics.printf(p.name, x, y + 250, 200, "center")

  love.graphics.setFont(S.fonts.small)
  U.setColor255(255, 255, 255, 255)
  love.graphics.printf("Score: " .. p.score, x, y + 285, 200, "center")

end

local function drawHUD(S)
  local w, _ = love.graphics.getDimensions()

  U.setColor255(0, 0, 0, 180)
  love.graphics.rectangle("fill", 10, 10, 220, 150, 10, 10)
  love.graphics.setFont(S.fonts.small)

  local yy = 18
  for _, p in ipairs(S.players) do
    U.setColor255(p.color[1], p.color[2], p.color[3], 255)
    love.graphics.print(("%s (Score: %d)"):format(p.name, p.score), 20, yy)
    yy = yy + 28
  end

  drawLegend(S, 10, 200)
  drawCurrentPlayerPanel(S, w - 210, 50)
end

-- ✅ Background routing:
-- splash -> video
-- menu/game -> galaxy shader
function Draw.background(S)
  local w, h = love.graphics.getDimensions()

  if S.state and S.state.mode == "splash" then
    if S.splashVideo then
      local vw, vh = S.splashVideo:getDimensions()
      if vw and vh and vw > 0 and vh > 0 then
        local sx = w / vw
        local sy = h / vh
        local s = math.max(sx, sy) -- cover
        local dx = (w - vw * s) * 0.5
        local dy = (h - vh * s) * 0.5
        U.setColor255(255, 255, 255, 255)
        love.graphics.draw(S.splashVideo, dx, dy, 0, s, s)
      end
    else
      -- no video: just a dark fallback
      U.setColor255(0, 0, 0, 255)
      love.graphics.rectangle("fill", 0, 0, w, h)
    end
    return
  end

  -- galaxy shader for menu + game
  love.graphics.setShader(S.bgShader)
  S.bgShader:send("iTime", love.timer.getTime())
  S.bgShader:send("iResolution", {w, h, 1.0})
  S.bgShader:send("iChannel0", S.audioFFT.image)

  U.setColor255(255, 255, 255, 255)
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setShader()
end

local function drawSplash(S)
  local w, h = love.graphics.getDimensions()

  -- overlay for readability
  drawDim(110)

  love.graphics.setFont(S.fonts.title)
  U.setColor255(255, 255, 255, 255)
  love.graphics.printf("SRAZ 2025", 0, h * 0.5 - 90, w, "center")

  love.graphics.setFont(S.fonts.medium)
  U.setColor255(200, 200, 200, 255)
  love.graphics.printf("Capture the Flag", 0, h * 0.5 - 10, w, "center")

  love.graphics.setFont(S.fonts.small)
  U.setColor255(255, 215, 0, 255)
  love.graphics.printf("Click anywhere to start", 0, h * 0.5 + 50, w, "center")

  if (not S.splashVideo) and S.splashVideoError then
    U.setColor255(255, 120, 120, 255)
    love.graphics.printf(S.splashVideoError, 0, h - 30, w, "center")
  end
end

local function drawMenu(S)
  local w, h = love.graphics.getDimensions()
  drawDim(105)

  local cx, cy = w / 2, h / 2
  local mx, my = love.mouse.getPosition()

  for _, b in ipairs(S.menuButtons) do
    b:updatePos(cx, cy)
    b:updateHover(mx, my)
  end

  local ticks = math.floor(love.timer.getTime() * 60)
  local glitchx, glitchy = 0, 0
  if ticks % 60 == 0 and love.math.random() < 0.3 then
    glitchx = love.math.random(-4, 4)
    glitchy = love.math.random(-2, 2)
  end

  love.graphics.setFont(S.fonts.title)
  U.setColor255(255, 255, 255, 255)
  love.graphics.printf("MAIN MENU", 0, cy - 350 + glitchy, w, "center")

  local labelFont = S.fonts.small
  local valueFont = S.fonts.medium
  local labelOffset = -20
  local valueOffset = 10

  local rowPlayers = cy - 170
  local rowTime = cy - 80
  local rowBoard = cy + 10
  local rowVolume = cy + 100

  love.graphics.setFont(labelFont)
  U.setColor255(255, 255, 255, 255)
  love.graphics.printf("Number of Players:", 0, rowPlayers + labelOffset, w, "center")
  love.graphics.setFont(valueFont)
  love.graphics.printf(tostring(S.cfg.numPlayers), 0, rowPlayers + valueOffset, w, "center")

  love.graphics.setFont(labelFont)
  love.graphics.printf("Time (sec):", 0, rowTime + labelOffset, w, "center")
  love.graphics.setFont(valueFont)
  love.graphics.printf(tostring(S.cfg.timeLimit), 0, rowTime + valueOffset, w, "center")

  love.graphics.setFont(labelFont)
  love.graphics.printf(("Board Size (%dx%d):"):format(S.cfg.boardSize, S.cfg.boardSize), 0, rowBoard + labelOffset, w, "center")
  love.graphics.setFont(valueFont)
  love.graphics.printf(tostring(S.cfg.boardSize), 0, rowBoard + valueOffset, w, "center")

  love.graphics.setFont(labelFont)
  love.graphics.printf("Music Volume:", 0, rowVolume + labelOffset, w, "center")
  love.graphics.setFont(valueFont)
  local volPct = math.floor((S.cfg.musicVolume or 0.5) * 100 + 0.5)
  love.graphics.printf(tostring(volPct) .. "%", 0, rowVolume + valueOffset, w, "center")




  for _, b in ipairs(S.menuButtons) do
    b:draw(S.fonts.medium, glitchx, glitchy)
  end
end

drawAnimatedPawn = function(S, pawn, x, y, pawnSize, sheet, row, col, allowPulse)
  local anim = S.pawnAnim
  local pulse = allowPulse and S.selectedPawn and pawn == S.selectedPawn
  if anim and sheet and sheet.image and sheet.quads and sheet.quads[row] and sheet.quads[row][col] then
    local scale = pawnSize / anim.frameSize
    if pulse then
      scale = scale * (1.0 + 0.1 * math.sin(love.timer.getTime() * 10))
    end

    local shader = getPawnTintShader()
    local target = {0xab / 255, 0x42 / 255, 0x5a / 255}
    local replace = {
      pawn.player.color[1] / 255,
      pawn.player.color[2] / 255,
      pawn.player.color[3] / 255,
    }
    scale = scale * 1.0
    shader:send("targetColor", target)
    shader:send("replaceColor", replace)
    shader:send("threshold", 0.12)
    local alpha = 255
    if pawn.row and pawn.col and S.board and S.board[pawn.row] and S.board[pawn.row][pawn.col] then
      local cell = S.board[pawn.row][pawn.col]
      if cell and cell.treeCol then
        alpha = 128
      end
    end
    love.graphics.setShader(shader)
    U.setColor255(255, 255, 255, alpha)
    local anchorOffset = anim.frameSize * -0.2
    love.graphics.draw(
      sheet.image, sheet.quads[row][col],
      x, y,
      0,
      scale, scale,
      anim.frameSize / 2, anim.frameSize + anchorOffset
    )
    love.graphics.setShader()
    return
  end

  local canvas = pawn.player.pawnCanvas
  local scale = pawnSize / Config.PAWN_CANVAS_SIZE
  if pulse then
    scale = scale * (1.0 + 0.1 * math.sin(love.timer.getTime() * 10))
  end
  scale = scale * 1.0
  local alpha = 255
  if pawn.row and pawn.col and S.board and S.board[pawn.row] and S.board[pawn.row][pawn.col] then
    local cell = S.board[pawn.row][pawn.col]
    if cell and cell.treeCol then
      alpha = 128
    end
  end
  U.setColor255(255, 255, 255, alpha)
  local anchorOffset = Config.PAWN_CANVAS_SIZE * -0.1
  love.graphics.draw(
    canvas,
    x, y,
    0,
    scale, scale,
    Config.PAWN_CANVAS_SIZE / 2, Config.PAWN_CANVAS_SIZE + anchorOffset
  )
end

local function drawBoard(S)

  local w, h = love.graphics.getDimensions()
  drawDim(70)

  local boardSize = S.cfg.boardSize

  local margin_x = 480
  local margin_y = 230
  local avail_w = math.max(50, w - margin_x)
  local avail_h = math.max(50, h - margin_y)
  local cellSize = math.floor(math.min(avail_w / boardSize, avail_h / boardSize))

  local startX = math.floor((w - (boardSize * cellSize)) / 2)
  local startY = math.floor((h - (boardSize * cellSize)) / 2)
  local pawnSize = math.floor(cellSize * 1.25)

  local moveAnim = S.moveAnim
  local movingPawn = moveAnim and moveAnim.pawn or nil
  local attackAnim = S.attackAnim
  local attackingPawn = attackAnim and attackAnim.pawn or nil
  local deathAnim = S.deathAnim
  local dyingPawn = deathAnim and deathAnim.pawn or nil
  local sheathAnim = S.sheathAnim
  local sheathingPawn = sheathAnim and sheathAnim.pawn or nil
  local guardAnim = S.guardAnim
  local guardingPawn = guardAnim and guardAnim.pawn or nil

  local moves = S.selectedPawn and Game.getValidMoves(S, S.selectedPawn, boardSize) or {}


  local moveSet = {}
  for _, m in ipairs(moves) do
    moveSet[m[1] .. "," .. m[2]] = true
  end

  for r = 1, boardSize do
    for c = 1, boardSize do
      local cell = S.board[r][c]
      local x = startX + (c - 1) * cellSize
      local y = startY + (r - 1) * cellSize
      local centerX = x + cellSize / 2
      local bottomY = y + cellSize


      local overlayR, overlayG, overlayB, overlayA = nil, nil, nil, nil

      if S.selectedPawn and r == S.selectedPawn.row and c == S.selectedPawn.col then
        overlayR, overlayG, overlayB, overlayA = 255, 255, 0, 160
      elseif moveSet[r .. "," .. c] then
        if cell.pawn and cell.pawn.player ~= S.selectedPawn.player then
          overlayR, overlayG, overlayB, overlayA = 255, 150, 150, 160
        else
          overlayR, overlayG, overlayB, overlayA = 150, 255, 150, 160
        end
      end

      if S.tileSheet and S.tileSheet.image and S.tileSheet.quads then
        local tileIndex = 1
        if cell.pawn and cell.pawn.isFlag then
          tileIndex = 2
        end
        local quad = S.tileSheet.quads[tileIndex]
        local scale = cellSize / S.tileSheet.frame_w
        U.setColor255(255, 255, 255, 255)
        love.graphics.draw(S.tileSheet.image, quad, x, y, 0, scale, scale)
      else
        U.setColor255(180, 180, 180, 240)
        love.graphics.rectangle("fill", x, y, cellSize, cellSize, 6, 6)
      end

      if cell.treeCol and S.treeSheet and S.treeSheet.image and S.treeSheet.quads then
        local frame = 1
        local fps = S.treeAnimFps or 6
        local offset = cell.treeOffset or 0
        if fps > 0 then
          frame = (math.floor(love.timer.getTime() * fps) + offset) % S.treeSheet.rows + 1
        end
        local quad = S.treeSheet.quads[frame] and S.treeSheet.quads[frame][cell.treeCol]
        if quad then
          local scale = cellSize / math.max(S.treeSheet.frame_w, S.treeSheet.frame_h)
          U.setColor255(255, 255, 255, 255)
          love.graphics.draw(
            S.treeSheet.image,
            quad,
            centerX, bottomY,
            0,
            scale, scale,
            S.treeSheet.frame_w / 2, S.treeSheet.frame_h
          )
        end
      end

      if cell.isHole and S.rockSprites and #S.rockSprites > 0 then
        local rock = S.rockSprites[cell.rockIndex or 1]
        if rock then
          local rw, rh = rock:getDimensions()
          local scale = cellSize / math.max(rw, rh)
          U.setColor255(255, 255, 255, 255)
          love.graphics.draw(
            rock,
            centerX, bottomY,
            0,
            scale, scale,
            rw / 2, rh
          )
        end
      end

      if overlayR then
        U.setColor255(overlayR, overlayG, overlayB, overlayA)
        love.graphics.rectangle("fill", x, y, cellSize, cellSize, 6, 6)
      end

      U.setColor255(10, 10, 10, 255)
      love.graphics.rectangle("line", x, y, cellSize, cellSize, 6, 6)

      if not cell.isHole then
        local col = Config.CATEGORY_COLORS[cell.category] or {128, 128, 128}
        U.setColor255(col[1], col[2], col[3], 255)
        local s = math.floor(cellSize * 0.16)
        love.graphics.rectangle("fill", x + 4, y + 4, s, s, 4, 4)
      end

      if cell.pawn then
        local pawn = cell.pawn

        if movingPawn and pawn == movingPawn then
          -- drawn after board for movement interpolation
        elseif dyingPawn and pawn == dyingPawn then
          -- drawn after board as death animation
        elseif sheathingPawn and pawn == sheathingPawn then
          local reverse = sheathAnim.mode == "sheath"
          local frameIndex = getPawnSheathFrame(S.pawnAnim, sheathAnim.t, sheathAnim.duration, reverse)
          local row = getDirRow(sheathAnim.dir)
          drawAnimatedPawn(S, pawn, centerX, bottomY, pawnSize, S.pawnAnim and S.pawnAnim.death, row, frameIndex, false)
        elseif attackingPawn and pawn == attackingPawn then
          local frameIndex = getPawnAttackFrame(S.pawnAnim, attackAnim.t, attackAnim.duration)
          local row = getDirRow(attackAnim.dir)
          if attackAnim.choice == 3 then
            row = row + 4
          end
          local col = frameIndex
          if attackAnim.choice == 2 then
            col = col + 4
          end
          drawAnimatedPawn(S, pawn, centerX, bottomY, pawnSize, S.pawnAnim and S.pawnAnim.attack, row, col, false)
        elseif guardingPawn and pawn == guardingPawn and not pawn.isFlag then
          local row = getDirRow(guardAnim.dir) + 4
          drawAnimatedPawn(S, pawn, centerX, bottomY, pawnSize, S.pawnAnim and S.pawnAnim.idle, row, 1, false)
        elseif pawn.isFlag then

          -- animated flag (5 frames) tinted to player color
          if S.flagSheet and S.flagSheet.image and S.flagSheet.quads then
            local sheet = S.flagSheet
            local fps = 10
            local frame = math.floor(love.timer.getTime() * fps) % 5 -- 0..4
            local quad = sheet.quads[1 + frame]

            local scale = pawnSize / sheet.frame_w
            scale = scale * 0.8
            if S.selectedPawn and pawn == S.selectedPawn then
              scale = scale * (1.0 + 0.1 * math.sin(love.timer.getTime() * 10))
            end

            local flip = pawn.player.index == 2 or pawn.player.index == 3
            local sx = flip and -scale or scale
            U.setColor255(pawn.player.color[1], pawn.player.color[2], pawn.player.color[3], 255)
            love.graphics.draw(
              sheet.image, quad,
              centerX, bottomY,
              0,
              sx, scale,
              sheet.frame_w / 2, sheet.frame_h
            )
            U.setColor255(255, 255, 255, 255)

          else
            local canvas = pawn.player.flagCanvas
            local scale = pawnSize / Config.PAWN_CANVAS_SIZE
            scale = scale * 0.8
            local flip = pawn.player.index == 2 or pawn.player.index == 3
            local sx = flip and -scale or scale
            U.setColor255(255, 255, 255, 255)
            love.graphics.draw(
              canvas,
              centerX, bottomY,
              0,
              sx, scale,
              Config.PAWN_CANVAS_SIZE / 2, Config.PAWN_CANVAS_SIZE
            )

          end
        else
          local dir = getPawnIdleDir(pawn, boardSize)
          local frameIndex = getPawnIdleFrame(S.pawnAnim, love.timer.getTime(), pawn.idleOffset)
          local row = getDirRow(dir)
          drawAnimatedPawn(S, pawn, centerX, bottomY, pawnSize, S.pawnAnim and S.pawnAnim.idle, row, frameIndex, true)
        end
      end

    end
  end

  if deathAnim and deathAnim.pawn then
    local centerX = startX + (deathAnim.col - 1) * cellSize + cellSize / 2
    local bottomY = startY + deathAnim.row * cellSize
    local frameIndex = getPawnDeathFrame(S.pawnAnim, deathAnim.t, deathAnim.duration)
    local row = getDirRow(deathAnim.dir)
    drawAnimatedPawn(S, deathAnim.pawn, centerX, bottomY, pawnSize, S.pawnAnim and S.pawnAnim.death, row, frameIndex, false)
  end

  if moveAnim and moveAnim.pawn then
    local denom = moveAnim.duration > 0 and moveAnim.duration or 1
    local t = U.clamp(moveAnim.t / denom, 0, 1)
    local fromX = startX + (moveAnim.fromCol - 1) * cellSize + cellSize / 2
    local fromY = startY + moveAnim.fromRow * cellSize
    local toX = startX + (moveAnim.toCol - 1) * cellSize + cellSize / 2
    local toY = startY + moveAnim.toRow * cellSize
    local x = fromX + (toX - fromX) * t
    local y = fromY + (toY - fromY) * t
    local frameIndex = getPawnMoveFrame(S.pawnAnim, moveAnim.t)
    local row = getDirRow(moveAnim.dir)
    drawAnimatedPawn(S, moveAnim.pawn, x, y, pawnSize, S.pawnAnim and S.pawnAnim.walk, row, frameIndex, false)
  end

  drawHUD(S)
end



local function drawQuestionModal(S)
  local w, h = love.graphics.getDimensions()
  drawDim(150)

  local ui = S.questionUI
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

  U.setColor255(245, 245, 245, 240)
  love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 12, 12)
  U.setColor255(10, 10, 10, 255)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 12, 12)

  love.graphics.setFont(S.fonts.small)
  U.setColor255(10, 10, 10, 255)

  local margin = 20
  local maxWidth = boxW - margin * 2
  local _, lines = S.fonts.small:getWrap(ui.question, maxWidth)
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

    local hover = U.pointInRect(mx, my, rectX, rectY, rectW, rectH)
    if hover then
      U.setColor255(230, 230, 230, 255)
      love.graphics.rectangle("fill", rectX, rectY, rectW, rectH, 6, 6)
    end

    U.setColor255(10, 10, 10, 255)
    love.graphics.print(label, rectX + 6, ay)

    table.insert(ui.answerRects, {x=rectX, y=rectY, w=rectW, h=rectH, ans=ans})
  end
end

local function drawFeedbackOverlay(S)
  local w, h = love.graphics.getDimensions()
  drawDim(120)

  local rectW, rectH = 420, 320
  local x = (w - rectW) / 2
  local y = (h - rectH) / 2

  U.setColor255(245, 245, 245, 240)
  love.graphics.rectangle("fill", x, y, rectW, rectH, 12, 12)
  U.setColor255(10, 10, 10, 255)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", x, y, rectW, rectH, 12, 12)

  love.graphics.setFont(S.fonts.big)
  if S.feedbackUI and S.feedbackUI.ok then
    U.setColor255(0, 200, 0, 255)
    love.graphics.printf("✓", 0, y + 40, w, "center")
  else
    U.setColor255(200, 0, 0, 255)
    love.graphics.printf("X", 0, y + 55, w, "center")
  end
end

function Draw.scene(S)
  if S.state.mode == "splash" then
    drawSplash(S)
  elseif S.state.mode == "menu" then
    drawMenu(S)
  elseif S.state.mode == "game" then
    drawBoard(S)
  end
end

function Draw.overlays(S)
  if S.questionUI then
    drawQuestionModal(S)
  end
  if S.feedbackUI then
    drawFeedbackOverlay(S)
  end
end

return Draw
