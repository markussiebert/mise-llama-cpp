--- Returns download information for a specific llama.cpp version
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#preinstall-hook
--- @param ctx PreInstallCtx
--- @return PreInstallResult
function PLUGIN:PreInstall(ctx)
    local version = ctx.version

    local url
    if version == "master" then
        -- Download latest master branch snapshot
        url = "https://github.com/ggml-org/llama.cpp/archive/refs/heads/master.tar.gz"
    else
        -- Download tagged release source tarball
        url = "https://github.com/ggml-org/llama.cpp/archive/refs/tags/" .. version .. ".tar.gz"
    end

    return {
        version = version,
        url = url,
        note = "Downloading llama.cpp " .. version .. " source for SYCL build",
    }
end
