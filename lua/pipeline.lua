local git = require('git')
local display = require('display')

local M = {}

-- Show error message (deferred to avoid fast event context issues)
local function show_error(msg)
    vim.schedule(function()
        vim.notify("Pipeline Error: " .. msg, vim.log.levels.ERROR)
    end)
end

-- ASCII spinner frames
local spinner_frames = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
local current_frame = 1

-- Create initial loading window
local function show_loading_window()
    local win_width = 60
    local win_height = 8
    
    local row = math.floor((vim.o.lines - win_height) / 2)
    local col = math.floor((vim.o.columns - win_width) / 2)
    
    -- Create buffer
    local buf = vim.api.nvim_create_buf(false, true)
    local loading_lines = {
        "",
        "           Loading GitHub Actions...           ",
        "",
        "  Fetching repositories and workflow runs...  ",
        "",
        "    This may take a few seconds...      ",
        "",
        "           Press q to close          "
    }
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, loading_lines)
    
    -- Set buffer options
    vim.api.nvim_buf_set_option(buf, 'modifiable', true)  -- Keep modifiable for spinner
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'pipeline')
    
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
    
    -- Set up spinner animation
    local timer = vim.loop.new_timer()
    timer:start(100, 100, vim.schedule_wrap(function()
        current_frame = (current_frame % #spinner_frames) + 1
        local spinner = spinner_frames[current_frame]
        
        -- Update the spinner line
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, {spinner .. " Loading GitHub Actions... " .. spinner})
    end))
    
    -- Set up keymaps
    local opts = { buffer = buf, silent = true }
    vim.keymap.set('n', 'q', '<cmd>close<cr>', opts)
    vim.keymap.set('n', '<Esc>', '<cmd>close<cr>', opts)
    
    return { buf = buf, win = win, timer = timer }
end

-- Main function to open the pipeline display with streaming updates
local function open_pipeline()
    -- Show loading window immediately
    local loading_window = show_loading_window()
    local main_window = nil
    
    -- Stream updates as they come in
    git.get_all_actions_streaming(function(results, error_msg)
        vim.schedule(function()
            if error_msg then
                -- Close loading window on error
                if loading_window.timer then
                    loading_window.timer:close()
                end
                if vim.api.nvim_win_is_valid(loading_window.win) then
                    vim.api.nvim_win_close(loading_window.win, true)
                end
                
                vim.notify("Pipeline Error: " .. error_msg, vim.log.levels.ERROR)
                return
            end
            
            local active_actions = results.active or {}
            local recent_actions = results.recent or {}
            
            -- If main window doesn't exist yet, create it
            if not main_window then
                -- Close loading window
                if loading_window.timer then
                    loading_window.timer:close()
                end
                if vim.api.nvim_win_is_valid(loading_window.win) then
                    vim.api.nvim_win_close(loading_window.win, true)
                end
                
                -- Create main display window
                local win_width = math.min(vim.o.columns - 4, 140)
                local win_height = math.min(vim.o.lines - 4, 40)
                
                local content = display.generate_display_content(
                    active_actions, 
                    recent_actions, 
                    win_width, 
                    win_height
                )
                
                main_window = display.create_floating_window(content)
                
            else
                -- Update existing window with new content
                display.update_window_content(main_window, active_actions, recent_actions)
            end
            
            -- Update window title to show progress
            if results.loading then
                display.update_window_title(main_window, " GitHub Actions Pipeline - Loading... ")
            else
                display.update_window_title(main_window, " GitHub Actions Pipeline ")
            end
        end)
    end, function(final_results, final_error)
        vim.schedule(function()
            -- Clean up any final loading state
            if main_window then
                display.update_window_title(main_window, " GitHub Actions Pipeline ")
            end
            
            if final_error then
                vim.notify("Pipeline Error: " .. final_error, vim.log.levels.ERROR)
                return
            end
        end)
    end)
end

-- Handle Pipeline subcommands
local function handle_pipeline_command(opts)
    local subcommand = opts.fargs[1] or ""

    if subcommand == "open" then
        open_pipeline()
    else
        vim.notify("Usage: :Pipeline open", vim.log.levels.WARN)
    end
end

-- Setup function
M.setup = function()
    vim.api.nvim_create_user_command('Pipeline', handle_pipeline_command, {
        nargs = '*',
        complete = function(ArgLead, CmdLine, CursorPos)
            return {'open'}
        end,
    })
end

return M
