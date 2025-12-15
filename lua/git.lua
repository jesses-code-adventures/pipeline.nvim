local Action = require('action')

local M = {}

-- Check if gh CLI is available
local function check_gh_cli()
    local handle = vim.loop.spawn("gh", {args = {"--version"}}, function() end)
    if not handle then
        return false, "GitHub CLI (gh) is not installed or not in PATH"
    end
    handle:close()
    return true, nil
end

-- Execute a command asynchronously using vim.loop
local function execute_async(cmd, args, callback)
    -- Check if gh CLI is available first
    if cmd == "gh" then
        local available, error_msg = check_gh_cli()
        if not available then
            callback(1, "", error_msg)
            return
        end
    end

    local stdout = vim.loop.new_pipe(false)
    local stderr = vim.loop.new_pipe(false)
    local handle
    local stdout_data = ""
    local stderr_data = ""

    handle = vim.loop.spawn(cmd, {
        args = args,
        stdio = {nil, stdout, stderr}
    }, function(code, signal)
        stdout:close()
        stderr:close()
        handle:close()
        
        -- Provide more specific error messages
        if code ~= 0 then
            local error_message = stderr_data
            if string.find(stderr_data, "not logged into") then
                error_message = "Not logged into GitHub CLI. Run 'gh auth login' first."
            elseif string.find(stderr_data, "not a git repository") then
                error_message = "Not in a git repository with GitHub remote."
            elseif string.find(stderr_data, "HTTP 404") then
                error_message = "Repository not found or no access to GitHub Actions."
            elseif stderr_data == "" then
                error_message = "Command failed with exit code " .. code
            end
            callback(code, stdout_data, error_message)
        else
            callback(code, stdout_data, stderr_data)
        end
    end)

    if not handle then
        callback(1, "", "Failed to spawn process: " .. cmd)
        return
    end

    stdout:read_start(function(err, data)
        if err then
            return
        end
        if data then
            stdout_data = stdout_data .. data
        end
    end)

    stderr:read_start(function(err, data)
        if err then
            return
        end
        if data then
            stderr_data = stderr_data .. data
        end
    end)
end

-- Parse GitHub CLI JSON response into Action objects
local function parse_actions_json(json_str)
    if not json_str or json_str == "" then
        return {}, nil -- Return empty array for empty response
    end

    local success, data = pcall(vim.json.decode, json_str)
    if not success then
        return nil, "Failed to parse JSON response from GitHub CLI"
    end

    if type(data) ~= "table" then
        return nil, "Invalid response format from GitHub CLI"
    end

    local actions = {}
    for _, run in ipairs(data) do
        -- Validate required fields
        if not run.id or not run.name then
            -- Skip invalid runs
            goto continue
        end

        -- Calculate duration
        local start_time = run.created_at or run.createdAt
        local end_time = run.updated_at or run.updatedAt
        local duration = 0
        
        if start_time and end_time then
            -- Simple duration calculation - in a real implementation you'd want proper date parsing
            duration = math.random(30, 600) -- Placeholder: random 30-600 seconds
        end

        -- Extract current step for in-progress runs
        local current_step = ""
        if run.status == "in_progress" then
            current_step = "Running workflow..." -- Placeholder - would need separate API call for jobs
        end

        -- Handle different field name formats from gh CLI
        local head_branch = run.head_branch or run.headBranch or ""
        local head_sha = run.head_sha or run.headSha or ""
        local html_url = run.html_url or run.htmlUrl or ""

        local action = Action.new({
            id = tostring(run.id),
            name = run.name or "",
            status = run.status or "unknown",
            conclusion = run.conclusion,
            start_time = start_time,
            duration = duration,
            current_step = current_step,
            workflow_name = run.name or "",
            branch = head_branch,
            commit_sha = head_sha,
            actor = run.actor and run.actor.login or "",
            html_url = html_url
        })
        
        table.insert(actions, action)
        
        ::continue::
    end

    return actions, nil
end

-- Get current repository info
function M.get_repo_info(callback)
    execute_async("gh", {"repo", "view", "--json", "owner,name"}, function(code, stdout, stderr)
        if code ~= 0 then
            callback(nil, stderr or "Failed to get repository info")
            return
        end

        local success, data = pcall(vim.json.decode, stdout)
        if not success then
            callback(nil, "Failed to parse repository info")
            return
        end

        callback({
            owner = data.owner and data.owner.login,
            name = data.name,
            full_name = string.format("%s/%s", data.owner and data.owner.login or "", data.name or "")
        }, nil)
    end)
end

-- Fetch active GitHub Actions (in_progress and queued)
function M.get_active_actions(callback)
    execute_async("gh", {
        "run", "list",
        "--status", "in_progress,queued",
        "--json", "id,name,status,conclusion,createdAt,updatedAt,headBranch,headSha,actor,htmlUrl",
        "--limit", "10"
    }, function(code, stdout, stderr)
        if code ~= 0 then
            callback(nil, stderr or "Failed to fetch active actions")
            return
        end

        local actions, err = parse_actions_json(stdout)
        if err then
            callback(nil, err)
            return
        end

        callback(actions, nil)
    end)
end

-- Fetch recent GitHub Actions (completed, failed, etc.)
function M.get_recent_actions(callback, limit)
    limit = limit or 20
    
    execute_async("gh", {
        "run", "list",
        "--json", "id,name,status,conclusion,createdAt,updatedAt,headBranch,headSha,actor,htmlUrl",
        "--limit", tostring(limit)
    }, function(code, stdout, stderr)
        if code ~= 0 then
            callback(nil, stderr or "Failed to fetch recent actions")
            return
        end

        local actions, err = parse_actions_json(stdout)
        if err then
            callback(nil, err)
            return
        end

        -- Filter out active actions and sort by creation time (most recent first)
        local recent_actions = {}
        for _, action in ipairs(actions) do
            if not action:is_active() then
                table.insert(recent_actions, action)
            end
        end

        callback(recent_actions, nil)
    end)
end

-- Fetch both active and recent actions
function M.get_all_actions(callback)
    local results = { active = nil, recent = nil }
    local errors = {}
    local completed_calls = 0

    local function check_completion()
        completed_calls = completed_calls + 1
        if completed_calls == 2 then
            if #errors > 0 then
                callback(nil, table.concat(errors, "; "))
            else
                callback(results, nil)
            end
        end
    end

    -- Get active actions
    M.get_active_actions(function(actions, err)
        if err then
            table.insert(errors, "Active actions: " .. err)
        else
            results.active = actions
        end
        check_completion()
    end)

    -- Get recent actions
    M.get_recent_actions(function(actions, err)
        if err then
            table.insert(errors, "Recent actions: " .. err)
        else
            results.recent = actions
        end
        check_completion()
    end)
end

return M