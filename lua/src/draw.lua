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

local function drawCurrentPlayerPanel(S, x, y)
  local p = S.players[S.currentPlayerIndex]
  if not p then return end

  U.setColor255(255, 255, 255, 255)
  love.graphics.setFont(S.fonts.small)
  love.graphics.print("Current Turn", x + 60, y)

  -- icon preview still uses pawnCanvas
  U.setColor255(255, 255, 255, 255)
  love.graphics.draw(p.pawnCanvas, x + 60, y + 45, 0, 2.2, 2.2)

  love.graphics.setFont(S.fonts.name)
  U.setColor255(p.color[1], p.color[2], p.color[3], 255)
  love.graphics.printf(p.name, x, y + 130, 200, "center")

  love.graphics.setFont(S.fonts.small)
  U.setColor255(255, 255, 255, 255)
  love.graphics.printf("Score: " .. p.score, x, y + 165, 200, "center")
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
  love.graphics.printf("MAIN MENU", 0, cy - 260 + glitchy, w, "center")

  love.graphics.setFont(S.fonts.medium)
  U.setColor255(255, 255, 255, 255)
  love.graphics.printf("Number of Players:", 0, cy - 190, w, "center")
  love.graphics.setFont(S.fonts.title)
  love.graphics.printf(tostring(S.cfg.numPlayers), 0, cy - 155, w, "center")

  love.graphics.setFont(S.fonts.medium)
  love.graphics.printf("Time (sec):", 0, cy - 110, w, "center")
  love.graphics.setFont(S.fonts.title)
  love.graphics.printf(tostring(S.cfg.timeLimit), 0, cy - 75, w, "center")

  love.graphics.setFont(S.fonts.medium)
  love.graphics.printf(("Board Size (%dx%d):"):format(S.cfg.boardSize, S.cfg.boardSize), 0, cy - 25, w, "center")
  love.graphics.setFont(S.fonts.title)
  love.graphics.printf(tostring(S.cfg.boardSize), 0, cy + 10, w, "center")

  love.graphics.setFont(S.fonts.medium)
  love.graphics.printf("Music Volume:", 0, cy + 70, w, "center")
  love.graphics.setFont(S.fonts.title)
  local volPct = math.floor((S.cfg.musicVolume or 0.5) * 100 + 0.5)
  love.graphics.printf(tostring(volPct) .. "%", 0, cy + 105, w, "center")

  for _, b in ipairs(S.menuButtons) do
    b:draw(S.fonts.medium, glitchx, glitchy)
  end
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
  local pawnSize = math.floor(cellSize * 0.7)

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

        if pawn.isFlag then
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
              x + cellSize / 2, y + cellSize / 2,
              0,
              scale, scale,
              sheet.frame_w / 2, sheet.frame_h / 2
            )
            U.setColor255(255, 255, 255, 255)
          else
            local canvas = pawn.player.flagCanvas
            local scale = pawnSize / Config.PAWN_CANVAS_SIZE
            U.setColor255(255, 255, 255, 255)
            love.graphics.draw(
              canvas,
              x + cellSize / 2, y + cellSize / 2,
              0,
              scale, scale,
              Config.PAWN_CANVAS_SIZE / 2, Config.PAWN_CANVAS_SIZE / 2
            )
          end
        else
          -- pawn idle row0 frames 0-7
          if S.pawnSheet and S.pawnSheet.image and S.pawnSheet.quads then
            local sheet = S.pawnSheet
            local fps = 8
            local frame = math.floor(love.timer.getTime() * fps) % 8 -- 0..7
            local quad = sheet.quads[1 + frame]

            local scale = pawnSize / sheet.frame_w
            if S.selectedPawn and pawn == S.selectedPawn then
              scale = scale * (1.0 + 0.1 * math.sin(love.timer.getTime() * 10))
            end

            U.setColor255(pawn.player.color[1], pawn.player.color[2], pawn.player.color[3], 255)
            love.graphics.draw(
              sheet.image, quad,
              x + cellSize / 2, y + cellSize / 2,
              0,
              scale, scale,
              sheet.frame_w / 2, sheet.frame_h / 2
            )
            U.setColor255(255, 255, 255, 255)
          else
            local canvas = pawn.player.pawnCanvas
            local scale = pawnSize / Config.PAWN_CANVAS_SIZE
            if S.selectedPawn and pawn == S.selectedPawn then
              scale = scale * (1.0 + 0.1 * math.sin(love.timer.getTime() * 10))
            end
            U.setColor255(255, 255, 255, 255)
            love.graphics.draw(
              canvas,
              x + cellSize / 2, y + cellSize / 2,
              0,
              scale, scale,
              Config.PAWN_CANVAS_SIZE / 2, Config.PAWN_CANVAS_SIZE / 2
            )
          end
        end
      end
    end
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
