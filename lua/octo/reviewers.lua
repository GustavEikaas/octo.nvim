---@diagnostic disable
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local utils = require "octo.utils"

local M = {}

local function add_excluded(excluded, value)
  if not utils.is_blank(value) then
    excluded[value] = true
  end
end

local function requested_reviewer_name(request)
  if not request then
    return nil
  end

  local reviewer = request.requestedReviewer or request
  return reviewer.login or reviewer.slug or reviewer.name
end

local function build_excluded(buffer)
  local excluded = {}
  add_excluded(excluded, vim.g.octo_viewer)

  if buffer and buffer.node then
    if buffer.node.author then
      add_excluded(excluded, buffer.node.author.login)
    end

    local review_requests = buffer.node.reviewRequests
    if review_requests and review_requests.nodes then
      for _, request in ipairs(review_requests.nodes) do
        add_excluded(excluded, requested_reviewer_name(request))
      end
    end
  end

  return excluded
end

local function normalize_user(user, suggested)
  if not user or vim.tbl_isempty(user) or utils.is_blank(user.login) then
    return nil
  end

  return {
    kind = "user",
    id = user.node_id or user.id,
    login = user.login,
    name = user.name,
    text = user.login,
    suggested = suggested or false,
  }
end

local function normalize_team(team)
  if not team or vim.tbl_isempty(team) or utils.is_blank(team.slug) then
    return nil
  end

  return {
    kind = "team",
    id = team.node_id or team.id,
    name = team.name or team.slug,
    slug = team.slug,
    text = team.name or team.slug,
    suggested = false,
  }
end

local function candidate_key(candidate)
  if candidate.kind == "team" then
    return "team:" .. candidate.slug
  end
  return "user:" .. candidate.login
end

local function insert_candidate(candidates, seen, excluded, candidate)
  if not candidate then
    return
  end

  local name = candidate.kind == "team" and candidate.slug or candidate.login
  if
    excluded[name] or (candidate.kind == "team" and not utils.is_blank(candidate.name) and excluded[candidate.name])
  then
    return
  end

  local key = candidate_key(candidate)
  if seen[key] then
    if candidate.suggested then
      seen[key].suggested = true
    end
    return
  end

  seen[key] = candidate
  table.insert(candidates, candidate)
end

local function sort_candidates(candidates)
  table.sort(candidates, function(a, b)
    if a.kind ~= b.kind then
      return a.kind == "user"
    end
    if a.suggested ~= b.suggested then
      return a.suggested
    end
    return (a.text or ""):lower() < (b.text or ""):lower()
  end)
end

local function fetch_collaborators(owner, name)
  local output, stderr = gh.api.get {
    "/repos/{owner}/{name}/collaborators",
    format = { owner = owner, name = name },
    f = { per_page = 100 },
    paginate = true,
    opts = { mode = "sync" },
  }
  if stderr and not utils.is_blank(stderr) then
    return {}
  end
  if utils.is_blank(output) then
    return {}
  end
  return utils.get_flatten_pages(output)
end

local function fetch_teams(owner, name)
  local output, stderr = gh.api.get {
    "/repos/{owner}/{name}/teams",
    format = { owner = owner, name = name },
    f = { per_page = 100 },
    paginate = true,
    opts = { mode = "sync" },
  }
  if stderr and not utils.is_blank(stderr) then
    return {}
  end
  if utils.is_blank(output) then
    return {}
  end
  return utils.get_flatten_pages(output)
end

local function fetch_suggested_reviewers(owner, name, number)
  local output, stderr = gh.api.graphql {
    query = queries.suggested_reviewers,
    F = { owner = owner, name = name, number = number },
    opts = { mode = "sync" },
  }
  if stderr and not utils.is_blank(stderr) then
    return {}
  end
  if utils.is_blank(output) then
    return {}
  end

  local ok, resp = pcall(vim.json.decode, output)
  if not ok then
    return {}
  end

  local pr = resp.data and resp.data.repository and resp.data.repository.pullRequest
  local suggested = pr and pr.suggestedReviewers
  return (suggested and suggested.nodes) or {}
end

function M.get_candidates(opts)
  opts = opts or {}

  local buffer = opts.buffer or utils.get_current_buffer()
  if not buffer then
    return {}
  end
  if buffer.isPullRequest and not buffer:isPullRequest() then
    return {}
  end

  local owner = opts.owner or buffer.owner
  local name = opts.name or buffer.name
  local number = opts.number or buffer.number
  local excluded = opts.excluded or build_excluded(buffer)
  local candidates = {}
  local seen = {}

  for _, item in ipairs(fetch_suggested_reviewers(owner, name, number)) do
    insert_candidate(candidates, seen, excluded, normalize_user(item.reviewer, true))
  end

  for _, user in ipairs(fetch_collaborators(owner, name)) do
    insert_candidate(candidates, seen, excluded, normalize_user(user, false))
  end

  for _, team in ipairs(fetch_teams(owner, name)) do
    insert_candidate(candidates, seen, excluded, normalize_team(team))
  end

  sort_candidates(candidates)

  return candidates
end

function M.format_candidate(candidate)
  local label
  if candidate.kind == "team" then
    label = string.format("%s (%s)", candidate.name or candidate.slug, candidate.slug)
  elseif not utils.is_blank(candidate.name) then
    label = string.format("%s (%s)", candidate.login, candidate.name)
  else
    label = candidate.login
  end

  if candidate.suggested then
    label = "[suggested] " .. label
  end

  return label
end

M._private = {
  build_excluded = build_excluded,
  insert_candidate = insert_candidate,
  normalize_team = normalize_team,
  normalize_user = normalize_user,
  sort_candidates = sort_candidates,
}

return M
