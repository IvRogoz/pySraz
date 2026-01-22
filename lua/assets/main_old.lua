-- main.lua (LÖVE 11.x)
-- Folder layout:
--   /main.lua
--   /sprites/frame_000.png, frame_001.png, ... (each file = 1 animation frame, contains 4 directions inside)

-- =========================
-- CONFIG YOU EDIT
-- =========================
local SPRITE_DIR = "sprites"

-- Custom crop rectangles INSIDE each PNG for each direction.
-- Edit these numbers to match your nonstandard sheets.
-- Coordinates are in pixels in the source PNG.
local crop = {
  up    = { x = 0,   y = 0,   w = 32, h = 32 },
  down  = { x = 32,  y = 0,   w = 32, h = 32 },
  left  = { x = 64,  y = 0,   w = 32, h = 32 },
  right = { x = 96,  y = 0,   w = 32, h = 32 },
}

local anchors = {}



-- Animation speed (frames per second)
local FPS = 10

-- Render scale (how big the sprite appears)
local DRAW_SCALE = 4

-- If your pixel art should be crisp
local USE_NEAREST = true

-- =========================
-- INTERNALS
-- =========================
local frames = {}          -- { {img=Image, quads={up=Quad,down=Quad,left=Quad,right=Quad}, name=string}, ... }
local dirs = { "down", "left", "right", "up" }
local dirKey = { up="up", down="down", left="left", right="right", w="up", s="down", a="left", d="right" }

local currentDir = "down"
local animIndex = 1
local animTimer = 0
local moving = false

-- Debug crop editor
local showDebug = true
local selectedDir = "down"   -- which direction's crop we are editing
local lastSaveMessage = "Not saved yet"
local wasSaveKeyDown = false
local dirSelectKeys = {
  ["1"] = "down",
  ["2"] = "left",
  ["3"] = "right",
  ["4"] = "up",
  ["kp1"] = "down",
  ["kp2"] = "left",
  ["kp3"] = "right",
  ["kp4"] = "up",
}


-- -------------------------
-- Helpers
-- -------------------------
local function endswith(s, suffix)
  return s:sub(-#suffix):lower() == suffix:lower()
end

local function extractNumber(s)
  -- returns first number found, or nil
  local n = s:match("(%d+)")
  return n and tonumber(n) or nil
end

local function naturalSort(a, b)
  -- Sort by first number if present, else lexicographic
  local na = extractNumber(a)
  local nb = extractNumber(b)
  if na and nb and na ~= nb then return na < nb end
  return a:lower() < b:lower()
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function rebuildQuads()
  for _, f in ipairs(frames) do
    local iw, ih = f.img:getDimensions()
    f.quads = {}
    for _, d in ipairs(dirs) do
      local r = crop[d]
      -- clamp in case user edits beyond bounds
      local x = clamp(r.x, 0, iw - 1)
      local y = clamp(r.y, 0, ih - 1)
      local w = clamp(r.w, 1, iw - x)
      local h = clamp(r.h, 1, ih - y)
      f.quads[d] = love.graphics.newQuad(x, y, w, h, iw, ih)
    end
  end
end

local function ensureAnchorForDir(dir)
  local r = crop[dir]
  if not r then
    return { x = 0, y = 0 }
  end

  anchors[dir] = anchors[dir] or { x = r.w * 0.5, y = r.h * 0.5 }
  anchors[dir].x = clamp(tonumber(anchors[dir].x) or r.w * 0.5, 0, r.w)
  anchors[dir].y = clamp(tonumber(anchors[dir].y) or r.h * 0.5, 0, r.h)
  return anchors[dir]
end

local function serializeLuaTable(t, indent)

  indent = indent or 0
  local pad = string.rep("  ", indent)
  local out = "{\n"
  for k, v in pairs(t) do
    local key
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then
      key = k
    else
      key = "[" .. tostring(k) .. "]"
    end

    if type(v) == "table" then
      out = out .. pad .. "  " .. key .. " = " .. serializeLuaTable(v, indent + 1) .. ",\n"
    elseif type(v) == "string" then
      out = out .. pad .. "  " .. key .. " = " .. string.format("%q", v) .. ",\n"
    else
      out = out .. pad .. "  " .. key .. " = " .. tostring(v) .. ",\n"
    end
  end
  out = out .. pad .. "}"
  return out
end

local function getSourceConfigPath()
  local base = love.filesystem.getSourceBaseDirectory()
  if not base or base == "" then
    return nil
  end
  return base .. "/crop_config.lua"
end

local function applyLoadedCropConfig(loaded)
  if type(loaded) ~= "table" then
    return false
  end

  local loadedCrop = loaded.crop or loaded
  local loadedAnchors = loaded.anchor

  for _, d in ipairs(dirs) do
    if loadedCrop[d] then
      crop[d] = crop[d] or { x=0,y=0,w=16,h=16 }
      crop[d].x = tonumber(loadedCrop[d].x) or crop[d].x
      crop[d].y = tonumber(loadedCrop[d].y) or crop[d].y
      crop[d].w = tonumber(loadedCrop[d].w) or crop[d].w
      crop[d].h = tonumber(loadedCrop[d].h) or crop[d].h
    end

    if loadedAnchors and loadedAnchors[d] then
      anchors[d] = anchors[d] or { x = 0, y = 0 }
      anchors[d].x = tonumber(loadedAnchors[d].x) or anchors[d].x
      anchors[d].y = tonumber(loadedAnchors[d].y) or anchors[d].y
    end
  end

  return true
end

local function loadLuaChunk(content)
  local loader = loadstring or load
  return loader(content)
end

local function saveCropConfig()
  local payload = {
    crop = crop,
    anchor = anchors,
  }
  local content = "return " .. serializeLuaTable(payload) .. "\n"
  local sourcePath = getSourceConfigPath()

  if sourcePath then
    local file, err = io.open(sourcePath, "w")
    if file then
      file:write(content)
      file:close()
      lastSaveMessage = "Saved crop_config.lua to " .. sourcePath
      print(lastSaveMessage)
      return
    end

    lastSaveMessage = "Source save failed: " .. tostring(err)
    print(lastSaveMessage)
  end

  local ok, err = love.filesystem.write("crop_config.lua", content)
  if ok then
    lastSaveMessage = "Saved crop_config.lua to save dir"
    print(lastSaveMessage)
  else
    lastSaveMessage = "Save failed: " .. tostring(err)
    print(lastSaveMessage)
  end
end



local function tryLoadSavedCropConfig()
  local sourcePath = getSourceConfigPath()
  if sourcePath then
    local file = io.open(sourcePath, "r")
    if file then
      local content = file:read("*a")
      file:close()
      local chunk = loadLuaChunk(content)
      if chunk then
        local ok, loaded = pcall(chunk)
        if ok and applyLoadedCropConfig(loaded) then
          return
        end
      end
    end
  end

  if love.filesystem.getInfo("crop_config.lua") then
    local chunk = love.filesystem.load("crop_config.lua")
    if chunk then
      local ok, loaded = pcall(chunk)
      if ok then
        applyLoadedCropConfig(loaded)
      end
    end
  end
end


local function isMoveKeyDown()
  return love.keyboard.isDown("up","down","left","right","w","a","s","d")
end

-- =========================
-- LÖVE callbacks
-- =========================
function love.load()
  love.window.setTitle("Sprite Sheet Direction Animator (per-file frames)")

  love.filesystem.setIdentity("sprite_sheet_direction_animator")

  if USE_NEAREST then
    love.graphics.setDefaultFilter("nearest", "nearest", 1)
  end

  tryLoadSavedCropConfig()

  for _, d in ipairs(dirs) do
    ensureAnchorForDir(d)
  end

  -- List PNGs from SPRITE_DIR (must be inside your project folder)

  local items = love.filesystem.getDirectoryItems(SPRITE_DIR)
  local pngs = {}
  for _, name in ipairs(items) do
    if endswith(name, ".png") then
      table.insert(pngs, name)
    end
  end
  table.sort(pngs, naturalSort)

  assert(#pngs > 0, "No .png files found in '" .. SPRITE_DIR .. "'. Put your frames there.")

  -- Load frames
  for _, filename in ipairs(pngs) do
    local path = SPRITE_DIR .. "/" .. filename
    local img = love.graphics.newImage(path)
    local f = { img = img, name = filename, quads = {} }
    table.insert(frames, f)
  end

  rebuildQuads()

  animIndex = 1
  currentDir = "down"
end

function love.update(dt)
  moving = isMoveKeyDown()

  -- Update direction based on held keys (priority order)
  -- You can change priority if you want diagonals handled differently.
  if love.keyboard.isDown("up") then
    currentDir = "down"
  elseif love.keyboard.isDown("w") then
    currentDir = "up"
  elseif love.keyboard.isDown("down") then
    currentDir = "up"
  elseif love.keyboard.isDown("s") then
    currentDir = "down"
  elseif love.keyboard.isDown("left") or love.keyboard.isDown("a") then
    currentDir = "left"
  elseif love.keyboard.isDown("right") or love.keyboard.isDown("d") then
    currentDir = "right"
  end


  if moving then
    animTimer = animTimer + dt
    local spf = 1 / FPS
    while animTimer >= spf do
      animTimer = animTimer - spf
      animIndex = animIndex + 1
      if animIndex > #frames then animIndex = 1 end
    end
  else
    -- idle frame (use first frame)
    animIndex = 1
    animTimer = 0
  end
end

function love.keypressed(key, scancode)
  -- Toggle debug overlay/editor
  if key == "tab" then
    showDebug = not showDebug
  end

  -- Select which direction crop to edit
  local dir = dirSelectKeys[key] or dirSelectKeys[scancode]
  if dir then
    selectedDir = dir
  end

  -- Save crop config (writes crop_config.lua to save directory)
  if key == "s" or scancode == "s" then
    saveCropConfig()
  end


  -- Hot reload quads (after manual table edits)
  if key == "r" then
    rebuildQuads()
  end
end

function love.draw()
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  love.graphics.clear(0.08, 0.08, 0.10, 1)

  local f = frames[animIndex]
  local q = f.quads[currentDir]

  -- Draw centered
  local anchor = ensureAnchorForDir(currentDir)
  local drawX = math.floor(w * 0.5)
  local drawY = math.floor(h * 0.75)

  love.graphics.draw(
    f.img, q,
    drawX, drawY,
    0,
    DRAW_SCALE, DRAW_SCALE,
    anchor.x, anchor.y
  )


  -- Debug overlay
  if showDebug then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Dir: " .. currentDir .. " | Frame: " .. animIndex .. "/" .. #frames .. " (" .. f.name .. ")", 10, 10)
    love.graphics.print("Hold WASD/Arrows to animate. TAB toggles debug.", 10, 30)

    love.graphics.print("Crop editor:", 10, 60)
    love.graphics.print("Select dir: 1=down 2=left 3=right 4=up  | Selected: " .. selectedDir, 10, 80)
    love.graphics.print("Edit: I/K/J/L move  | Shift+I/K changes H  | Shift+J/L changes W", 10, 100)
    love.graphics.print("Ctrl = step x10  | S save crop_config.lua  | R rebuild quads", 10, 120)
    love.graphics.print("Click preview to set anchor", 10, 140)

    local sr = crop[selectedDir]
    local sa = ensureAnchorForDir(selectedDir)
    love.graphics.print(
      string.format("Selected crop [%s] x=%d y=%d w=%d h=%d", selectedDir, sr.x, sr.y, sr.w, sr.h),
      10, 170
    )
    love.graphics.print(
      string.format("Anchor [%s] x=%d y=%d", selectedDir, math.floor(sa.x), math.floor(sa.y)),
      10, 190
    )
    love.graphics.print("Save: " .. lastSaveMessage, 10, 210)



    -- Draw the source sheet preview (top-right) with crop rect overlays
    local previewScale = 2
    local px = w - (f.img:getWidth() * previewScale) - 20
    local py = 20
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(f.img, px, py, 0, previewScale, previewScale)

    -- Rectangles for all directions
    for _, d in ipairs(dirs) do
      local rr = crop[d]
      if d == selectedDir then
        love.graphics.setColor(1, 0.2, 0.2, 1)
      else
        love.graphics.setColor(0.2, 1, 0.2, 0.9)
      end
      love.graphics.rectangle("line", px + rr.x * previewScale, py + rr.y * previewScale, rr.w * previewScale, rr.h * previewScale)
      love.graphics.print(d, px + rr.x * previewScale, py + (rr.y * previewScale) - 14)
    end

    local selectedAnchor = ensureAnchorForDir(selectedDir)
    local selectedCrop = crop[selectedDir]
    love.graphics.setColor(1, 0.8, 0.2, 1)
    love.graphics.circle(
      "fill",
      px + (selectedCrop.x + selectedAnchor.x) * previewScale,
      py + (selectedCrop.y + selectedAnchor.y) * previewScale,
      3
    )

    love.graphics.setColor(1, 1, 1, 1)

  end
end

-- =========================
-- Crop editor controls (continuous)
-- =========================
function love.keyreleased(_) end

function love.focus(_) end

function love.mousepressed(x, y, button)
  if not showDebug or button ~= 1 then
    return
  end

  local f = frames[animIndex]
  if not f then
    return
  end

  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  local previewScale = 2
  local px = w - (f.img:getWidth() * previewScale) - 20
  local py = 20
  local maxX = px + (f.img:getWidth() * previewScale)
  local maxY = py + (f.img:getHeight() * previewScale)

  if x < px or x > maxX or y < py or y > maxY then
    return
  end

  local srcX = (x - px) / previewScale
  local srcY = (y - py) / previewScale
  local r = crop[selectedDir]
  local a = ensureAnchorForDir(selectedDir)

  a.x = clamp(srcX - r.x, 0, r.w)
  a.y = clamp(srcY - r.y, 0, r.h)
end


function love.wheelmoved(_, _) end

-- Continuous editing in love.update via keyboard state:
local function editCrop(dt)
  if not showDebug then return end

  local step = 1
  if love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then
    step = 10
  end

  local sr = crop[selectedDir]
  local shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")

  -- I/K/J/L
  if love.keyboard.isDown("i") then
    if shift then sr.h = sr.h - step else sr.y = sr.y - step end
  end
  if love.keyboard.isDown("k") then
    if shift then sr.h = sr.h + step else sr.y = sr.y + step end
  end
  if love.keyboard.isDown("j") then
    if shift then sr.w = sr.w - step else sr.x = sr.x - step end
  end
  if love.keyboard.isDown("l") then
    if shift then sr.w = sr.w + step else sr.x = sr.x + step end
  end

  sr.w = math.max(1, sr.w)
  sr.h = math.max(1, sr.h)

  ensureAnchorForDir(selectedDir)

  -- Rebuild quads live if editing keys are used
  if love.keyboard.isDown("i") or love.keyboard.isDown("k") or love.keyboard.isDown("j") or love.keyboard.isDown("l") then
    rebuildQuads()
  end
end

local function handleSaveHotkey()
  local isDown = love.keyboard.isDown("s")
  if isDown and not wasSaveKeyDown then
    saveCropConfig()
  end
  wasSaveKeyDown = isDown
end

-- Hook crop editor into update
local _oldUpdate = love.update
function love.update(dt)
  _oldUpdate(dt)
  editCrop(dt)
  handleSaveHotkey()
end

