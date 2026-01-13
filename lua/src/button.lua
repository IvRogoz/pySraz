-- src/button.lua
local U = require("src.util")

local Button = {}
Button.__index = Button

function Button.new(relx, rely, w, h, text, color, hoverColor, action)
  local self = setmetatable({}, Button)
  self.relx, self.rely = relx, rely
  self.w, self.h = w, h
  self.text = text
  self.color = color
  self.hoverColor = hoverColor
  self.action = action
  self.x, self.y = 0, 0
  self.hovered = false
  return self
end

function Button:updatePos(cx, cy)
  self.x = cx + self.relx - self.w / 2
  self.y = cy + self.rely - self.h / 2
end

function Button:updateHover(mx, my)
  self.hovered = U.pointInRect(mx, my, self.x, self.y, self.w, self.h)
end

function Button:mousepressed(mx, my, button)
  if button == 1 and self.hovered and self.action then
    self.action()
    return true
  end
  return false
end

function Button:draw(font, glitchx, glitchy)
  local gx, gy = glitchx or 0, glitchy or 0
  local x, y = self.x + gx, self.y + gy

  U.setColor255(245, 235, 220, 255)
  love.graphics.rectangle("fill", x, y, self.w, self.h, 8, 8)

  local c = self.hovered and self.hoverColor or self.color
  U.setColor255(c[1], c[2], c[3], 255)
  love.graphics.rectangle("fill", x + 3, y + 3, self.w - 6, self.h - 6, 6, 6)

  U.setColor255(20, 20, 20, 255)
  love.graphics.rectangle("line", x, y, self.w, self.h, 8, 8)

  love.graphics.setFont(font)
  U.setColor255(20, 20, 20, 255)
  local ty = y + self.h / 2 - font:getHeight() / 2
  love.graphics.printf(self.text, x, ty, self.w, "center")
end

return Button
