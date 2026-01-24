-- src/game.lua
local Config    = require("src.config")
local U         = require("src.util")
local Button    = require("src.button")
local Assets    = require("src.assets")
local Questions = require("src.questions")

local Game = {}

local SAVE_PATH = "savegame.json"

local function getWorkingSavePath()
  local cwd = love.filesystem.getWorkingDirectory and love.filesystem.getWorkingDirectory() or nil
  if not cwd or cwd == "" then
    return nil
  end
  return cwd .. "/" .. SAVE_PATH
end

local function getSourceSavePath()
  local realDir = love.filesystem.getRealDirectory("main.lua")
  if not realDir or realDir == "" then
    return nil
  end
  return realDir .. "/" .. SAVE_PATH
end

local function getDebugPath()
  local cwd = love.filesystem.getWorkingDirectory and love.filesystem.getWorkingDirectory() or nil
  if cwd and cwd ~= "" then
    return cwd .. "/save_debug.txt"
  end
  local sourcePath = getSourceSavePath()
  if sourcePath then
    return sourcePath:gsub(SAVE_PATH .. "$", "save_debug.txt")
  end
  return "save_debug.txt"
end

local function debugLog(message)
  print(message)
  local path = getDebugPath()
  local file = io.open(path, "a")
  if file then
    file:write(message .. "\n")
    file:close()
  end
end

local function writeSaveFile(content)
  local savedPaths = {}
  debugLog("Save debug: cwd=" .. tostring(love.filesystem.getWorkingDirectory and love.filesystem.getWorkingDirectory() or nil)
    .. " source=" .. tostring(getSourceSavePath()))

  local workingPath = getWorkingSavePath()
  if workingPath then
    local file, err = io.open(workingPath, "w")
    if file then
      file:write(content)
      file:close()
      table.insert(savedPaths, workingPath)
      debugLog("Save debug: wrote " .. workingPath)
    else
      debugLog("Save debug: failed " .. workingPath .. " -> " .. tostring(err))
    end
  end

  local sourcePath = getSourceSavePath()
  if sourcePath then
    local sourceFile, sourceErr = io.open(sourcePath, "w")
    if sourceFile then
      sourceFile:write(content)
      sourceFile:close()
      table.insert(savedPaths, sourcePath)
      debugLog("Save debug: wrote " .. sourcePath)
    else
      debugLog("Save debug: failed " .. sourcePath .. " -> " .. tostring(sourceErr))
    end
  end

  local ok, loveErr = love.filesystem.write(SAVE_PATH, content)
  if ok then
    local saveDir = love.filesystem.getSaveDirectory()
    if saveDir then
      local lovePath = saveDir .. "/" .. SAVE_PATH
      table.insert(savedPaths, lovePath)
      debugLog("Save debug: wrote " .. lovePath)
    end
  else
    debugLog("Save debug: failed love save -> " .. tostring(loveErr))
  end

  return savedPaths
end

local function readSaveFile()
  local workingPath = getWorkingSavePath()
  if workingPath then
    local file = io.open(workingPath, "r")
    if file then
      local content = file:read("*a")
      file:close()
      return content
    end
  end

  local sourcePath = getSourceSavePath()
  if sourcePath then
    local sourceFile = io.open(sourcePath, "r")
    if sourceFile then
      local content = sourceFile:read("*a")
      sourceFile:close()
      return content
    end
  end

  if love.filesystem.getInfo(SAVE_PATH) then
    return love.filesystem.read(SAVE_PATH)
  end

  return nil
end

local function removeSaveFile()
  local workingPath = getWorkingSavePath()
  if workingPath then
    pcall(os.remove, workingPath)
  end

  local sourcePath = getSourceSavePath()
  if sourcePath then
    pcall(os.remove, sourcePath)
  end
  if love.filesystem.getInfo(SAVE_PATH) then
    love.filesystem.remove(SAVE_PATH)
  end
end

local function saveFileExists()
  local workingPath = getWorkingSavePath()
  if workingPath then
    local file = io.open(workingPath, "r")
    if file then
      file:close()
      return true
    end
  end

  local sourcePath = getSourceSavePath()
  if sourcePath then
    local sourceFile = io.open(sourcePath, "r")
    if sourceFile then
      sourceFile:close()
      return true
    end
  end
  return false
end


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
      index = i,
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
        local homeSide = (c <= boardSize / 2) and "left" or "right"
        table.insert(S.pawns, {
          player = p,
          row = r,
          col = c,
          isFlag = isFlag,
          homeSide = homeSide,
          idleOffset = love.math.random(0, 3),
        })
      end

    end
  end
end

local function saveGameState(S)
  print("Save debug: saveGameState called")
  local data = {
    cfg = S.cfg,
    currentPlayerIndex = S.currentPlayerIndex,
    players = {},
    pawns = {},
    board = {},
  }

  for _, player in ipairs(S.players) do
    table.insert(data.players, {
      name = player.name,
      index = player.index,
      color = player.color,
      score = player.score,
      scaleBoost = player.scaleBoost,
    })
  end

  for _, pawn in ipairs(S.pawns) do
    local playerIndex = nil
    for idx, player in ipairs(S.players) do
      if pawn.player == player then
        playerIndex = idx
        break
      end
    end
    table.insert(data.pawns, {
      playerIndex = playerIndex,
      row = pawn.row,
      col = pawn.col,
      isFlag = pawn.isFlag,
      homeSide = pawn.homeSide,
      idleOffset = pawn.idleOffset,
    })
  end

  for r = 1, #S.board do
    data.board[r] = {}
    for c = 1, #S.board[r] do
      local cell = S.board[r][c]
      data.board[r][c] = {
        category = cell.category,
        isHole = cell.isHole,
        rockIndex = cell.rockIndex,
        treeCol = cell.treeCol,
        treeOffset = cell.treeOffset,
      }
    end
  end

  local encoded = U.encodeJson(data)
  if not encoded then
    print("Save debug: JSON encode failed")
    local paths = writeSaveFile("{\"error\":\"encode failed\"}")
    if #paths == 0 then
      print("Warning: failed to write savegame.json")
    else
      print("Saved error payload to: " .. table.concat(paths, ", "))
    end
    return
  end

  local paths = writeSaveFile(encoded)
  if #paths == 0 then
    print("Warning: failed to write savegame.json")
  else
    print("Saved game to: " .. table.concat(paths, ", "))
  end
end

local function clearSavedGame()
  removeSaveFile()
end

local function hasSavedGame()
  return saveFileExists()
end

local function loadSavedGame(S)
  debugLog("Load debug: attempting load")
  local content = readSaveFile()
  if not content then
    debugLog("Load debug: no save file found")
    return false
  end

  local decoded = U.decodeJson(content)
  if not decoded then
    debugLog("Load debug: JSON decode failed")
    return false
  end

  S.cfg = decoded.cfg or S.cfg
  S.players = {}
  S.pawns = {}
  S.board = {}

  for _, playerData in ipairs(decoded.players or {}) do
    table.insert(S.players, {
      name = playerData.name or "Player",
      index = playerData.index or 1,
      color = playerData.color or {255, 255, 255},
      score = playerData.score or 0,
      pawnCanvas = nil,
      flagCanvas = nil,
      scaleBoost = playerData.scaleBoost or 1.0,
    })
  end

  for _, player in ipairs(S.players) do
    if S.pawnBaseImg and S.flagBaseImg then
      player.pawnCanvas = Assets.makeTintedCanvas(S.pawnBaseImg, player.color, 1.0)
      player.flagCanvas = Assets.makeTintedCanvas(S.flagBaseImg, player.color, 0.35)
    else
      player.pawnCanvas = Assets.makeFallbackPawnCanvas(player.color, false)
      player.flagCanvas = Assets.makeFallbackPawnCanvas(player.color, true)
    end
  end

  for r = 1, #(decoded.board or {}) do
    S.board[r] = {}
    for c = 1, #(decoded.board[r] or {}) do
      local cell = decoded.board[r][c]
      local rockIndex = cell.rockIndex
      if cell.isHole and not rockIndex and S.rockSprites and #S.rockSprites > 0 then
        rockIndex = love.math.random(1, #S.rockSprites)
      end
      local treeCol = cell.treeCol or cell.treeIndex
      local treeOffset = cell.treeOffset
      if treeCol and S.treeColumns then
        local valid = false
        for _, col in ipairs(S.treeColumns) do
          if col == treeCol then
            valid = true
            break
          end
        end
        if not valid then
          treeCol = S.treeColumns[love.math.random(1, #S.treeColumns)]
        end
      end
      if treeCol and not treeOffset then
        if S.treeSheet and S.treeSheet.rows then
          treeOffset = love.math.random(0, S.treeSheet.rows - 1)
        else
          treeOffset = love.math.random(0, 12)
        end
      end
      S.board[r][c] = {
        category = cell.category,
        isHole = cell.isHole,
        rockIndex = rockIndex,
        treeCol = treeCol,
        treeOffset = treeOffset,
        pawn = nil,
      }
    end
  end

  for _, pawnData in ipairs(decoded.pawns or {}) do
    local player = S.players[pawnData.playerIndex or 1]
    if player then
      local homeSide = pawnData.homeSide
      if not homeSide then
        homeSide = (pawnData.col <= (S.cfg.boardSize or 1) / 2) and "left" or "right"
      end
      local pawn = {
        player = player,
        row = pawnData.row,
        col = pawnData.col,
        isFlag = pawnData.isFlag,
        homeSide = homeSide,
        idleOffset = pawnData.idleOffset or 0,
      }
      table.insert(S.pawns, pawn)
      if S.board[pawn.row] and S.board[pawn.row][pawn.col] then
        S.board[pawn.row][pawn.col].pawn = pawn
      end
    end
  end

  S.currentPlayerIndex = decoded.currentPlayerIndex or 1
  S.selectedPawn = nil
  S.questionUI = nil
  S.feedbackUI = nil
  S.pendingAction = nil
  S.moveAnim = nil
  S.attackAnim = nil
  S.attackPending = nil
  S.deathAnim = nil
  S.deathPending = nil
  S.state.mode = "game"
  S.guardAnim = nil

  return true
end

local function isGameOver(S)
  local pawnCounts = {}
  local flagCounts = {}
  for idx = 1, #S.players do
    pawnCounts[idx] = 0
    flagCounts[idx] = 0
  end

  for _, pawn in ipairs(S.pawns) do
    local idx = nil
    for i, player in ipairs(S.players) do
      if pawn.player == player then
        idx = i
        break
      end
    end
    if idx then
      pawnCounts[idx] = pawnCounts[idx] + 1
      if pawn.isFlag then
        flagCounts[idx] = flagCounts[idx] + 1
      end
    end
  end

  for i = 1, #S.players do
    if pawnCounts[i] == 0 or flagCounts[i] == 0 then
      return true
    end
  end
  return false
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
    local cell = S.board[pos[1]][pos[2]]
    cell.isHole = true
    if S.rockSprites and #S.rockSprites > 0 then
      cell.rockIndex = love.math.random(1, #S.rockSprites)
    end
  end

  if S.treeSheet and S.treeColumns and #S.treeColumns > 0 then
    local treeChoices = {}
    for r = 1, boardSize do
      for c = 1, boardSize do
        local cell = S.board[r][c]
        if not cell.isHole and cell.pawn == nil then
          table.insert(treeChoices, {r, c})
        end
      end
    end

    local treeCount = math.min(#treeChoices, math.ceil(boardSize * boardSize * 0.2))
    for i = 1, treeCount do
      local idx = love.math.random(#treeChoices)
      local pos = table.remove(treeChoices, idx)
      local cell = S.board[pos[1]][pos[2]]
      cell.treeCol = S.treeColumns[love.math.random(1, #S.treeColumns)]
      if S.treeSheet and S.treeSheet.rows then
        cell.treeOffset = love.math.random(0, S.treeSheet.rows - 1)
      else
        cell.treeOffset = love.math.random(0, 12)
      end
    end
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

local function getActionDir(fromRow, fromCol, toRow, toCol)
  if toRow < fromRow then
    return "up"
  elseif toRow > fromRow then
    return "down"
  elseif toCol < fromCol then
    return "left"
  end
  return "right"
end

local function executeActionResult(S, pending)
  local current = S.players[S.currentPlayerIndex]
  local fromPawn = pending.fromPawn
  local targetCell = pending.targetCell
  local tr, tc = pending.toRow, pending.toCol

  if pending.victim then
    local victim = pending.victim
    S.board[victim.row][victim.col].pawn = nil
    for i = #S.pawns, 1, -1 do
      if S.pawns[i] == victim then table.remove(S.pawns, i) break end
    end
  end

  current.score = current.score + pending.scoreDelta

  S.resolvePending = pending

  if pending.moveAnim then
    S.moveAnim = pending.moveAnim
  else
    S.moveAnim = nil
    S.currentPlayerIndex = (S.currentPlayerIndex % #S.players) + 1
    saveGameState(S)
    S.resolvePending = nil
  end
  S.selectedPawn = nil
end

local function applyPendingAction(S, success)

  if not S.pendingAction then return end
  local act = S.pendingAction
  S.pendingAction = nil

  local current = S.players[S.currentPlayerIndex]

  if not success then
    startFeedback(S, false, function()
      S.selectedPawn = nil
      S.guardAnim = nil
      S.currentPlayerIndex = (S.currentPlayerIndex % #S.players) + 1
    end)
    return
  end

  local fromPawn = act.pawn
  local tr, tc = act.toR, act.toC
  local targetCell = S.board[tr][tc]
  local fromRow, fromCol = fromPawn.row, fromPawn.col


  local dir = getActionDir(fromRow, fromCol, tr, tc)

  local moveAnim = {
    pawn = fromPawn,
    fromRow = fromRow,
    fromCol = fromCol,
    toRow = tr,
    toCol = tc,
    dir = dir,
    t = 0,
    duration = 0.45,
  }

  local victim = nil
  if act.type == "attack" and targetCell.pawn and targetCell.pawn.player ~= fromPawn.player then
    victim = targetCell.pawn
  end

  local pending = {
    fromPawn = fromPawn,
    targetCell = targetCell,
    toRow = tr,
    toCol = tc,
    moveAnim = moveAnim,
    scoreDelta = (act.type == "attack") and 5 or 1,
    victim = victim,
  }

  startFeedback(S, true, function()
    S.guardAnim = nil
    if act.type == "attack" and victim then
      local duration = 0.6
      local fps = (S.pawnAnim and S.pawnAnim.fps or 8) * 0.5
      if fps > 0 then
        duration = 3 / fps
      end

      local attackDir = getActionDir(tr, tc, fromRow, fromCol)
      S.deathAnim = {
        pawn = victim,
        row = tr,
        col = tc,
        dir = attackDir,
        t = 0,
        duration = duration,
      }
      S.deathPending = pending
      return
    end

    executeActionResult(S, pending)
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

  local needed = 1
  local targetCell = S.board[toR] and S.board[toR][toC]
  local fromCell = S.board[pawn.row] and S.board[pawn.row][pawn.col]
  if actType == "attack" then
    if fromCell and fromCell.treeCol then
      needed = 1
    elseif targetCell and targetCell.treeCol then
      needed = 4
    else
      needed = 2
    end
  else
    if targetCell and targetCell.treeCol then
      needed = 2
    else
      needed = 1
    end
  end
  local onFinish = function(ok)
    applyPendingAction(S, ok)
  end

  if actType == "attack" then
    local cell = S.board[toR] and S.board[toR][toC]
    if cell and cell.pawn and cell.pawn.player ~= pawn.player then
      local guardDir = getActionDir(cell.pawn.row, cell.pawn.col, pawn.row, pawn.col)
      S.guardAnim = {
        pawn = cell.pawn,
        dir = guardDir,
      }
    end
    local dir = getActionDir(pawn.row, pawn.col, toR, toC)
    local choice = love.math.random(1, 3)
    local duration = 0.6
    local fps = (S.pawnAnim and S.pawnAnim.fps or 8) * 0.5
    if fps > 0 then
      duration = 4 / fps
    end

    S.attackAnim = {
      pawn = pawn,
      dir = dir,
      choice = choice,
      t = 0,
      duration = duration,
    }
    S.attackPending = {
      category = category,
      timeLimit = S.cfg.timeLimit,
      required = needed,
      onFinish = onFinish,
    }
    return
  end

  beginQuestion(S, category, S.cfg.timeLimit, needed, onFinish)

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
    S.attackAnim = nil
    S.attackPending = nil
    S.deathAnim = nil
    S.deathPending = nil
    S.sheathAnim = nil
    S.guardAnim = nil
    S.state.mode = "game"
    saveGameState(S)
  end

  local function loadGame()
    if loadSavedGame(S) then
      debugLog("Load debug: load succeeded")
      return
    end
    debugLog("Load debug: load failed")
  end


  local buttonFill = {220, 220, 220}
  local buttonHover = {255, 180, 120}

  S.menuButtons = {
    -- players
    Button.new(-170, -170, 60, 60, "-", buttonFill, buttonHover, function() clampPlayers(-1) end),
    Button.new( 170, -170, 60, 60, "+", buttonFill, buttonHover, function() clampPlayers( 1) end),

    -- time
    Button.new(-170,  -80, 60, 60, "-", buttonFill, buttonHover, function() clampTime(-5) end),
    Button.new( 170,  -80, 60, 60, "+", buttonFill, buttonHover, function() clampTime( 5) end),

    -- board size
    Button.new(-170,   10, 60, 60, "-", buttonFill, buttonHover, function() clampBoard(-1) end),
    Button.new( 170,   10, 60, 60, "+", buttonFill, buttonHover, function() clampBoard( 1) end),

    -- music volume
    Button.new(-170,  100, 60, 60, "-", buttonFill, buttonHover, function() clampVolume(-0.05) end),
    Button.new( 170,  100, 60, 60, "+", buttonFill, buttonHover, function() clampVolume( 0.05) end),

    -- play
    Button.new( -190,  260, 180, 60, "PLAY", {50,50,200}, {100,149,237}, startGame),
  }

  if hasSavedGame() then
    table.insert(S.menuButtons, Button.new( 10,  260, 180, 60, "LOAD GAME", {60,120,60}, {90,170,90}, loadGame))
  end

end

-- -----------------------------
-- Update + input
-- -----------------------------
function Game.update(S, dt)
  if S.moveAnim then
    S.moveAnim.t = S.moveAnim.t + dt
    if S.moveAnim.t >= S.moveAnim.duration then
      local dir = S.moveAnim.dir
      local pawn = S.moveAnim.pawn
      local pending = S.resolvePending
      S.moveAnim = nil

      if pending and pawn then
        S.board[pending.fromPawn.row][pending.fromPawn.col].pawn = nil
        pending.fromPawn.row, pending.fromPawn.col = pending.toRow, pending.toCol
        pending.targetCell.pawn = pending.fromPawn
      end

      if pawn then
        local fps = (S.pawnAnim and S.pawnAnim.fps or 8) * 0.5
        local duration = 0.3
        if fps > 0 then
          duration = 2 / fps
        end
        S.sheathAnim = {
          pawn = pawn,
          dir = dir,
          t = 0,
          duration = duration,
          mode = "draw",
        }
      end
    end
  end

  if S.attackAnim then
    S.attackAnim.t = S.attackAnim.t + dt
    if S.attackAnim.t >= S.attackAnim.duration then
      local pending = S.attackPending
      S.attackAnim = nil
      S.attackPending = nil
      if pending then
        beginQuestion(S, pending.category, pending.timeLimit, pending.required, pending.onFinish)
      end
    end
  end

  if S.deathAnim then
    S.deathAnim.t = S.deathAnim.t + dt
    if S.deathAnim.t >= S.deathAnim.duration then
      local pending = S.deathPending
      S.deathAnim = nil
      S.deathPending = nil
      if pending then
        executeActionResult(S, pending)
      end
    end
  end

  if S.sheathAnim then
    S.sheathAnim.t = S.sheathAnim.t + dt
    if S.sheathAnim.t >= S.sheathAnim.duration then
      local mode = S.sheathAnim.mode
      local pending = S.resolvePending
      S.sheathAnim = nil
      if mode == "draw" and pending then
        if isGameOver(S) then
          clearSavedGame()
          S.moveAnim = nil
          S.selectedPawn = nil
          S.questionUI = nil
          S.feedbackUI = nil
          S.pendingAction = nil
          S.attackAnim = nil
          S.attackPending = nil
          S.deathAnim = nil
          S.deathPending = nil
          S.sheathAnim = nil
          S.guardAnim = nil
          S.moveAnim = nil
          S.resolvePending = nil
          S.state.mode = "menu"
          Game.buildMenuButtons(S)
          return
        end

        S.selectedPawn = nil
        S.currentPlayerIndex = (S.currentPlayerIndex % #S.players) + 1
        saveGameState(S)
        S.resolvePending = nil
      end
    end
  end

  if S.attackAnim or S.deathAnim or S.sheathAnim then
    return
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
  if S.feedbackUI or S.attackAnim or S.deathAnim or S.sheathAnim then return end


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
      Game.buildMenuButtons(S)
      return
    end

  end
end

-- Expose for Draw module: valid moves
function Game.getValidMoves(S, pawn, boardSize)
  return getValidMoves(S, pawn, boardSize)
end

return Game
