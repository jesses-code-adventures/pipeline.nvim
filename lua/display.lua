local M = {}

-- Configuration for display
local config = {
	box_width = 80, -- Doubled from 40
	box_height = 6,
	margin = 2,
	active_border_color = "DiagnosticWarn", -- Yellow border for active actions
	completed_border_color = "Normal",
}

-- Create highlight groups
local function setup_highlights()
	-- Use explicit colors instead of theme
	vim.api.nvim_set_hl(0, "PipelineActiveBorder", { fg = "#f0c674" })        -- Yellow
	vim.api.nvim_set_hl(0, "PipelineCompletedBorder", { fg = "#808080" })     -- Gray
	vim.api.nvim_set_hl(0, "PipelineSuccess", { fg = "#00ff00" })             -- Green
	vim.api.nvim_set_hl(0, "PipelineFailure", { fg = "#ff0000" })             -- Red
	vim.api.nvim_set_hl(0, "PipelineCancelled", { fg = "#808080" })           -- Gray
	vim.api.nvim_set_hl(0, "PipelineInProgress", { fg = "#f0c674" })          -- Yellow
	vim.api.nvim_set_hl(0, "PipelineNormal", { link = "Normal" })             -- Use theme background
	vim.api.nvim_set_hl(0, "PipelineFloat", { link = "NormalFloat" })         -- Use theme float background
	vim.api.nvim_set_hl(0, "PipelineSelected", { fg = "#ffffff", bold = true }) -- White highlighted border
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

-- Create a double-line box border for selected action
local function create_double_box_border(width, height)
	local lines = {}

	-- Top double border
	lines[1] = "╔" .. string.rep("═", width - 2) .. "╗"

	-- Side double borders
	for i = 2, height - 1 do
		lines[i] = "║" .. string.rep(" ", width - 2) .. "║"
	end

	-- Bottom double border
	lines[height] = "╚" .. string.rep("═", width - 2) .. "╝"

	return lines, "PipelineSelected"
end

-- Format action content for display
local function format_action_content(action, width)
	local content_width = width - 4 -- Account for borders and padding
	local lines = {}

	-- Line 1: {repo} - {organisation/user} | {branch}
	local repo_parts = {}
	for part in string.gmatch(action.repository, "[^/]+") do
		table.insert(repo_parts, part)
	end
	local org_user = repo_parts[1] or ""
	local repo = repo_parts[2] or ""
	local branch_info = action:get_branch_info()
	local repo_line = string.format("%s - %s | %s", repo, org_user, branch_info)
	if string.len(repo_line) > content_width then
		repo_line = string.sub(repo_line, 1, content_width - 3) .. "..."
	end
	lines[1] = repo_line

	-- Line 2: empty
	lines[2] = ""

	-- Line 3: workflow name (duration)
	local workflow = action:get_display_name()
	local duration_str = action:get_duration_string()
	local workflow_line = string.format("%s (%s)", workflow, duration_str)
	if string.len(workflow_line) > content_width then
		workflow_line = string.sub(workflow_line, 1, content_width - 3) .. "..."
	end
	lines[3] = workflow_line

	-- Line 4: status text
	local status_text = action:get_status_text()
	if string.len(status_text) > content_width then
		status_text = string.sub(status_text, 1, content_width - 3) .. "..."
	end
	lines[4] = status_text

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
	local box_positions = {} -- Track box positions for navigation
	local current_line = 1

	-- Calculate horizontal centering offset
	local center_offset = math.max(0, math.floor((win_width - config.box_width) / 2))

	-- Helper function to add lines with optional centering
	local function add_lines(content_lines, hl_group, centered)
		for _, line in ipairs(content_lines) do
			if centered then
				local line_center_offset = math.max(0, math.floor((win_width - string.len(line)) / 2))
				line = string.rep(" ", line_center_offset) .. line
			end
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

	-- Helper function to add a centered box
	local function add_centered_box(action, box_index)
		local box = M.render_action_box(action)
		local box_start_line = current_line

		for j, box_line in ipairs(box.lines) do
			-- Center the box horizontally
			local centered_line = string.rep(" ", center_offset) .. box_line
			lines[current_line] = centered_line

			-- Add border highlight
			table.insert(highlights, {
				line = current_line - 1,
				col_start = center_offset,
				col_end = center_offset + string.len(box_line),
				hl_group = box.border_highlight
			})

			-- Add status highlighting for the status line (j=5, fourth content line)
			if j == 5 then
				local status_pos = center_offset + 2
				local status_text = action:get_status_text()
				table.insert(highlights, {
					line = current_line - 1,
					col_start = status_pos,
					col_end = status_pos + string.len(status_text),
					hl_group = action:get_status_color()
				})
			end

			current_line = current_line + 1
		end

		-- Record box position for navigation
		table.insert(box_positions, {
			action = action,
			start_line = box_start_line,
			end_line = current_line - 1,
			center_line = box_start_line + math.floor(config.box_height / 2),
			col_start = center_offset,
			col_end = center_offset + string.len(box.lines[1])
		})

		add_lines({ "" }) -- Spacing between boxes
	end

	-- Render active actions section
	if #active_actions > 0 then
		add_lines({ layout.active_section.title }, "PipelineInProgress", true)
		add_lines({ "" }) -- Spacing

		for i, action in ipairs(active_actions) do
			add_centered_box(action, i)
		end
	end

	-- Render recent actions section
	if #recent_actions > 0 then
		add_lines({ layout.recent_section.title }, "Normal", true)
		add_lines({ "" }) -- Spacing

		for i, action in ipairs(recent_actions) do
			add_centered_box(action, #active_actions + i)
		end
	end

	-- Add empty message if no actions
	if #active_actions == 0 and #recent_actions == 0 then
		add_lines({ "No GitHub Actions found.", "", "Make sure you're in a repository with GitHub Actions enabled." },
			"Comment", true)
	end

	return {
		lines = lines,
		highlights = highlights,
		layout = layout,
		box_positions = box_positions
	}
end

-- Create and configure floating window
function M.create_floating_window(content)
	-- Make window almost full width and height
	local win_width = math.min(vim.o.columns - 8, math.max(120, math.floor(vim.o.columns * 0.9)))
	local win_height = math.min(vim.o.lines - 4, math.max(20, math.floor(vim.o.lines * 0.9)))

	local row = math.floor((vim.o.lines - win_height) / 2)
	local col = math.floor((vim.o.columns - win_width) / 2)

	-- Store original cursor setting globally
	vim.g.pipeline_original_guicursor = vim.opt.guicursor:get()

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
		title = 'GitHub Actions Pipeline',
		title_pos = 'center',
	})

	-- Set window options to use theme background and hide cursor
	vim.api.nvim_win_set_option(win, 'winhighlight', 'Normal:PipelineNormal,NormalNC:PipelineNormal')
	vim.api.nvim_win_set_option(win, 'cursorline', false)
	vim.api.nvim_win_set_option(win, 'wrap', false)
	vim.api.nvim_win_set_option(win, 'cursorcolumn', false)
	vim.opt.guicursor = 'a:Normal/PipelineNormal'

	-- Box navigation state
	local current_box = 1
	local box_positions = content.box_positions or {}

	-- Function to restore original borders for all boxes
	local function restore_all_borders()
		vim.api.nvim_buf_set_option(buf, 'modifiable', true)
		local current_center_offset = math.max(0, math.floor((win_width - config.box_width) / 2))
		for i, box_pos in ipairs(box_positions) do
			local action = box_pos.action
			local box = M.render_action_box(action)
			
			for line_offset = 1, #box.lines do
				local actual_line = box_pos.start_line + line_offset - 1
				if actual_line <= box_pos.end_line then
					local restored_line = string.rep(" ", current_center_offset) .. box.lines[line_offset]
					vim.api.nvim_buf_set_lines(buf, actual_line - 1, actual_line, false, { restored_line })
					
					-- Re-apply original border highlights
					vim.api.nvim_buf_add_highlight(buf, -1, box.border_highlight, actual_line - 1, current_center_offset,
						current_center_offset + string.len(box.lines[line_offset]))
				end
			end
		end
		vim.api.nvim_buf_set_option(buf, 'modifiable', false)
	end

	-- Function to highlight a specific box
	local function highlight_box(box_index)
		if #box_positions == 0 then return end

		box_index = math.max(1, math.min(box_index, #box_positions))
		current_box = box_index

		-- Restore all borders first
		restore_all_borders()

		-- Clear all previous selections
		vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)

		-- Apply double-line border to selected box
		vim.api.nvim_buf_set_option(buf, 'modifiable', true)
		local box_pos = box_positions[box_index]
		local action = box_pos.action
		local double_border_lines = create_double_box_border(config.box_width, config.box_height)
		local current_center_offset = math.max(0, math.floor((win_width - config.box_width) / 2))
		
		for line_offset = 1, #double_border_lines do
			local actual_line = box_pos.start_line + line_offset - 1
			if actual_line <= box_pos.end_line then
				-- Create the double border line with content
				local line_content
				if line_offset == 1 or line_offset == #double_border_lines then
					-- Top or bottom border
					line_content = double_border_lines[line_offset]
				else
					-- Side borders with content
					local content_lines = format_action_content(action, config.box_width)
					local content_index = line_offset - 1
					
					if content_index <= #content_lines then
						local content = content_lines[content_index]
						local padded_content = content .. string.rep(" ", config.box_width - 4 - string.len(content))
						line_content = "║" .. padded_content .. "║"
					else
						line_content = double_border_lines[line_offset]
					end
				end
				
				local full_line = string.rep(" ", current_center_offset) .. line_content
				vim.api.nvim_buf_set_lines(buf, actual_line - 1, actual_line, false, { full_line })
				
				-- Add selection highlight for the border
				vim.api.nvim_buf_add_highlight(buf, -1, "PipelineSelected", actual_line - 1, current_center_offset,
					current_center_offset + config.box_width)
			end
		end
		vim.api.nvim_buf_set_option(buf, 'modifiable', false)

		-- Scroll window to keep selected box visible
		local win_height = vim.api.nvim_win_get_height(win)
		local center_line = box_pos.center_line
		local top_visible = vim.fn.line('w0')
		local bottom_visible = vim.fn.line('w$')

		-- Scroll up if selection is above visible area
		if center_line < top_visible + 2 then
			vim.api.nvim_win_set_cursor(win, { center_line - 2, 0 })
			-- Scroll down if selection is below visible area
		elseif center_line > bottom_visible - 2 then
			vim.api.nvim_win_set_cursor(win, { center_line + 2, 0 })
		end
	end

	-- Function to restore cursor on exit
	-- local function restore_cursor()
	-- 	vim.api.nvim_win_set_option(win, 'guicursor', '') -- Reset to default
	-- 	vim.cmd('close')
	-- end

	local function restore_cursor()
		-- Restore original cursor setting from global variable
		if vim.g.pipeline_original_guicursor and #vim.g.pipeline_original_guicursor > 0 then
			vim.opt.guicursor = vim.g.pipeline_original_guicursor
		else
			vim.opt.guicursor = ''
		end
		vim.api.nvim_win_set_option(win, 'cursorline', true)
		vim.api.nvim_win_set_option(win, 'cursorcolumn', false)
		-- Clear global variable
		vim.g.pipeline_original_guicursor = nil
		-- Clean up augroup
		pcall(vim.api.nvim_del_augroup_by_id, augroup)
	end

	-- Set up box navigation keymaps
	local opts = { buffer = buf, silent = true }

	-- Basic navigation
	vim.keymap.set('n', 'q', restore_cursor, opts)
	vim.keymap.set('n', '<Esc>', restore_cursor, opts)

	-- Box-based navigation
	vim.keymap.set('n', 'j', function()
		highlight_box(current_box + 1)
	end, opts)

	vim.keymap.set('n', 'k', function()
		highlight_box(current_box - 1)
	end, opts)

	vim.keymap.set('n', '<Down>', function()
		highlight_box(current_box + 1)
	end, opts)

	vim.keymap.set('n', '<Up>', function()
		highlight_box(current_box - 1)
	end, opts)

	-- Jump to first/last box
	vim.keymap.set('n', 'gg', function()
		highlight_box(1)
	end, opts)

	vim.keymap.set('n', 'G', function()
		highlight_box(#box_positions)
	end, opts)

	-- Open action URL (if available)
	vim.keymap.set('n', '<CR>', function()
		if #box_positions > 0 and current_box <= #box_positions then
			local action = box_positions[current_box].action
			if action.html_url and action.html_url ~= "" then
				vim.fn.system('open "' .. action.html_url .. '"')
				vim.notify("Opened: " .. action.html_url)
			else
				vim.notify("No URL available for this action")
			end
		end
	end, opts)

	-- Highlight first box if available
	if #box_positions > 0 then
		highlight_box(1)
	end

	-- Set up multiple autocmds to ensure cursor restoration
	local augroup = vim.api.nvim_create_augroup("PipelineWindow", { clear = false })

	-- Multiple triggers to ensure restoration
	vim.api.nvim_create_autocmd({ "WinClosed", "WinLeave", "BufLeave" }, {
		group = augroup,
		buffer = buf,
		callback = restore_cursor,
		once = true
	})

	-- Additional safety net
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = augroup,
		callback = function()
			vim.g.pipeline_original_guicursor = nil
		end,
		once = true
	})

	return { buf = buf, win = win, box_positions = box_positions }
end

-- Update existing window with new content
function M.update_window_content(window_info, active_actions, recent_actions)
	if not window_info or not window_info.buf or not vim.api.nvim_buf_is_valid(window_info.buf) then
		return
	end

	local win_width = vim.api.nvim_win_get_width(window_info.win)
	local win_height = vim.api.nvim_win_get_height(window_info.win)

	local content = M.generate_display_content(
		active_actions,
		recent_actions,
		win_width,
		win_height
	)

	-- Update buffer with new content
	vim.api.nvim_buf_set_option(window_info.buf, 'modifiable', true)
	vim.api.nvim_buf_set_lines(window_info.buf, 0, -1, false, content.lines)
	vim.api.nvim_buf_set_option(window_info.buf, 'modifiable', false)

	-- Re-apply highlights
	for _, hl in ipairs(content.highlights) do
		vim.api.nvim_buf_add_highlight(window_info.buf, -1, hl.hl_group, hl.line, hl.col_start, hl.col_end)
	end

	-- Re-highlight first box if available - use the new double border method
	if content.box_positions and #content.box_positions > 0 then
		-- Make buffer modifiable again for double border updates
		vim.api.nvim_buf_set_option(window_info.buf, 'modifiable', true)
		
		local current_center_offset = math.max(0, math.floor((win_width - config.box_width) / 2))
		local action = content.box_positions[1].action
		local double_border_lines = create_double_box_border(config.box_width, config.box_height)
		local box_pos = content.box_positions[1]
		
		for line_offset = 1, #double_border_lines do
			local actual_line = box_pos.start_line + line_offset - 1
			if actual_line <= box_pos.end_line then
				-- Create the double border line with content
				local line_content
				if line_offset == 1 or line_offset == #double_border_lines then
					line_content = double_border_lines[line_offset]
				else
					local content_lines = format_action_content(action, config.box_width)
					local content_index = line_offset - 1
					
					if content_index <= #content_lines then
						local content = content_lines[content_index]
						local padded_content = content .. string.rep(" ", config.box_width - 4 - string.len(content))
						line_content = "║" .. padded_content .. "║"
					else
						line_content = double_border_lines[line_offset]
					end
				end
				
				local full_line = string.rep(" ", current_center_offset) .. line_content
				vim.api.nvim_buf_set_lines(window_info.buf, actual_line - 1, actual_line, false, { full_line })
				
				-- Add selection highlight for the border
				vim.api.nvim_buf_add_highlight(window_info.buf, -1, "PipelineSelected", actual_line - 1, current_center_offset,
					current_center_offset + config.box_width)
			end
		end
		
		-- Set buffer back to not modifiable
		vim.api.nvim_buf_set_option(window_info.buf, 'modifiable', false)
	end
end

-- Update window title
function M.update_window_title(window_info, title)
	if not window_info or not window_info.win or not vim.api.nvim_win_is_valid(window_info.win) then
		return
	end

	local config = vim.api.nvim_win_get_config(window_info.win)
	if config.title ~= title then
		vim.api.nvim_win_set_config(window_info.win, {
			relative = 'editor',
			width = config.width,
			height = config.height,
			row = config.row,
			col = config.col,
			style = 'minimal',
			border = 'rounded',
			title = title,
			title_pos = 'center',
		})
	end
end

return M
