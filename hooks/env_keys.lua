--- Configures environment variables for the installed llama.cpp
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#envkeys-hook
--- @param ctx EnvKeysCtx
--- @return EnvKey[]
function PLUGIN:EnvKeys(ctx)
    local mainPath = ctx.path

    -- Detect oneAPI base path
    local oneapi = "/opt/intel/oneapi"
    if not file_exists(oneapi) then
        local custom = os.getenv("ONEAPI_ROOT")
        if custom then
            oneapi = custom
        end
    end

    local env_vars = {
        {
            key = "PATH",
            value = mainPath .. "/bin",
        },
        {
            key = "LD_LIBRARY_PATH",
            value = mainPath .. "/lib",
        },
    }

    -- Add oneAPI runtime library paths (using "latest" symlinks for version independence)
    local oneapi_lib_paths = {
        oneapi .. "/compiler/latest/lib",
        oneapi .. "/compiler/latest/opt/compiler/lib",
        oneapi .. "/mkl/latest/lib",
        oneapi .. "/tbb/latest/lib/intel64/gcc4.8",
        oneapi .. "/umf/latest/lib",
        oneapi .. "/tcm/latest/lib",
    }

    for _, lib_path in ipairs(oneapi_lib_paths) do
        if file_exists(lib_path) then
            table.insert(env_vars, {
                key = "LD_LIBRARY_PATH",
                value = lib_path,
            })
        end
    end

    return env_vars
end

--- Check if a file or directory exists
--- @param path string
--- @return boolean
function file_exists(path)
    return os.execute("test -e '" .. path .. "'") == 0
end
