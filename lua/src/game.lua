-- src/game.lua
local Config    = require("src.config")
local U         = require("src.util")
local Button    = require("src.button")
local Assets    = require("src.assets")
local Questions = require("src.questions")

local Game = {}

-- -----------------------------
-- Board / gameplay helpers
-- -----------------------------
local function buildPlayersAndPawns(S, numPlayers, boardSize)
  S.players = {}
  S.pawns = {}

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
      color = Config.PLAYER_COLORS[i],
      score = 0,
      pawnCanvas = nil,
      flagCanvas = nil,
      scaleBoost = (i == 1) and 1.3 or (i == 4) and 1.3 or 1.0,

    }


    if S.pawnBaseImg and S.flagBaseImg then
      p.pawnCanvas = Assets.makeTintedCanvas(S.pawnBaseImg, p.color, 1.0)
      p.flagCanvas = Assets.makeTintedCanvas(S.flagBaseImg, p.color, 0.35)
    else
      p.pawnCanvas = Assets.makeFallbackPawnCanvas(p.color, false)
      p.flagCanvas = Assets.makeFallbackPawnCanvas(p.color, true)
    end

    table.insert(S.players, p)

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
        table.insert(S.pawns, {
          player = p,
          row = r,
          col = c,
          isFlag = isFlag,
        })
      end
    end
  end
end

local function initBoard(S, boardSize)
  S.board = {}

  -- Build a balanced bag of categories, then shuffle for random placement
  local cats = {}
  for k, _ in pairs(Config.CATEGORY_COLORS) do table.insert(cats, k) end
  table.sort(cats)

  local totalCells = boardSize * boardSize
  local bag = {}
  while #bag < totalCells do
    for _, cat in ipairs(cats) do
      table.insert(bag, cat)
      if #bag >= totalCells then break end
    end
  end
  U.shuffle(bag)

  for r = 1, boardSize do
    S.board[r] = {}
    for c = 1, boardSize do
      local cat = table.remove(bag) -- pop gives random distribution
      S.board[r][c] = {
        isHole = false,
        pawn = nil,
        category = cat,
      }
    end
  end

  for _, p in ipairs(S.pawns) do
    S.board[p.row][p.col].pawn = p
  end

  local free = {}
  for r = 1, boardSize do
    for c = 1, boardSize do
      if S.board[r][c].pawn == nil then
        table.insert(free, {r, c})
      end
    end
  end

  local count = math.min(Config.HOLE_COUNT, #free)
  for i = 1, count do
    local idx = love.math.random(#free)
    local pos = table.remove(free, idx)
    S.board[pos[1]][pos[2]].isHole = true
  end
end

local function getValidMoves(S, pawn, boardSize)
  if not pawn then return {} end
  local moves = {}
  local r, c = pawn.row, pawn.col
  local dirs = {{0,1},{0,-1},{1,0},{-1,0}}
  for _, d in ipairs(dirs) do
    local nr, nc = r + d[1], c + d[2]
    if nr >= 1 and nr <= boardSize and nc >= 1 and nc <= boardSize then
      local cell = S.board[nr][nc]
      if not cell.isHole then
        if not (cell.pawn and cell.pawn.player == pawn.player) then
          table.insert(moves, {nr, nc})
        end
      end
    end
  end
  return moves
end

local function startFeedback(S, ok, onDone)
  S.feedbackUI = {
    ok = ok,
    t = 0,
    duration = 0.9,
    onDone = onDone,
  }
end

local function beginQuestion(S, category, timeLimit, requiredCorrect, onFinish)
  local qdata = Questions.getRandomQuestionFrom(S.questionsByCategory, category)
  if not qdata then
    onFinish(true)
    return
  end

  local q = qdata.question
  local correct = qdata.correct
  local answers = {correct, qdata.wrong[1], qdata.wrong[2], qdata.wrong[3]}
  U.shuffle(answers)

  S.questionUI = {
    question = q,
    correct = correct,
    answers = answers,
    category = category,
    timeLimit = timeLimit,
    t = 0,
    required = requiredCorrect or 1,
    correctSoFar = 0,
    onFinish = onFinish,
    answerRects = nil,
  }
end

local function applyPendingAction(S, success)
  if not S.pendingAction then return end
  local act = S.pendingAction
  S.pendingAction = nil

  local current = S.players[S.currentPlayerIndex]

  if not success then
    startFeedback(S, false, function()
      S.selectedPawn = nil
      S.currentPlayerIndex = (S.currentPlayerIndex % #S.players) + 1
    end)
    return
  end

  local fromPawn = act.pawn
  local tr, tc = act.toR, act.toC
  local targetCell = S.board[tr][tc]
  local fromRow, fromCol = fromPawn.row, fromPawn.col


  if act.type == "attack" and targetCell.pawn and targetCell.pawn.player ~= fromPawn.player then
    local victim = targetCell.pawn
    S.board[victim.row][victim.col].pawn = nil
    for i = #S.pawns, 1, -1 do
      if S.pawns[i] == victim then table.remove(S.pawns, i) break end
    end
    current.score = current.score + 5
  else
    current.score = current.score + 1
  end

  S.board[fromPawn.row][fromPawn.col].pawn = nil
  fromPawn.row, fromPawn.col = tr, tc
  targetCell.pawn = fromPawn

  local dir
  if tr < fromRow then
    dir = "down"
  elseif tr > fromRow then
    dir = "up"
  elseif tc < fromCol then
    dir = "left"
  else
    dir = "right"
  end

  S.moveAnim = {
    pawn = fromPawn,
    fromRow = fromRow,
    fromCol = fromCol,
    toRow = tr,
    toCol = tc,
    dir = dir,
    t = 0,
    duration = 0.45,
  }

  startFeedback(S, true, function()

    S.selectedPawn = nil
    S.currentPlayerIndex = (S.currentPlayerIndex % #S.players) + 1
  end)
end

local function askForAction(S, actType, pawn, toR, toC, category)
  S.pendingAction = {
    type = actType,
    pawn = pawn,
    toR = toR,
    toC = toC,
    category = category,
  }

  local needed = (actType == "attack") and 2 or 1
  beginQuestion(S, category, S.cfg.timeLimit, needed, function(ok)
    applyPendingAction(S, ok)
  end)
end

-- -----------------------------
-- Menu build
-- -----------------------------
function Game.buildMenuButtons(S)
  local function clampPlayers(delta)
    S.cfg.numPlayers = U.clamp(S.cfg.numPlayers + delta, 2, 4)
  end
  local function clampTime(delta)
    S.cfg.timeLimit = U.clamp(S.cfg.timeLimit + delta, 5, 120)
  end
  local function clampBoard(delta)
    S.cfg.boardSize = U.clamp(S.cfg.boardSize + delta, 6, 32)
  end

  -- NEW: volume clamp (0..1), step is 0.05 = 5%
  local function clampVolume(delta)
    S.cfg.musicVolume = U.clamp((S.cfg.musicVolume or 0.5) + delta, 0, 1)
    if S.audioFFT and S.audioFFT.setVolume then
      S.audioFFT:setVolume(S.cfg.musicVolume)
    elseif S.audioFFT and S.audioFFT.source and S.audioFFT.source.setVolume then
      -- fallback if you didn't add setVolume() yet
      S.audioFFT.source:setVolume(S.cfg.musicVolume)
    end
  end

  local function startGame()
    buildPlayersAndPawns(S, S.cfg.numPlayers, S.cfg.boardSize)
    initBoard(S, S.cfg.boardSize)
    S.currentPlayerIndex = 1
    S.selectedPawn = nil
    S.questionUI = nil
    S.feedbackUI = nil
    S.pendingAction = nil
    S.moveAnim = nil
    S.state.mode = "game"

  end

  S.menuButtons = {
    -- players
    Button.new(-100, -120, 50, 50, "-", {20,20,20}, {200,50,50}, function() clampPlayers(-1) end),
    Button.new( 100, -120, 50, 50, "+", {20,20,20}, {200,50,50}, function() clampPlayers( 1) end),

    -- time
    Button.new(-100,  -40, 50, 50, "-", {20,20,20}, {200,50,50}, function() clampTime(-5) end),
    Button.new( 100,  -40, 50, 50, "+", {20,20,20}, {200,50,50}, function() clampTime( 5) end),

    -- board size
    Button.new(-100,   40, 50, 50, "-", {20,20,20}, {200,50,50}, function() clampBoard(-1) end),
    Button.new( 100,   40, 50, 50, "+", {20,20,20}, {200,50,50}, function() clampBoard( 1) end),

    -- NEW: music volume
    Button.new(-100,  120, 50, 50, "-", {20,20,20}, {200,50,50}, function() clampVolume(-0.05) end),
    Button.new( 100,  120, 50, 50, "+", {20,20,20}, {200,50,50}, function() clampVolume( 0.05) end),

    -- play (moved down to make room)
    Button.new(  -80,  200, 160, 60, "PLAY", {50,50,200}, {100,149,237}, startGame),
  }
end

-- -----------------------------
-- Update + input
-- -----------------------------
function Game.update(S, dt)
  if S.moveAnim then
    S.moveAnim.t = S.moveAnim.t + dt
    if S.moveAnim.t >= S.moveAnim.duration then
      S.moveAnim = nil
    end
  end

  if S.feedbackUI then

    S.feedbackUI.t = S.feedbackUI.t + dt
    if S.feedbackUI.t >= S.feedbackUI.duration then
      local done = S.feedbackUI.onDone
      S.feedbackUI = nil
      if done then done() end
    end
    return
  end

  if S.questionUI then
    S.questionUI.t = S.questionUI.t + dt
    if S.questionUI.t >= S.questionUI.timeLimit then
      local finish = S.questionUI.onFinish
      S.questionUI = nil
      if finish then finish(false) end
    end
    return
  end
end

function Game.mousepressed(S, x, y, button)
  if S.feedbackUI then return end

  if S.state.mode == "splash" then
    if button == 1 then S.state.mode = "menu" end
    return
  end

  if S.state.mode == "menu" then
    if button == 1 then
      local w, h = love.graphics.getDimensions()
      local cx, cy = w / 2, h / 2
      local mx, my = love.mouse.getPosition()
      for _, b in ipairs(S.menuButtons) do
        b:updatePos(cx, cy)
        b:updateHover(mx, my)
      end
      for _, b in ipairs(S.menuButtons) do
        if b:mousepressed(x, y, button) then break end
      end
    end
    return
  end

  -- Answer click handling
  if S.questionUI then
    if button == 1 and S.questionUI.answerRects then
      for _, r in ipairs(S.questionUI.answerRects) do
        if U.pointInRect(x, y, r.x, r.y, r.w, r.h) then
          local correct = (r.ans == S.questionUI.correct)

          if correct then
            S.questionUI.correctSoFar = S.questionUI.correctSoFar + 1
          end

          if not correct then
            local finish = S.questionUI.onFinish
            S.questionUI = nil
            if finish then finish(false) end
            return
          end

          if S.questionUI.correctSoFar >= S.questionUI.required then
            local finish = S.questionUI.onFinish
            S.questionUI = nil
            if finish then finish(true) end
            return
          else
            local cat = S.questionUI.category
            local tl = S.questionUI.timeLimit
            local required = S.questionUI.required
            local soFar = S.questionUI.correctSoFar
            local finish = S.questionUI.onFinish

            S.questionUI = nil
            beginQuestion(S, cat, tl, required, finish)
            if S.questionUI then
              S.questionUI.correctSoFar = soFar
            end
            return
          end
        end
      end
    end
    return
  end

  -- Game board click handling
  if S.state.mode == "game" then
    if button ~= 1 then return end

    local boardSize = S.cfg.boardSize

    local w, h = love.graphics.getDimensions()
    local margin_x = 480
    local margin_y = 230
    local avail_w = math.max(50, w - margin_x)
    local avail_h = math.max(50, h - margin_y)
    local cellSize = math.floor(math.min(avail_w / boardSize, avail_h / boardSize))
    local startX = math.floor((w - (boardSize * cellSize)) / 2)
    local startY = math.floor((h - (boardSize * cellSize)) / 2)

    local current = S.players[S.currentPlayerIndex]

    local function cellAt(mx, my)
      if mx < startX or my < startY then return nil end
      local cx = math.floor((mx - startX) / cellSize) + 1
      local cy = math.floor((my - startY) / cellSize) + 1
      if cx < 1 or cx > boardSize or cy < 1 or cy > boardSize then return nil end
      return cy, cx
    end

    local r, c = cellAt(x, y)
    if not r then return end

    local cell = S.board[r][c]

    if not S.selectedPawn then
      if cell.pawn and cell.pawn.player == current then
        S.selectedPawn = cell.pawn
      end
      return
    end

    local dist = math.abs(S.selectedPawn.row - r) + math.abs(S.selectedPawn.col - c)
    if dist ~= 1 then
      S.selectedPawn = nil
      return
    end

    if cell.isHole then
      S.selectedPawn = nil
      return
    end

    if not cell.pawn then
      askForAction(S, "move", S.selectedPawn, r, c, cell.category)
      return
    else
      if cell.pawn.player ~= current then
        askForAction(S, "attack", S.selectedPawn, r, c, cell.category)
      else
        S.selectedPawn = nil
      end
      return
    end
  end
end

function Game.keypressed(S, key)
  if key == "escape" then
    if S.questionUI then
      local finish = S.questionUI.onFinish
      S.questionUI = nil
      if finish then finish(false) end
      return
    end
    if S.state.mode == "game" then
      S.state.mode = "menu"
      return
    end
  end
end

-- Expose for Draw module: valid moves
function Game.getValidMoves(S, pawn, boardSize)
  return getValidMoves(S, pawn, boardSize)
end

return Game
