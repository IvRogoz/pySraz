-- src/config.lua
local Config = {}

Config.DEFAULT_W, Config.DEFAULT_H = 900, 700
Config.FPS = 60

Config.HOLE_COUNT = 6

Config.PAWN_CANVAS_SIZE = 40

Config.CATEGORY_COLORS = {
  Sport   = {0, 200, 0},
  History = {139, 69, 19},
  Music   = {128, 0, 128},
  Science = {0, 255, 255},
  Art     = {255, 192, 203},
  Random  = {128, 128, 128},
}

Config.PLAYER_COLORS = {
  {220, 20, 60},
  {30, 144, 255},
  {34, 139, 34},
  {255, 215, 0},
}

return Config
