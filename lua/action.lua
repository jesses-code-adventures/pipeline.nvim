local Action = {}
Action.__index = Action

-- Create a new Action instance
function Action.new(data)
    local self = setmetatable({}, Action)
    
    self.id = data.id or ""
    self.name = data.name or ""
    self.status = data.status or "unknown"  -- in_progress, completed, failed, cancelled
    self.conclusion = data.conclusion or ""  -- success, failure, cancelled, etc.
    self.start_time = data.start_time or ""
    self.duration = data.duration or 0  -- in seconds
    self.current_step = data.current_step or ""
    self.workflow_name = data.workflow_name or ""
    self.branch = data.branch or ""
    self.commit_sha = data.commit_sha or ""
    self.actor = data.actor or ""
    self.html_url = data.html_url or ""
    
    return self
end

-- Check if action is currently running
function Action:is_active()
    return self.status == "in_progress" or self.status == "queued"
end

-- Get formatted duration string
function Action:get_duration_string()
    if self.duration == 0 then
        return "0s"
    end
    
    local hours = math.floor(self.duration / 3600)
    local minutes = math.floor((self.duration % 3600) / 60)
    local seconds = self.duration % 60
    
    if hours > 0 then
        return string.format("%dh %dm %ds", hours, minutes, seconds)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, seconds)
    else
        return string.format("%ds", seconds)
    end
end

-- Get status display character/symbol
function Action:get_status_symbol()
    local symbols = {
        in_progress = "●",
        queued = "○",
        completed = "✓",
        success = "✓",
        failure = "✗",
        cancelled = "⊘",
        skipped = "⊝"
    }
    
    -- Use conclusion for completed actions, status for others
    local key = self.status == "completed" and self.conclusion or self.status
    return symbols[key] or "?"
end

-- Get status color for highlights
function Action:get_status_color()
    local colors = {
        in_progress = "DiagnosticWarn",  -- Yellow
        queued = "DiagnosticHint",       -- Gray
        success = "DiagnosticOk",        -- Green
        failure = "DiagnosticError",     -- Red
        cancelled = "Comment",           -- Gray
        skipped = "Comment"              -- Gray
    }
    
    local key = self.status == "completed" and self.conclusion or self.status
    return colors[key] or "Normal"
end

-- Get formatted display name
function Action:get_display_name()
    return self.workflow_name ~= "" and self.workflow_name or self.name
end

-- Get formatted branch/commit info
function Action:get_branch_info()
    local branch_part = self.branch ~= "" and self.branch or "unknown"
    local commit_part = self.commit_sha ~= "" and string.sub(self.commit_sha, 1, 7) or ""
    
    if commit_part ~= "" then
        return string.format("%s (%s)", branch_part, commit_part)
    else
        return branch_part
    end
end

return Action