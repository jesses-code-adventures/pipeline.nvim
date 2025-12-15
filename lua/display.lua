local M = {}

-- Configuration for display
local config = {
    box_width = 40,
    box_height = 6,
    margin = 2,
    active_border_color = "DiagnosticWarn", -- Yellow border for active actions
    completed_border_color = "Normal",
}

-- Create highlight groups
local function setup_highlights()
    vim.api.nvim_set_hl(0, "PipelineActiveBorder", {fg = "#f0c674"}) -- Yellow
    vim.api.nvim_set_hl(0, "PipelineCompletedBorder", {fg = "#5c6370"}) -- Gray
    vim.api.nvim_set_hl(0, "PipelineSuccess", {fg = "#98c379"}) -- Green
    vim.api.nvim_set_hl(0, "PipelineFailure", {fg = "#e06c75"}) -- Red
    vim.api.nvim_set_hl(0, "PipelineCancelled", {fg = "#abb2bf"}) -- Light gray
    vim.api.nvim_set_hl(0, "PipelineInProgress", {fg = "#f0c674"}) -- Yellow
end

-- Create a box border with corners and edges
local function create_box_border(width, height, is_active)
    local lines = {}
    local border_hl = is_active and "PipelineActiveBorder" or "PipelineCompletedBorder"

    -- Top border
    lines[1] = "┌" .. string.rep("─", width - 2) .. "┐"

    -- Side borders
    for i = 2, height - 1 do
        lines[i] = "│" .. string.rep(" ", width - 2) .. "│"
    end

    -- Bottom border
    lines[height] = "└" .. string.rep("─", width - 2) .. "┘"

    return lines, border_hl
end

-- Format action content for display
local function format_action_content(action, width)
    local content_width = width - 4 -- Account for borders and padding
    local lines = {}

    -- Line 1: Status symbol and workflow name
    local status_symbol = action:get_status_symbol()
    local name = action:get_display_name()
    if string.len(name) > content_width - 2 then
        name = string.sub(name, 1, content_width - 5) .. "..."
    end
    lines[1] = string.format(" %s %s", status_symbol, name)

    -- Line 2: Repository (if available)
    if action.repository ~= "" then
        local repo = action.repository
        if string.len(repo) > content_width then
            repo = string.sub(repo, 1, content_width - 3) .. "..."
        end
        lines[2] = string.format(" Repo: %s", repo)
    else
        lines[2] = ""
    end

    -- Line 3: Duration
    local duration_str = action:get_duration_string()
    lines[3] = string.format(" Duration: %s", duration_str)

    -- Line 4: Current step (for active) or branch info (for completed)
    if action:is_active() and action.current_step ~= "" then
        local step = action.current_step
        if string.len(step) > content_width then
            step = string.sub(step, 1, content_width - 3) .. "..."
        end
        lines[4] = string.format(" %s", step)
    else
        local branch_info = action:get_branch_info()
        if string.len(branch_info) > content_width then
            branch_info = string.sub(branch_info, 1, content_width - 3) .. "..."
        end
        lines[4] = string.format(" Branch: %s", branch_info)
    end

    return lines
end

-- Render a single action box
function M.render_action_box(action)
    local box_lines, border_hl = create_box_border(config.box_width, config.box_height, action:is_active())
    local content_lines = format_action_content(action, config.box_width)

    -- Insert content into box
    for i, content in ipairs(content_lines) do
        if i + 1 <= #box_lines - 1 then -- Skip top and bottom border
            local line_idx = i + 1
            local padded_content = content .. string.rep(" ", config.box_width - 2 - string.len(content))
            box_lines[line_idx] = "│" .. padded_content .. "│"
        end
    end

    return {
        lines = box_lines,
        border_highlight = border_hl,
        status_highlight = action:get_status_color(),
        action = action
    }
end

-- Calculate layout for multiple action boxes
function M.calculate_layout(active_actions, recent_actions, win_width, win_height)
    local boxes_per_row = math.floor(win_width / (config.box_width + config.margin))
    if boxes_per_row < 1 then boxes_per_row = 1 end

    local layout = {
        boxes_per_row = boxes_per_row,
        active_section = {},
        recent_section = {},
        total_height = 0
    }

    -- Calculate active actions layout
    if #active_actions > 0 then
        layout.active_section.start_row = 1
        layout.active_section.title = "● Active GitHub Actions"
        local active_rows = math.ceil(#active_actions / boxes_per_row)
        layout.active_section.height = 2 + (active_rows * (config.box_height + 1)) -- Title + boxes + spacing
        layout.total_height = layout.active_section.height
    end

    -- Calculate recent actions layout
    if #recent_actions > 0 then
        layout.recent_section.start_row = layout.total_height + 2
        layout.recent_section.title = "● Recent GitHub Actions"
        local recent_rows = math.ceil(#recent_actions / boxes_per_row)
        layout.recent_section.height = 2 + (recent_rows * (config.box_height + 1)) -- Title + boxes + spacing
        layout.total_height = layout.total_height + layout.recent_section.height
    end

    return layout
end

-- Generate all display lines and highlights
function M.generate_display_content(active_actions, recent_actions, win_width, win_height)
    setup_highlights()

    local layout = M.calculate_layout(active_actions, recent_actions, win_width, win_height)
    local lines = {}
    local highlights = {}
    local current_line = 1

    -- Helper function to add lines
    local function add_lines(content_lines, hl_group)
        for _, line in ipairs(content_lines) do
            lines[current_line] = line
            if hl_group then
                table.insert(highlights, {
                    line = current_line - 1, -- 0-based for nvim_buf_add_highlight
                    col_start = 0,
                    col_end = -1,
                    hl_group = hl_group
                })
            end
            current_line = current_line + 1
        end
    end

    -- Render active actions section
    if #active_actions > 0 then
        add_lines({layout.active_section.title}, "PipelineInProgress")
        add_lines({""}) -- Spacing

        for i, action in ipairs(active_actions) do
            local box = M.render_action_box(action)
            local row_in_section = math.floor((i - 1) / layout.boxes_per_row)
            local col_in_row = (i - 1) % layout.boxes_per_row

            -- For simplicity, we'll render boxes vertically for now
            -- In a more sophisticated implementation, you'd position them in a grid
            for j, box_line in ipairs(box.lines) do
                lines[current_line] = box_line
                table.insert(highlights, {
                    line = current_line - 1,
                    col_start = 0,
                    col_end = -1,
                    hl_group = box.border_highlight
                })
                current_line = current_line + 1
            end
            add_lines({""}) -- Spacing between boxes
        end
    end

    -- Render recent actions section
    if #recent_actions > 0 then
        add_lines({layout.recent_section.title}, "Normal")
        add_lines({""}) -- Spacing

        for i, action in ipairs(recent_actions) do
            local box = M.render_action_box(action)

            for j, box_line in ipairs(box.lines) do
                lines[current_line] = box_line
                table.insert(highlights, {
                    line = current_line - 1,
                    col_start = 0,
                    col_end = -1,
                    hl_group = box.border_highlight
                })
                current_line = current_line + 1
            end
            add_lines({""}) -- Spacing between boxes
        end
    end

    -- Add empty message if no actions
    if #active_actions == 0 and #recent_actions == 0 then
        add_lines({"No GitHub Actions found.", "", "Make sure you're in a repository with GitHub Actions enabled."}, "Comment")
    end

    return {
        lines = lines,
        highlights = highlights,
        layout = layout
    }
end

-- Create and configure floating window
function M.create_floating_window(content)
    local win_width = math.min(vim.o.columns - 4, 120)
    local win_height = math.min(vim.o.lines - 4, math.max(20, #content.lines + 2))

    local row = math.floor((vim.o.lines - win_height) / 2)
    local col = math.floor((vim.o.columns - win_width) / 2)

    -- Create buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content.lines)

    -- Set buffer options
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'pipeline')

    -- Apply highlights
    for _, hl in ipairs(content.highlights) do
        vim.api.nvim_buf_add_highlight(buf, -1, hl.hl_group, hl.line, hl.col_start, hl.col_end)
    end

    -- Create window
    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = win_width,
        height = win_height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded',
        title = ' GitHub Actions Pipeline ',
        title_pos = 'center',
    })

    -- Set window options
    vim.api.nvim_win_set_option(win, 'cursorline', true)
    vim.api.nvim_win_set_option(win, 'wrap', false)

    -- Set up keymaps for the window
    local opts = { buffer = buf, silent = true }
    vim.keymap.set('n', 'q', '<cmd>close<cr>', opts)
    vim.keymap.set('n', '<Esc>', '<cmd>close<cr>', opts)

    return { buf = buf, win = win }
end

return M
