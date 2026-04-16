local U = require("src.util")

local Localization = {}

local function trim(value)
  return (value or ""):match("^%s*(.-)%s*$")
end

local function readLines(filename, addLine)
  if love.filesystem.getInfo(filename) then
    for line in love.filesystem.lines(filename) do
      addLine(line)
    end
    return true
  end

  local file = io.open(filename, "r")
  if file then
    for line in file:lines() do
      addLine(line)
    end
    file:close()
    return true
  end

  local base = love.filesystem.getSourceBaseDirectory and love.filesystem.getSourceBaseDirectory() or nil
  if base and base ~= "" then
    local path = base .. "/" .. filename
    file = io.open(path, "r")
    if file then
      for line in file:lines() do
        addLine(line)
      end
      file:close()
      return true
    end
  end

  return false
end

function Localization.loadCSV(filename)
  local data = {
    defaultLanguage = "en",
    languages = {},
    languageSet = {},
    values = {},
  }

  local headers = nil

  local function addLine(line)
    if not line or line == "" then
      return
    end

    local row = U.csvSplitLine(line)
    if not headers then
      headers = row
      for i = 2, #headers do
        local code = trim(headers[i]):lower()
        if code ~= "" and not data.languageSet[code] then
          table.insert(data.languages, code)
          data.languageSet[code] = true
        end
      end
      if data.languageSet.en then
        data.defaultLanguage = "en"
      elseif #data.languages > 0 then
        data.defaultLanguage = data.languages[1]
      end
      return
    end

    local key = trim(row[1])
    if key == "" or key:sub(1, 1) == "#" then
      return
    end

    data.values[key] = data.values[key] or {}
    for i = 2, #headers do
      local code = trim(headers[i]):lower()
      if code ~= "" then
        data.values[key][code] = row[i] or ""
      end
    end
  end

  if not readLines(filename, addLine) then
    print("Warning: missing " .. filename)
  end

  return data
end

function Localization.setLanguage(S, code)
  local i18n = S.i18n
  if not i18n then
    S.language = "en"
    S.cfg.language = "en"
    return S.language
  end

  code = trim(code):lower()
  if code == "" or not i18n.languageSet[code] then
    code = i18n.defaultLanguage
  end

  S.language = code
  S.cfg.language = code
  return code
end

function Localization.getLanguageCodes(S)
  local i18n = S.i18n
  if not i18n then
    return {"en"}
  end
  return i18n.languages
end

function Localization.getLanguageName(S, code)
  local i18n = S.i18n
  if not i18n then
    return string.upper(code or "en")
  end

  local names = i18n.values.language_name or {}
  return names[code] or string.upper(code or i18n.defaultLanguage)
end

function Localization.t(S, key, vars)
  local i18n = S.i18n
  if not i18n then
    return key
  end

  local lang = S.language or S.cfg.language or i18n.defaultLanguage
  local row = i18n.values[key]
  local text = row and (row[lang] or row[i18n.defaultLanguage]) or nil
  if not text or text == "" then
    text = key
  end

  if vars then
    for name, value in pairs(vars) do
      text = text:gsub("{" .. name .. "}", tostring(value))
    end
  end

  return text
end

return Localization
