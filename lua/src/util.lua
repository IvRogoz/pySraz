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

local function encodeJsonString(value)
  local escaped = value:gsub("\\", "\\\\")
    :gsub("\"", "\\\"")
    :gsub("\n", "\\n")
    :gsub("\r", "\\r")
    :gsub("\t", "\\t")
  return "\"" .. escaped .. "\""
end

local function isArrayTable(value)
  local count = 0
  for k, _ in pairs(value) do
    if type(k) ~= "number" then
      return false
    end
    if k > count then
      count = k
    end
  end
  return count == #value
end

local function encodeJsonValue(value)
  local valueType = type(value)
  if valueType == "string" then
    return encodeJsonString(value)
  elseif valueType == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      return "null"
    end
    return tostring(value)
  elseif valueType == "boolean" then
    return value and "true" or "false"
  elseif valueType == "table" then
    if isArrayTable(value) then
      local items = {}
      for i = 1, #value do
        items[i] = encodeJsonValue(value[i])
      end
      return "[" .. table.concat(items, ",") .. "]"
    end

    local items = {}
    for k, v in pairs(value) do
      if type(k) ~= "string" then
        k = tostring(k)
      end
      table.insert(items, encodeJsonString(k) .. ":" .. encodeJsonValue(v))
    end
    return "{" .. table.concat(items, ",") .. "}"
  end

  return "null"
end

local function decodeJsonValue(input)
  local pos = 1

  local function skipWhitespace()
    while true do
      local ch = input:sub(pos, pos)
      if ch == "" then return end
      if ch ~= " " and ch ~= "\n" and ch ~= "\r" and ch ~= "\t" then
        return
      end
      pos = pos + 1
    end
  end

  local function parseString()
    pos = pos + 1
    local out = {}
    while true do
      local ch = input:sub(pos, pos)
      if ch == "" then
        return nil
      end
      if ch == "\"" then
        pos = pos + 1
        return table.concat(out)
      end
      if ch == "\\" then
        local nextChar = input:sub(pos + 1, pos + 1)
        if nextChar == "n" then
          table.insert(out, "\n")
        elseif nextChar == "r" then
          table.insert(out, "\r")
        elseif nextChar == "t" then
          table.insert(out, "\t")
        elseif nextChar == "\"" then
          table.insert(out, "\"")
        elseif nextChar == "\\" then
          table.insert(out, "\\")
        else
          table.insert(out, nextChar)
        end
        pos = pos + 2
      else
        table.insert(out, ch)
        pos = pos + 1
      end
    end
  end

  local function parseNumber()
    local startPos = pos
    local ch = input:sub(pos, pos)
    if ch == "-" then
      pos = pos + 1
    end
    while input:sub(pos, pos):match("%d") do
      pos = pos + 1
    end
    if input:sub(pos, pos) == "." then
      pos = pos + 1
      while input:sub(pos, pos):match("%d") do
        pos = pos + 1
      end
    end
    local substr = input:sub(startPos, pos - 1)
    return tonumber(substr)
  end

  local function parseValue()
    skipWhitespace()
    local ch = input:sub(pos, pos)
    if ch == "" then
      return nil
    elseif ch == "\"" then
      return parseString()
    elseif ch == "{" then
      pos = pos + 1
      local obj = {}
      skipWhitespace()
      if input:sub(pos, pos) == "}" then
        pos = pos + 1
        return obj
      end
      while true do
        skipWhitespace()
        local key = parseString()
        skipWhitespace()
        if input:sub(pos, pos) ~= ":" then
          return nil
        end
        pos = pos + 1
        local value = parseValue()
        obj[key] = value
        skipWhitespace()
        local delim = input:sub(pos, pos)
        if delim == "}" then
          pos = pos + 1
          break
        elseif delim == "," then
          pos = pos + 1
        else
          return nil
        end
      end
      return obj
    elseif ch == "[" then
      pos = pos + 1
      local arr = {}
      skipWhitespace()
      if input:sub(pos, pos) == "]" then
        pos = pos + 1
        return arr
      end
      local i = 1
      while true do
        local value = parseValue()
        arr[i] = value
        i = i + 1
        skipWhitespace()
        local delim = input:sub(pos, pos)
        if delim == "]" then
          pos = pos + 1
          break
        elseif delim == "," then
          pos = pos + 1
        else
          return nil
        end
      end
      return arr
    elseif ch == "t" and input:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true
    elseif ch == "f" and input:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return false
    elseif ch == "n" and input:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return nil
    else
      return parseNumber()
    end
  end

  return parseValue()
end

function U.encodeJson(value)
  if love.data and love.data.encode then
    local ok, encoded = pcall(love.data.encode, "string", "json", value)
    if ok and encoded then
      return encoded
    end
  end
  return encodeJsonValue(value)
end

function U.decodeJson(value)
  if love.data and love.data.decode then
    local ok, decoded = pcall(love.data.decode, "string", "json", value)
    if ok and decoded then
      return decoded
    end
  end

  local decoded = decodeJsonValue(value or "")
  return decoded
end

return U

