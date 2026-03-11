--- Returns a list of available versions for llama.cpp
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#available-hook
--- @param ctx AvailableCtx
--- @return AvailableVersion[]
function PLUGIN:Available(ctx)
    local http = require("http")
    local json = require("json")

    -- Only fetch the first page — GitHub returns newest first,
    -- so this covers latest + recent versions. No need to paginate
    -- through all 1000+ releases.
    local resp, err = http.get({
        url = "https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=100&page=1",
    })

    if err ~= nil then
        error("Failed to fetch releases: " .. err)
    end

    local versions = {}

    if resp.status_code == 200 then
        local releases = json.decode(resp.body)
        for _, release in ipairs(releases) do
            if not release.prerelease and not release.draft then
                table.insert(versions, {
                    version = release.tag_name,
                })
            end
        end
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
