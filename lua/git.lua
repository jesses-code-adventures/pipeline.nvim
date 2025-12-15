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
        -- Use the correct field names from gh CLI
        local id = run.databaseId or run.id
        local name = run.name or run.workflowName
        
        -- Validate required fields
        if id and name then
            -- Calculate duration
            local start_time = run.createdAt or run.created_at
            local end_time = run.updatedAt or run.updated_at
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

            -- Handle field name formats from gh CLI
            local head_branch = run.headBranch or run.head_branch or ""
            local head_sha = run.headSha or run.head_sha or ""
            local html_url = run.url or run.htmlUrl or run.html_url or ""
            local workflow_name = run.workflowName or run.name or ""

            -- Extract repository info
            local repository = ""
            if run.repository then
                if type(run.repository) == "table" then
                    repository = run.repository.name or run.repository.full_name or ""
                else
                    repository = tostring(run.repository)
                end
            end

            local action = Action.new({
                id = tostring(id),
                name = name,
                status = run.status or "unknown",
                conclusion = run.conclusion,
                start_time = start_time,
                duration = duration,
                current_step = current_step,
                workflow_name = workflow_name,
                branch = head_branch,
                commit_sha = head_sha,
                actor = "", -- No actor info in current fields
                html_url = html_url,
                repository = repository
            })

            table.insert(actions, action)
        end
    end

    return actions, nil
end

-- Get repositories ordered by recent activity (pushed_at)
function M.get_recent_repos(callback)
    -- First get user's personal repositories
    execute_async("gh", {
        "repo", "list", 
        "--json", "name,owner,pushedAt,updatedAt,isPrivate",
        "--limit", "100"
    }, function(code, stdout, stderr)
        if code ~= 0 then
            callback(nil, "Failed to fetch repositories: " .. (stderr or "unknown error"))
            return
        end

        local success, personal_repos = pcall(vim.json.decode, stdout)
        if not success or not personal_repos then
            callback(nil, "Failed to parse repositories list")
            return
        end

        -- Also get organization repositories
        execute_async("gh", {
            "repo", "list",
            "--source", "member",
            "--json", "name,owner,pushedAt,updatedAt,isPrivate",
            "--limit", "200"
        }, function(org_code, org_stdout, org_stderr)
            local org_repos = {}
            if org_code == 0 then
                local org_success, parsed_org_repos = pcall(vim.json.decode, org_stdout)
                if org_success and parsed_org_repos then
                    org_repos = parsed_org_repos
                end
            end

            -- Combine both lists
            local all_repos = {}
            for _, repo in ipairs(personal_repos) do
                table.insert(all_repos, repo)
            end
            for _, repo in ipairs(org_repos) do
                table.insert(all_repos, repo)
            end

            -- Add full_name field and sort by most recent activity
            for _, repo in ipairs(all_repos) do
                repo.full_name = string.format("%s/%s", repo.owner.login, repo.name)
                -- Use pushedAt for sorting (most recent git activity)
                repo.sort_date = repo.pushedAt or repo.updatedAt or ""
            end

            -- Sort repos by most recent activity first
            table.sort(all_repos, function(a, b)
                return (a.sort_date or "") > (b.sort_date or "")
            end)

            callback(all_repos, nil)
        end)
    end)
end

-- Fetch active GitHub Actions (in_progress and queued) from all accessible repos
function M.get_active_actions(callback)
    -- Get repositories ordered by recent activity, then fetch active actions
    M.get_recent_repos(function(repos, err)
        if err then
            callback(nil, "Failed to fetch repositories: " .. err)
            return
        end

        -- Fetch active actions from repos (limit to first 30 repos to avoid rate limits)
        local all_active_actions = {}
        local completed_repos = 0
        local max_repos = math.min(#repos, 30)
        
        if max_repos == 0 then
            callback({}, nil)
            return
        end

        -- Check both in_progress and queued status for each repo
        local function fetch_repo_active_actions(repo_name, repo_callback)
            execute_async("gh", {
                "run", "list",
                "--repo", repo_name,
                "--status", "in_progress",
                "--json", "databaseId,name,status,conclusion,createdAt,updatedAt,headBranch,headSha,url,workflowName",
                "--limit", "3"
            }, function(code1, stdout1, stderr1)
                local in_progress_actions = {}
                if code1 == 0 then
                    local actions, err1 = parse_actions_json(stdout1)
                    if not err1 and actions then
                        for _, action in ipairs(actions) do
                            action.repository = repo_name
                            table.insert(in_progress_actions, action)
                        end
                    end
                end

                -- Also check queued actions
                execute_async("gh", {
                    "run", "list",
                    "--repo", repo_name,
                    "--status", "queued",
                    "--json", "databaseId,name,status,conclusion,createdAt,updatedAt,headBranch,headSha,url,workflowName",
                    "--limit", "3"
                }, function(code2, stdout2, stderr2)
                    local queued_actions = {}
                    if code2 == 0 then
                        local actions, err2 = parse_actions_json(stdout2)
                        if not err2 and actions then
                            for _, action in ipairs(actions) do
                                action.repository = repo_name
                                table.insert(queued_actions, action)
                            end
                        end
                    end

                    -- Combine both types
                    local repo_actions = {}
                    for _, action in ipairs(in_progress_actions) do
                        table.insert(repo_actions, action)
                    end
                    for _, action in ipairs(queued_actions) do
                        table.insert(repo_actions, action)
                    end

                    repo_callback(repo_actions)
                end)
            end)
        end

        -- Process repos concurrently
        for i = 1, max_repos do
            local repo = repos[i]
            fetch_repo_active_actions(repo.full_name, function(repo_actions)
                completed_repos = completed_repos + 1
                
                -- Add this repo's actions to the total
                for _, action in ipairs(repo_actions) do
                    table.insert(all_active_actions, action)
                end
                
                -- Check if we've completed all repos
                if completed_repos == max_repos then
                    callback(all_active_actions, nil)
                end
            end)
        end
    end)
end

-- Fetch recent GitHub Actions (completed, failed, etc.) from all accessible repos
function M.get_recent_actions(callback, limit)
    limit = limit or 40

    -- Get repositories ordered by recent activity, then fetch recent actions
    M.get_recent_repos(function(repos, err)
        if err then
            callback(nil, "Failed to fetch repositories: " .. err)
            return
        end

        -- Fetch recent actions from repos (limit to first 30 repos for recent actions)
        local all_recent_actions = {}
        local completed_repos = 0
        local max_repos = math.min(#repos, 30)
        
        if max_repos == 0 then
            callback({}, nil)
            return
        end

        -- Fetch recent actions from each repo (last year)
        for i = 1, max_repos do
            local repo = repos[i]
            execute_async("gh", {
                "run", "list",
                "--repo", repo.full_name,
                "--json", "databaseId,name,status,conclusion,createdAt,updatedAt,headBranch,headSha,url,workflowName",
                "--limit", "20"
            }, function(code, stdout, stderr)
                completed_repos = completed_repos + 1
                
                if code == 0 then
                    local actions, parse_err = parse_actions_json(stdout)
                    if not parse_err and actions then
                        -- Add repository info and filter out active actions
                        for _, action in ipairs(actions) do
                            action.repository = repo.full_name
                            -- Only include completed actions (not active ones)
                            if not action:is_active() then
                                table.insert(all_recent_actions, action)
                            end
                        end
                    end
                end
                
                -- Check if we've completed all repos
                if completed_repos == max_repos then
                    -- Sort all actions by creation time (most recent first)
                    table.sort(all_recent_actions, function(a, b)
                        return (a.start_time or "") > (b.start_time or "")
                    end)
                    
                    -- Limit total results
                    local limited_actions = {}
                    for i = 1, math.min(limit, #all_recent_actions) do
                        table.insert(limited_actions, all_recent_actions[i])
                    end
                    
                    callback(limited_actions, nil)
                end
            end)
        end
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