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


local function getPawnIdleFrame(anim, t)
  if not anim or not anim.frames or #anim.frames == 0 then
    return 1
  end
  local frameCount = math.min(4, #anim.frames)
  local fps = anim.fps * 0.5
  return (math.floor(t * fps) % frameCount) + 1
end

local function getPawnMoveFrame(anim, t)
  if not anim or not anim.frames or #anim.frames == 0 then
    return 1
  end
  local first = math.min(20, #anim.frames)
  local last = math.min(40, #anim.frames)
  if last < first then
    first, last = 1, #anim.frames
  end
  local range = math.max(1, last - first + 1)
  local fps = anim.fps * 0.5
  return first + (math.floor(t * fps) % range)
end

local function getPawnAttackFrame(anim, t, duration)
  if not anim or not anim.frames or #anim.frames == 0 then
    return 1
  end
  local first = math.min(12, #anim.frames)
  local last = math.min(19, #anim.frames)
  if last < first then
    first, last = 1, #anim.frames
  end
  local range = math.max(1, last - first + 1)
  if range == 1 then
    return first
  end

  local progress = 0
  if duration and duration > 0 then
    progress = U.clamp(t / duration, 0, 1)
  end
  return first + math.floor(progress * (range - 1))
end


local function getPawnAnchor(anim, dir)
  if not anim or not anim.crop or not anim.crop[dir] then
    return 0, 0
  end

  local rect = anim.crop[dir]
  local anchor = anim.anchors and anim.anchors[dir]
  local ax = rect.w * 0.5
  local ay = rect.h * 0.5
  if anchor then
    ax = U.clamp(anchor.x or ax, 0, rect.w)
    ay = U.clamp(anchor.y or ay, 0, rect.h)
  end
  return ax, ay
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
  drawAnimatedPawn(S, previewPawn, x + 110, y + 240, 170, "left", frameIndex, true)


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
  love.graphics.printf("MAIN MENU", 0, cy - 300 + glitchy, w, "center")


  love.graphics.setFont(S.fonts.medium)
  U.setColor255(255, 255, 255, 255)
  love.graphics.printf("Number of Players:", 0, cy - 230, w, "center")
  love.graphics.setFont(S.fonts.title)
  love.graphics.printf(tostring(S.cfg.numPlayers), 0, cy - 190, w, "center")

  love.graphics.setFont(S.fonts.medium)
  love.graphics.printf("Time (sec):", 0, cy - 140, w, "center")
  love.graphics.setFont(S.fonts.title)
  love.graphics.printf(tostring(S.cfg.timeLimit), 0, cy - 100, w, "center")

  love.graphics.setFont(S.fonts.medium)
  love.graphics.printf(("Board Size (%dx%d):"):format(S.cfg.boardSize, S.cfg.boardSize), 0, cy - 50, w, "center")
  love.graphics.setFont(S.fonts.title)
  love.graphics.printf(tostring(S.cfg.boardSize), 0, cy - 10, w, "center")

  love.graphics.setFont(S.fonts.medium)
  love.graphics.printf("Music Volume:", 0, cy + 40, w, "center")
  love.graphics.setFont(S.fonts.title)
  local volPct = math.floor((S.cfg.musicVolume or 0.5) * 100 + 0.5)
  love.graphics.printf(tostring(volPct) .. "%", 0, cy + 80, w, "center")


  for _, b in ipairs(S.menuButtons) do
    b:draw(S.fonts.medium, glitchx, glitchy)
  end
end

drawAnimatedPawn = function(S, pawn, x, y, pawnSize, dir, frameIndex, allowPulse)
  local anim = S.pawnAnim
  local pulse = allowPulse and S.selectedPawn and pawn == S.selectedPawn
  if anim and anim.frames and #anim.frames > 0 then
    local frame = anim.frames[frameIndex] or anim.frames[1]
    local quad = frame.quads and frame.quads[dir]
    local rect = anim.crop and anim.crop[dir]
    if quad and rect then
      local scale = pawnSize / math.max(rect.w, rect.h)
      if pulse then
        scale = scale * (1.0 + 0.1 * math.sin(love.timer.getTime() * 10))
      end

      local ax, ay = getPawnAnchor(anim, dir)
      local anchorOffset = rect.h * 0.18
      local shader = getPawnTintShader()
      local target = {0x74 / 255, 0x75 / 255, 0x7c / 255}
      local replace = {
        pawn.player.color[1] / 255,
        pawn.player.color[2] / 255,
        pawn.player.color[3] / 255,
      }
      scale = scale * (pawn.player.scaleBoost or 1.0)
      shader:send("targetColor", target)
      shader:send("replaceColor", replace)
      shader:send("threshold", 0.08)
      love.graphics.setShader(shader)
      U.setColor255(255, 255, 255, 255)
      love.graphics.draw(
        frame.image, quad,
        x, y,
        0,
        scale, scale,
        ax, ay + anchorOffset
      )
      love.graphics.setShader()
      return
    end
  end

  local canvas = pawn.player.pawnCanvas
  local scale = pawnSize / Config.PAWN_CANVAS_SIZE
  if pulse then
    scale = scale * (1.0 + 0.1 * math.sin(love.timer.getTime() * 10))
  end
  scale = scale * (pawn.player.scaleBoost or 1.0)
  local anchorOffset = Config.PAWN_CANVAS_SIZE * 0.18
  U.setColor255(255, 255, 255, 255)
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
  local pawnSize = math.floor(cellSize * 0.85)

  local moveAnim = S.moveAnim
  local movingPawn = moveAnim and moveAnim.pawn or nil
  local attackAnim = S.attackAnim
  local attackingPawn = attackAnim and attackAnim.pawn or nil

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


      local cellR, cellG, cellB = 180, 180, 180
      local cellA = 240

      -- holes: 50% transparent
      if cell.isHole then
        cellR, cellG, cellB = 0, 0, 0
        cellA = 120
      end

      -- highlights override (keep opaque)
      if S.selectedPawn and r == S.selectedPawn.row and c == S.selectedPawn.col then
        cellR, cellG, cellB = 255, 255, 0
        cellA = 240
      elseif moveSet[r .. "," .. c] then
        if cell.pawn and cell.pawn.player ~= S.selectedPawn.player then
          cellR, cellG, cellB = 255, 150, 150
          cellA = 240
        else
          cellR, cellG, cellB = 150, 255, 150
          cellA = 240
        end
      end

      U.setColor255(cellR, cellG, cellB, cellA)
      love.graphics.rectangle("fill", x, y, cellSize, cellSize, 6, 6)

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
        elseif attackingPawn and pawn == attackingPawn then
          local frameIndex = getPawnAttackFrame(S.pawnAnim, attackAnim.t, attackAnim.duration)
          drawAnimatedPawn(S, pawn, centerX, bottomY, pawnSize, attackAnim.dir, frameIndex, false)
        elseif pawn.isFlag then

          -- animated flag (5 frames) tinted to player color
          if S.flagSheet and S.flagSheet.image and S.flagSheet.quads then
            local sheet = S.flagSheet
            local fps = 10
            local frame = math.floor(love.timer.getTime() * fps) % 5 -- 0..4
            local quad = sheet.quads[1 + frame]

            local scale = pawnSize / sheet.frame_w
            if S.selectedPawn and pawn == S.selectedPawn then
              scale = scale * (1.0 + 0.1 * math.sin(love.timer.getTime() * 10))
            end

            U.setColor255(pawn.player.color[1], pawn.player.color[2], pawn.player.color[3], 255)
            love.graphics.draw(
              sheet.image, quad,
              centerX, bottomY,
              0,
              scale, scale,
              sheet.frame_w / 2, sheet.frame_h
            )
            U.setColor255(255, 255, 255, 255)
          else
            local canvas = pawn.player.flagCanvas
            local scale = pawnSize / Config.PAWN_CANVAS_SIZE
            U.setColor255(255, 255, 255, 255)
            love.graphics.draw(
              canvas,
              centerX, bottomY,
              0,
              scale, scale,
              Config.PAWN_CANVAS_SIZE / 2, Config.PAWN_CANVAS_SIZE
            )
          end
        else
          local dir = getPawnIdleDir(pawn, boardSize)
          local frameIndex = getPawnIdleFrame(S.pawnAnim, love.timer.getTime())
          drawAnimatedPawn(S, pawn, centerX, bottomY, pawnSize, dir, frameIndex, true)
        end
      end

    end
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
    drawAnimatedPawn(S, moveAnim.pawn, x, y, pawnSize, moveAnim.dir, frameIndex, false)
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
