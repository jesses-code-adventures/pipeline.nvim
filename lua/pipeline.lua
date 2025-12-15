local git = require('git')
local display = require('display')

local M = {}

-- Show error message (deferred to avoid fast event context issues)
local function show_error(msg)
    vim.schedule(function()
        vim.notify("Pipeline Error: " .. msg, vim.log.levels.ERROR)
    end)
end

-- Show loading message
local function show_loading()
    vim.notify("Loading GitHub Actions...", vim.log.levels.INFO)
end

-- Main function to open the pipeline display
local function open_pipeline()
    show_loading()

    git.get_all_actions(function(results, error_msg)
        vim.schedule(function()
            if error_msg then
                vim.notify("Pipeline Error: " .. error_msg, vim.log.levels.ERROR)
                return
            end

            local active_actions = results.active or {}
            local recent_actions = results.recent or {}

            -- Generate display content
            local win_width = math.min(vim.o.columns - 4, 120)
            local win_height = math.min(vim.o.lines - 4, 40)

            local content = display.generate_display_content(
                active_actions,
                recent_actions,
                win_width,
                win_height
            )

            -- Create and show floating window
            display.create_floating_window(content)
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
