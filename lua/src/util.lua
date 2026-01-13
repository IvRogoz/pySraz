-- src/util.lua
local U = {}

function U.clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

function U.rgb255(r, g, b, a)
  return (r or 0) / 255, (g or 0) / 255, (b or 0) / 255, (a == nil and 1 or (a / 255))
end

function U.setColor255(r, g, b, a)
  love.graphics.setColor(U.rgb255(r, g, b, a))
end

function U.pointInRect(px, py, x, y, w, h)
  return px >= x and px <= x + w and py >= y and py <= y + h
end

function U.shuffle(t)
  for i = #t, 2, -1 do
    local j = love.math.random(i)
    t[i], t[j] = t[j], t[i]
  end
end

-- Minimal CSV splitter (handles simple quoted fields)
function U.csvSplitLine(line)
  local out = {}
  local i = 1
  local len = #line
  while i <= len do
    local c = line:sub(i, i)
    if c == '"' then
      local j = i + 1
      local buf = {}
      while j <= len do
        local cj = line:sub(j, j)
        if cj == '"' then
          if line:sub(j + 1, j + 1) == '"' then
            table.insert(buf, '"')
            j = j + 2
          else
            j = j + 1
            break
          end
        else
          table.insert(buf, cj)
          j = j + 1
        end
      end
      table.insert(out, table.concat(buf))
      if line:sub(j, j) == "," then j = j + 1 end
      i = j
    else
      local j = i
      while j <= len and line:sub(j, j) ~= "," do j = j + 1 end
      table.insert(out, (line:sub(i, j - 1)):match("^%s*(.-)%s*$"))
      i = j + 1
    end
  end
  return out
end

function U.isPixelFormatSupported(fmt)
  local ok = pcall(function()
    love.image.newImageData(2, 2, fmt)
  end)
  return ok
end

return U
