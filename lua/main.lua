-- main.lua
local Config    = require("src.config")
local AudioFFT  = require("src.audio_fft")
local ShaderSrc = require("src.shader_galaxy")
local Assets    = require("src.assets")
local Questions = require("src.questions")
local Game      = require("src.game")
local Draw      = require("src.draw")

local S = {
  state = { mode = "splash" }, -- splash | menu | game
  cfg = {
    numPlayers   = 2,
    timeLimit    = 30,
    boardSize    = 8,
    musicVolume  = 0.5, -- default 50%
  },

  fonts = {},
  bgShader = nil,
  audioFFT = nil,

  -- runtime/game state
  questionsByCategory = {},
  players = {},
  pawns = {},
  board = {},

  currentPlayerIndex = 1,
  selectedPawn = nil,

  questionUI = nil,
  feedbackUI = nil,
  pendingAction = nil,
  moveAnim = nil,
  attackAnim = nil,
  attackPending = nil,
  deathAnim = nil,
  deathPending = nil,
  sheathAnim = nil,
  guardAnim = nil,


  menuButtons = nil,

  -- cached assets
  pawnBaseImg = nil,
  flagBaseImg = nil,

  pawnAnim = nil,
  flagSheet = nil,
  tileSheet = nil,
  rockSprites = nil,


  -- optional low-res background render target (used by your shader background, if draw.lua uses it)
  bgScaleW = 320,
  bgScaleH = 240,
  bgCanvas = nil,

  -- splash video
  splashVideo = nil,
  splashVideoError = nil,
}

local function tryLoadSplashVideo()
  -- LÖVE plays Ogg Theora via newVideo (no MKV). Convert main.mkv -> renders/splash.ogv
  local path = "renders/splash.ogv"
  if not love.filesystem.getInfo(path) then
    S.splashVideo = nil
    S.splashVideoError = "Missing renders/splash.ogv (convert from MKV)"
    return
  end

  local ok, vidOrErr = pcall(function()
    return love.graphics.newVideo(path)
  end)

  if ok and vidOrErr then
    S.splashVideo = vidOrErr
    S.splashVideoError = nil
    if S.splashVideo.play then
      S.splashVideo:play()
    end
  else
    S.splashVideo = nil
    S.splashVideoError = tostring(vidOrErr)
  end
end

function love.load()
  love.window.setMode(Config.DEFAULT_W, Config.DEFAULT_H, { resizable = true, vsync = 0 })
  love.graphics.setBackgroundColor(0, 0, 0, 1)
  love.math.setRandomSeed(os.time())

  -- Fonts
  S.fonts.title  = love.graphics.newFont(48)
  S.fonts.medium = love.graphics.newFont(24)
  S.fonts.small  = love.graphics.newFont(20)
  S.fonts.big    = love.graphics.newFont(200)
  S.fonts.name   = love.graphics.newFont(30)

  -- Questions (KEEP your original working loader name)
  S.questionsByCategory = Questions.loadQuestionsCSV("questions.csv")

  -- Base pawn/flag images (fallback / menu previews)
  S.pawnBaseImg = Assets.tryLoadImage("pawn.png")
  S.flagBaseImg = Assets.tryLoadImage("flag.png")
  if not S.pawnBaseImg then print("Warning: pawn.png missing -> using fallback") end
  if not S.flagBaseImg then print("Warning: flag.png missing -> using fallback") end

  -- Optional sprite sheets
  S.pawnAnim = Assets.loadPawnAnimations()
  S.flagSheet = Assets.loadSpriteSheet("flag_spritesheet.png", 60, 60, 5) -- 5 frames
  S.tileSheet = Assets.loadSpriteSheet("assets/tiles.png", 96, 96, 2, 1)
  S.rockSprites = {
    Assets.tryLoadImage("assets/Rock1_1.png"),
    Assets.tryLoadImage("assets/Rock5_1.png"),
    Assets.tryLoadImage("assets/Rock6_1.png"),
  }


  -- Audio FFT + music volume
  S.audioFFT = AudioFFT.new("shadertoy.mp3")
  if S.audioFFT and S.audioFFT.setVolume then
    S.audioFFT:setVolume(S.cfg.musicVolume)
  end

  -- Background shader
  S.bgShader = love.graphics.newShader(ShaderSrc.GALAXY_SHADER)

  -- Low-res canvas (if you want retro shader render path)
  S.bgCanvas = love.graphics.newCanvas(S.bgScaleW, S.bgScaleH)
  S.bgCanvas:setFilter("nearest", "nearest")

  -- Build menu buttons
  Game.buildMenuButtons(S)

  -- Splash video
  tryLoadSplashVideo()
end

function love.update(dt)
  if S.audioFFT and S.audioFFT.update then
    S.audioFFT:update(dt)
  end

  -- Manual loop for splash video (since :setLooping isn't available on your LÖVE)
  if S.state.mode == "splash" and S.splashVideo and S.splashVideo.isPlaying then
    if not S.splashVideo:isPlaying() then
      if S.splashVideo.rewind then S.splashVideo:rewind() end
      if S.splashVideo.play then S.splashVideo:play() end
    end
  end

  Game.update(S, dt)
end

function love.draw()
  Draw.background(S)
  Draw.scene(S)
  Draw.overlays(S)
end

function love.mousepressed(x, y, button)
  -- click on splash => go to menu (and pause video)
  if S.state.mode == "splash" and button == 1 then
    if S.splashVideo and S.splashVideo.pause then S.splashVideo:pause() end
    S.state.mode = "menu"
    return
  end
  Game.mousepressed(S, x, y, button)
end

function love.keypressed(key)
  Game.keypressed(S, key)
end
