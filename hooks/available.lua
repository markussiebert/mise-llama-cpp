--- Returns a list of available versions for llama.cpp
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#available-hook
--- @param ctx AvailableCtx
--- @return AvailableVersion[]
function PLUGIN:Available(ctx)
    local http = require("http")
    local json = require("json")

    local versions = {}
    local page = 1
    local per_page = 100

    -- GitHub API limits to 1000 results (10 pages of 100)
    local max_pages = 10

    while page <= max_pages do
        local resp, err = http.get({
            url = "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page="
                .. per_page
                .. "&page="
                .. page,
        })

        if err ~= nil then
            error("Failed to fetch releases: " .. err)
        end
        if resp.status_code ~= 200 then
            break
        end

        local releases = json.decode(resp.body)
        if #releases == 0 then
            break
        end

        for _, release in ipairs(releases) do
            if not release.prerelease and not release.draft then
                local version = release.tag_name
                table.insert(versions, {
                    version = version,
                })
            end
        end

        if #releases < per_page then
            break
        end
        page = page + 1
    end

    -- Sort ascending by build number (tags are "b1234")
    -- mise internally reverses this list, so oldest must come first
    table.sort(versions, function(a, b)
        local num_a = tonumber(a.version:match("^b(%d+)$"))
        local num_b = tonumber(b.version:match("^b(%d+)$"))
        if num_a and num_b then
            return num_a < num_b
        end
        return a.version < b.version
    end)

    -- Add master as a rolling release (always re-fetched)
    table.insert(versions, {
        version = "master",
        note = "latest master branch (rolling)",
        rolling = true,
    })

    return versions
end
