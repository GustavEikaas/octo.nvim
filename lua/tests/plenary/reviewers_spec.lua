---@diagnostic disable
local reviewers = require "octo.reviewers"
local eq = assert.are.same

describe("Reviewers:", function()
  local private = reviewers._private

  it("deduplicates suggested reviewers against collaborators", function()
    local candidates = {}
    local seen = {}
    local excluded = {}

    private.insert_candidate(candidates, seen, excluded, private.normalize_user({ id = "U_1", login = "alice" }, false))
    private.insert_candidate(
      candidates,
      seen,
      excluded,
      private.normalize_user({ id = "U_1", login = "alice", name = "Alice" }, true)
    )

    eq(1, #candidates)
    eq(true, candidates[1].suggested)
  end)

  it("excludes viewer, author, and already-requested reviewers", function()
    vim.g.octo_viewer = "viewer"
    local excluded = private.build_excluded {
      node = {
        author = { login = "author" },
        reviewRequests = {
          nodes = {
            { requestedReviewer = { login = "requested-user" } },
            { requestedReviewer = { name = "requested-team" } },
          },
        },
      },
    }

    local candidates = {}
    local seen = {}
    for _, login in ipairs { "viewer", "author", "requested-user", "candidate" } do
      private.insert_candidate(candidates, seen, excluded, private.normalize_user { id = login, login = login })
    end
    private.insert_candidate(
      candidates,
      seen,
      excluded,
      private.normalize_team { node_id = "T_1", name = "requested-team", slug = "requested-team" }
    )

    eq(1, #candidates)
    eq("candidate", candidates[1].login)
  end)

  it("keeps team slugs for review request submission", function()
    local team = private.normalize_team {
      node_id = "T_kwDO",
      name = "Core Team",
      slug = "core-team",
    }

    eq("team", team.kind)
    eq("core-team", team.slug)
    eq("T_kwDO", team.id)
  end)

  it("sorts suggested reviewers first", function()
    local candidates = {
      private.normalize_user({ id = "U_1", login = "zara" }, false),
      private.normalize_user({ id = "U_2", login = "alice" }, true),
    }

    private.sort_candidates(candidates)

    eq("alice", candidates[1].login)
    eq(true, candidates[1].suggested)
  end)

  it("sorts users before teams", function()
    local candidates = {
      private.normalize_team { node_id = "T_1", name = "Core Team", slug = "core-team" },
      private.normalize_user({ id = "U_1", login = "zara" }, false),
    }

    private.sort_candidates(candidates)

    eq("user", candidates[1].kind)
    eq("team", candidates[2].kind)
  end)

  it("formats reviewer candidates", function()
    eq(
      "[suggested] alice (Alice)",
      reviewers.format_candidate { kind = "user", login = "alice", name = "Alice", suggested = true }
    )
    eq("Core Team (core-team)", reviewers.format_candidate { kind = "team", name = "Core Team", slug = "core-team" })
  end)
end)
