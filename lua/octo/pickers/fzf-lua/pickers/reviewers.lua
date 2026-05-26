---@diagnostic disable
local fzf = require "fzf-lua"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local reviewers = require "octo.reviewers"
local utils = require "octo.utils"

return function(cb)
  local reviewer_list = reviewers.get_candidates()
  if #reviewer_list == 0 then
    utils.error "No reviewers found"
    return
  end

  local formatted_reviewers = {}
  local reviewer_titles = {}

  for _, reviewer in ipairs(reviewer_list) do
    local title = reviewers.format_candidate(reviewer)
    formatted_reviewers[title] = reviewer
    table.insert(reviewer_titles, title)
  end

  fzf.fzf_exec(
    reviewer_titles,
    vim.tbl_deep_extend("force", picker_utils.dropdown_opts, {
      actions = {
        ["default"] = function(selected)
          local reviewer = formatted_reviewers[selected[1]]
          if reviewer then
            cb(reviewer)
          end
        end,
      },
    })
  )
end
