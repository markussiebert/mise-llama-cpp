--- Builds llama.cpp from source with SYCL support after download
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#postinstall-hook
--- @param ctx PostInstallCtx
function PLUGIN:PostInstall(ctx)
    -- Only supported on Linux amd64
    if RUNTIME.osType:lower() ~= "linux" or RUNTIME.archType:lower() ~= "amd64" then
        error("llama-cpp SYCL plugin only supports Linux amd64 (Ubuntu). Current: " .. RUNTIME.osType .. "/" .. RUNTIME.archType)
    end

    local sdkInfo = ctx.sdkInfo[PLUGIN.name]
    local path = sdkInfo.path
    local version = sdkInfo.version

    -- The extracted tarball creates a subdirectory like llama.cpp-b1234/
    -- Find the source directory
    local source_dir = find_source_dir(path, version)

    -- Detect Intel oneAPI environment
    local oneapi_path = detect_oneapi()

    -- Detect ccache for build caching
    local ccache_available = detect_ccache()

    -- Build llama.cpp with SYCL
    build_llama_cpp(path, source_dir, oneapi_path, ccache_available)

    -- Clean up source directory to save disk space
    os.execute("rm -rf '" .. source_dir .. "'")

    -- Verify the build
    verify_build(path)
end

--- Find the extracted source directory
--- @param path string Installation path
--- @param version string Version string
--- @return string Source directory path
function find_source_dir(path, version)
    -- Check if CMakeLists.txt is directly in the install path (mise flattened the archive)
    if os.execute("test -f '" .. path .. "/CMakeLists.txt'") == 0 then
        return path
    end

    -- GitHub tarballs extract to {repo}-{tag}/ subdirectory
    local patterns = {
        path .. "/llama.cpp-" .. version,
        path .. "/llama.cpp-" .. version:gsub("^v", ""),
        path .. "/llama.cpp-" .. version:gsub("^b", ""),
    }

    for _, dir in ipairs(patterns) do
        if os.execute("test -d '" .. dir .. "'") == 0 then
            return dir
        end
    end

    -- Fallback: find any directory containing CMakeLists.txt
    local handle = io.popen("find '" .. path .. "' -maxdepth 2 -name 'CMakeLists.txt' -printf '%h\\n' 2>/dev/null | head -1")
    if handle then
        local result = handle:read("*l")
        handle:close()
        if result and result ~= "" then
            return result
        end
    end

    -- Debug: show what's actually there
    local ls = io.popen("ls -la '" .. path .. "' 2>&1")
    local listing = ls and ls:read("*a") or "unable to list"
    if ls then ls:close() end

    error("Could not find llama.cpp source in " .. path .. "\nContents:\n" .. listing)
end

--- Detect Intel oneAPI installation
--- @param _ nil
--- @return string Path to oneAPI installation
function detect_oneapi()
    local search_paths = {
        "/opt/intel/oneapi",
        os.getenv("ONEAPI_ROOT") or "",
        os.getenv("HOME") .. "/intel/oneapi",
    }

    for _, p in ipairs(search_paths) do
        if p ~= "" then
            local check = os.execute("test -f '" .. p .. "/setvars.sh'")
            if check == 0 then
                return p
            end
        end
    end

    error(
        "Intel oneAPI not found. Please install Intel oneAPI Base Toolkit.\n"
            .. "See: https://www.intel.com/content/www/us/en/developer/tools/oneapi/base-toolkit-download.html\n"
            .. "Or run: https://github.com/markussiebert/llama-cpp-sycl/blob/main/install-intel-sycl-runtime.sh"
    )
end

--- Detect ccache for build caching
--- @return boolean Whether ccache is available
function detect_ccache()
    local result = os.execute("command -v ccache >/dev/null 2>&1")
    if result == 0 then
        -- Ensure ccache directory exists
        local cache_dir = (os.getenv("CCACHE_DIR") or os.getenv("HOME") .. "/.cache/ccache")
        os.execute("mkdir -p '" .. cache_dir .. "'")
        return true
    end
    return false
end

--- Build llama.cpp with SYCL support
--- @param install_path string Where to install the built binaries
--- @param source_dir string Path to the extracted source
--- @param oneapi_path string Path to oneAPI installation
--- @param ccache_available boolean Whether ccache is available
function build_llama_cpp(install_path, source_dir, oneapi_path, ccache_available)
    local build_dir = source_dir .. "/build"

    -- Construct cmake command with SYCL flags
    local cmake_args = {
        "-B '" .. build_dir .. "'",
        "-S '" .. source_dir .. "'",
        "-DGGML_SYCL=ON",
        "-DCMAKE_C_COMPILER=icx",
        "-DCMAKE_CXX_COMPILER=icpx",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_INSTALL_PREFIX='" .. install_path .. "'",
        "-DGGML_SYCL_DNN=ON",
    }

    -- Use ccache as compiler launcher to cache object files across builds
    if ccache_available then
        table.insert(cmake_args, "-DCMAKE_C_COMPILER_LAUNCHER=ccache")
        table.insert(cmake_args, "-DCMAKE_CXX_COMPILER_LAUNCHER=ccache")
    end

    local cmake_cmd = "cmake " .. table.concat(cmake_args, " ")

    -- Detect number of CPU cores for parallel build
    local nproc_handle = io.popen("nproc 2>/dev/null || echo 4")
    local nproc = "4"
    if nproc_handle then
        nproc = nproc_handle:read("*l") or "4"
        nproc_handle:close()
    end

    local build_cmd = "cmake --build '" .. build_dir .. "' --config Release -j " .. nproc
    local install_cmd = "cmake --install '" .. build_dir .. "'"

    -- Run the full build pipeline with oneAPI environment sourced
    local full_cmd = "bash -c '"
        .. "set -e && "
        .. 'source "' .. oneapi_path .. '/setvars.sh" --force 2>&1 && '
        .. (ccache_available
            and 'echo "==> Build cache: ccache enabled" && '
            or 'echo "==> Build cache: ccache not found, install ccache for faster rebuilds" && ')
        .. 'echo "==> Configuring llama.cpp with SYCL support..." && '
        .. cmake_cmd .. " 2>&1 && "
        .. 'echo "==> Building llama.cpp (using ' .. nproc .. ' cores)..." && '
        .. build_cmd .. " 2>&1 && "
        .. 'echo "==> Installing llama.cpp..." && '
        .. install_cmd .. " 2>&1"
        .. "'"

    local result = os.execute(full_cmd)
    if result ~= 0 then
        error(
            "Failed to build llama.cpp with SYCL support.\n"
                .. "Make sure Intel oneAPI Base Toolkit is properly installed.\n"
                .. "Required: Intel oneAPI DPC++/C++ compiler (icx/icpx), oneMKL, oneDNN"
        )
    end
end

--- Verify the build produced working binaries
--- @param install_path string Installation path
function verify_build(install_path)
    local binaries = { "llama-cli", "llama-server", "llama-quantize" }
    local found = false

    for _, binary in ipairs(binaries) do
        local check = os.execute("test -x '" .. install_path .. "/bin/" .. binary .. "'")
        if check == 0 then
            found = true
        end
    end

    if not found then
        error("Build verification failed: no llama.cpp binaries found in " .. install_path .. "/bin/")
    end
end
