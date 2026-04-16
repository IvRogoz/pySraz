-- src/questions.lua
local U = require("src.util")

local Q = {}

function Q.loadQuestionsCSV(filename)
  local questionData = {
    defaultLanguage = "en",
    languages = {},
    languageSet = {},
    byLanguage = {},
  }

  local function ensureLanguage(lang)
    if not questionData.languageSet[lang] then
      questionData.languageSet[lang] = true
      table.insert(questionData.languages, lang)
      questionData.byLanguage[lang] = {}
    end
    return questionData.byLanguage[lang]
  end

  local function addLine(line)
    if line and #line > 0 then
      local row = U.csvSplitLine(line)
      if #row >= 6 then
        local lang, cat, q, correct, w1, w2, w3
        if #row >= 7 then
          lang, cat, q, correct, w1, w2, w3 = row[1], row[2], row[3], row[4], row[5], row[6], row[7]
        else
          lang, cat, q, correct, w1, w2, w3 = questionData.defaultLanguage, row[1], row[2], row[3], row[4], row[5], row[6]
        end

        lang = ((lang or ""):match("^%s*(.-)%s*$")):lower()
        cat = (cat or ""):match("^%s*(.-)%s*$")

        if lang ~= "" and cat ~= "" then
          local questionsByCategory = ensureLanguage(lang)
          questionsByCategory[cat] = questionsByCategory[cat] or {}
          table.insert(questionsByCategory[cat], {
            question = q,
            correct = correct,
            wrong = {w1, w2, w3},
          })
        end
      end
    end
  end

  ensureLanguage(questionData.defaultLanguage)

  if love.filesystem.getInfo(filename) then
    for line in love.filesystem.lines(filename) do
      addLine(line)
    end
    return questionData
  end

  local file = io.open(filename, "r")
  if file then
    for line in file:lines() do
      addLine(line)
    end
    file:close()
    return questionData
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
      return questionData
    end
  end

  print("Warning: missing " .. filename)

  return questionData
end

local function getQuestionsForLanguage(questionData, language)
  local lang = (language or questionData.defaultLanguage or "en"):lower()
  return questionData.byLanguage[lang] or questionData.byLanguage[questionData.defaultLanguage] or {}
end

function Q.getRandomQuestionAny(questionData, language)
  local questionsByCategory = getQuestionsForLanguage(questionData, language)
  local cats = {}
  for k, v in pairs(questionsByCategory) do
    if v and #v > 0 then table.insert(cats, k) end
  end
  if #cats == 0 then
    return nil
  end

  local cat = cats[love.math.random(#cats)]
  local list = questionsByCategory[cat]
  return list[love.math.random(#list)], cat
end

function Q.getRandomQuestionFrom(questionData, category, language)
  local questionsByCategory = getQuestionsForLanguage(questionData, language)
  local list = questionsByCategory[category]
  if list and #list > 0 then
    return list[love.math.random(#list)], category
  end
  return Q.getRandomQuestionAny(questionData, language)
end

return Q
