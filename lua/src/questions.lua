-- src/questions.lua
local U = require("src.util")

local Q = {}

function Q.loadQuestionsCSV(filename)
  local questionsByCategory = {}

  if not love.filesystem.getInfo(filename) then
    print("Warning: missing " .. filename)
    return questionsByCategory
  end

  for line in love.filesystem.lines(filename) do
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
