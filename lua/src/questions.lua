-- src/questions.lua
local U = require("src.util")

local Q = {}

function Q.loadQuestionsCSV(filename)
  local questionsByCategory = {}

  local function addLine(line)
    if line and #line > 0 then
      local row = U.csvSplitLine(line)
      if #row >= 6 then
        local cat, q, correct, w1, w2, w3 = row[1], row[2], row[3], row[4], row[5], row[6]
        cat = (cat or ""):match("^%s*(.-)%s*$")
        questionsByCategory[cat] = questionsByCategory[cat] or {}
        table.insert(questionsByCategory[cat], {
          question = q,
          correct = correct,
          wrong = {w1, w2, w3},
        })
      end
    end
  end

  if love.filesystem.getInfo(filename) then
    for line in love.filesystem.lines(filename) do
      addLine(line)
    end
    return questionsByCategory
  end

  local file = io.open(filename, "r")
  if file then
    for line in file:lines() do
      addLine(line)
    end
    file:close()
    return questionsByCategory
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
      return questionsByCategory
    end
  end

  print("Warning: missing " .. filename)
  
  return questionsByCategory
end

function Q.getRandomQuestionAny(questionsByCategory)
  local cats = {}
  for k, v in pairs(questionsByCategory) do
    if v and #v > 0 then table.insert(cats, k) end
  end
  if #cats == 0 then return nil end

  local cat = cats[love.math.random(#cats)]
  local list = questionsByCategory[cat]
  return list[love.math.random(#list)], cat
end

function Q.getRandomQuestionFrom(questionsByCategory, category)
  local list = questionsByCategory[category]
  if list and #list > 0 then
    return list[love.math.random(#list)], category
  end
  return Q.getRandomQuestionAny(questionsByCategory)
end

return Q
