local async = require("plenary.async")
local utils = require("harvgate.utils")
local state = require("harvgate.state")

local function provider_label()
	return state.provider_label or "Assistant"
end

local function assistant_prefix()
	return " " .. provider_label()
end

local function create_chat(session, primary_file, additional_files)
	if not state.provider or not state.provider.new_chat then
		return nil, "Provider does not support chat conversations"
	end
	local ok, chat, err = pcall(state.provider.new_chat, session, primary_file, additional_files, state.provider_config)
	if not ok then
		return nil, chat
	end
	if not chat then
		return nil, err or "Failed to create chat"
	end
	return chat
end

local M = {}
local INPUT_HEIGHT_FOCUSED = 10 -- default, will be updated later
local INPUT_HEIGHT_UNFOCUSED = 3

-- Create namespace for highlights
local ns_id = vim.api.nvim_create_namespace("harvgate_highlights")

-- Define highlight groups for chat messages
local function setup_highlights()
	vim.api.nvim_set_hl(0, "HarvgateYouPrefix", { fg = "#61afef", bold = true })
	vim.api.nvim_set_hl(0, "HarvgateAssistantPrefix", { fg = "#d87658", bold = true })
end

-- Apply highlighting to message prefixes
local function apply_message_highlights(bufnr, start_line, text)
	local lines = vim.split(text, "\n")
	for i, line in ipairs(lines) do
		local line_num = start_line + i - 1
		if line:match("^You:") then
			vim.hl.range(bufnr, ns_id, "HarvgateYouPrefix", { line_num, 0 }, { line_num, 4 })
		elseif line:match("^" .. vim.pesc(assistant_prefix())) then
			local prefix = assistant_prefix()
			vim.hl.range(bufnr, ns_id, "HarvgateAssistantPrefix", { line_num, 0 }, { line_num, #prefix })
		end
	end
end

local function resize_input_window(height)
	if
		state.chat_window
		and state.chat_window.input.winid
		and vim.api.nvim_win_is_valid(state.chat_window.input.winid)
	then
		vim.api.nvim_win_set_height(state.chat_window.input.winid, height)
	end
end

local setup_window_focus_autocmd = function()
	if not state.chat_window then
		return
	end

	vim.api.nvim_create_autocmd("WinEnter", {
		buffer = state.chat_window.input.bufnr,
		callback = function()
			resize_input_window(INPUT_HEIGHT_FOCUSED)
		end,
	})

	vim.api.nvim_create_autocmd("WinEnter", {
		buffer = state.chat_window.messages.bufnr,
		callback = function()
			resize_input_window(INPUT_HEIGHT_UNFOCUSED)
		end,
	})
end

local function goto_matching_line()
	local bufnr = state.chat_window.messages.bufnr
	local winid = state.chat_window.messages.winid

	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		vim.notify("No active chat window", vim.log.levels.ERROR)
		return
	end

	-- Get the line under cursor in the chat window
	local cursor_pos = vim.api.nvim_win_get_cursor(winid)
	if not cursor_pos then
		vim.notify("No cursor position found", vim.log.levels.ERROR)
		return
	end
	local cursor_line = cursor_pos[1]
	local line_text = vim.api.nvim_buf_get_lines(bufnr, cursor_line - 1, cursor_line, false)[1]

	if not line_text then
		vim.notify("No line text found", vim.log.levels.ERROR)
		return
	end

	-- Find the source window/buffer
	local source_buf
	local source_winid

	-- First try to use the source buffer if set
	if state.source_buf and vim.api.nvim_buf_is_valid(state.source_buf) then
		source_buf = state.source_buf
		-- Find window displaying the source buffer
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(win) == source_buf then
				source_winid = win
				break
			end
		end
	end

	-- If no source buffer/window found yet, try to find any non-chat window
	if not source_winid then
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			local win_buf = vim.api.nvim_win_get_buf(win)
			if win_buf ~= bufnr and win_buf ~= state.chat_window.input.bufnr then
				source_winid = win
				source_buf = win_buf
				break
			end
		end
	end

	if not source_winid or not source_buf then
		vim.notify("No source window found", vim.log.levels.ERROR)
		return
	end

	-- Get all lines from the source buffer
	local source_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
	if #source_lines == 0 then
		vim.notify("Source buffer is empty", vim.log.levels.ERROR)
		return
	end

	-- Trim text
	local clean_line_text = vim.trim(line_text)

	-- Look for a match in the source buffer
	local match_found = false
	for i, line in ipairs(source_lines) do
		-- Try exact match first
		if line == clean_line_text then
			vim.api.nvim_set_current_win(source_winid)
			vim.api.nvim_win_set_cursor(source_winid, { i, 0 })
			match_found = true
			break
		end
	end

	-- If no exact match, try partial match
	if not match_found and #clean_line_text > 0 then
		local pattern = vim.pesc(clean_line_text)
		for i, line in ipairs(source_lines) do
			if line:match(pattern) then
				vim.api.nvim_set_current_win(source_winid)
				vim.api.nvim_win_set_cursor(source_winid, { i, 0 })
				match_found = true
				break
			end
		end
	end

	if not match_found then
		vim.notify("No matching line found in source buffer", vim.log.levels.WARN)
	end
end

local function copy_code()
	local bufnr = state.chat_window.messages.bufnr
	local winid = state.chat_window.messages.winid

	-- Early return if invalid buffer/window
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		vim.notify("No active chat window", vim.log.levels.ERROR)
		return
	end

	local cursor_line = vim.api.nvim_win_get_cursor(winid)[1]

	-- Use a limited range of lines for efficiency instead of reading entire buffer
	local search_range = 1000 -- Adjust based on your typical code block size
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	local start_search = math.max(1, cursor_line - search_range)
	local end_search = math.min(line_count, cursor_line + search_range)

	local lines = vim.api.nvim_buf_get_lines(bufnr, start_search - 1, end_search, false)
	local cursor_offset = cursor_line - start_search + 1

	-- Find code block boundaries
	local start_idx, end_idx = nil, nil

	-- Look backward for start of code block
	for i = cursor_offset, 1, -1 do
		if lines[i] and lines[i]:match("^```") then
			start_idx = i
			break
		end
	end

	-- Early return if no start marker found
	if not start_idx then
		vim.notify("No code block found at cursor position", vim.log.levels.WARN)
		return
	end

	-- Look forward for end of code block
	for i = math.max(start_idx + 1, cursor_offset), #lines do
		if lines[i] and lines[i]:match("^```") then
			end_idx = i
			break
		end
	end

	-- If we found both boundaries
	if start_idx and end_idx then
		local code_content = table.concat(vim.list_slice(lines, start_idx + 1, end_idx - 1), "\n")
		vim.fn.setreg("+", code_content) -- System clipboard
		vim.fn.setreg('"', code_content) -- Unnamed register
		vim.notify("Code block copied to clipboard", vim.log.levels.INFO)
	else
		vim.notify("No complete code block found at cursor position", vim.log.levels.WARN)
	end
end

---@param text string Text to append
---@param save_history boolean? Save to history (default: true)
local window_append_text = function(text, save_history)
	save_history = save_history ~= false
	if state.chat_window and state.chat_window.messages.bufnr then
		local lines = vim.split(text, "\n")
		if save_history then
			table.insert(state.message_history, text)
		end
		local buf_line_count = vim.api.nvim_buf_line_count(state.chat_window.messages.bufnr)
		local is_first_message = buf_line_count == 1
			and vim.api.nvim_buf_get_lines(state.chat_window.messages.bufnr, 0, 1, false)[1] == ""
		local start_line
		if is_first_message then
			vim.api.nvim_buf_set_lines(state.chat_window.messages.bufnr, 0, 1, false, lines)
			start_line = 0
		else
			vim.api.nvim_buf_set_lines(state.chat_window.messages.bufnr, -1, -1, false, lines)
			start_line = buf_line_count
		end
		-- Apply highlighting to message prefixes
		apply_message_highlights(state.chat_window.messages.bufnr, start_line, text)
		-- Scroll to bottom
		local line_count = vim.api.nvim_buf_line_count(state.chat_window.messages.bufnr)
		vim.api.nvim_win_set_cursor(state.chat_window.messages.winid, { line_count, 0 })
	end
end

local get_filename = function()
	if state.source_buf and vim.api.nvim_buf_is_valid(state.source_buf) then
		return vim.api.nvim_buf_get_name(state.source_buf)
	end
	return nil
end

local function get_file_icon(filename)
	if not filename then
		return ""
	end

	local extension = vim.fn.fnamemodify(filename, ":e")
	local file_icon, _ = require("nvim-web-devicons").get_icon(filename, extension, { default = true })
	return file_icon or ""
end

local update_winbar = function()
	if
		state.chat_window
		and state.chat_window.messages.winid
		and vim.api.nvim_win_is_valid(state.chat_window.messages.winid)
	then
		local zen_indicator = state.zen_mode and " [ZEN]" or ""
		local base_label = string.format("%s Chat%s", provider_label(), zen_indicator)
		local winbar_text = base_label

		-- Check if we have any context buffers
		if #state.context_buffers > 0 then
			local filenames = {}
			for _, bufnr in ipairs(state.context_buffers) do
				if vim.api.nvim_buf_is_valid(bufnr) then
					local filename = vim.api.nvim_buf_get_name(bufnr)
					local file_basename = vim.fn.fnamemodify(filename, ":t")
					if file_basename == "" then
						file_basename = "[Buffer " .. bufnr .. "]"
					end
					local file_icon = get_file_icon(filename)
					if file_icon ~= "" then
						table.insert(filenames, file_icon .. " " .. file_basename)
					else
						table.insert(filenames, file_basename)
					end
				end
			end

			if #filenames > 0 then
				winbar_text = string.format("%s: %s", base_label, table.concat(filenames, ", "))
			end
		end

		vim.api.nvim_set_option_value("winbar", winbar_text, { win = state.chat_window.messages.winid })
	end
end

---@param input_text string Message to send
local chat_send_message = async.void(function(input_text)
	-- Get content from all context buffers
	local file_contents = {}
	for _, bufnr in ipairs(state.context_buffers) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			local filename = vim.api.nvim_buf_get_name(bufnr)
			local file_basename = vim.fn.fnamemodify(filename, ":t")
			if file_basename == "" then
				file_basename = "[Buffer " .. bufnr .. "]"
			end
			file_contents[file_basename] = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
		end
	end

	if not state.chat then
		local chat_instance, err = create_chat(state.session, nil, file_contents)
		if not chat_instance then
			vim.notify(err or "Failed to initialize chat", vim.log.levels.ERROR)
			return
		end
		state.chat = chat_instance
		state.chat_id = state.chat:create_chat()
		if not state.chat_id then
			vim.notify("Failed to create chat conversation", vim.log.levels.ERROR)
			return
		end
	else
		-- Update context for existing chat - merge with existing context
		state.chat:update_context(file_contents, true)
	end

	-- Store the user message in history
	local trimmed_message = utils.trim_message(input_text)
	local user_message = "\nYou: " .. trimmed_message .. "\n"
	table.insert(state.message_history, user_message)

	-- Update UI to show user message and thinking indicator
	if
		state.chat_window
		and state.chat_window.messages.bufnr
		and vim.api.nvim_buf_is_valid(state.chat_window.messages.bufnr)
	then
		window_append_text(user_message, false)
		window_append_text(string.format("%s: *thinking...*", provider_label()), false)
	end

	async.util.sleep(100) -- Small delay to ensure UI updates

	-- Send message to the active provider
	local response, error_msg = state.chat:send_message(state.chat_id, input_text)

	vim.schedule(function()
		-- Remove thinking message regardless of response success
		if
			state.chat_window
			and state.chat_window.messages.bufnr
			and vim.api.nvim_buf_is_valid(state.chat_window.messages.bufnr)
		then
			local last_line = vim.api.nvim_buf_line_count(state.chat_window.messages.bufnr)
			vim.api.nvim_buf_set_lines(state.chat_window.messages.bufnr, last_line - 1, last_line, false, {})
		end

		if not response then
			-- Enhanced error handling
			local error_text = error_msg
				or string.format("Unknown error occurred while communicating with %s", provider_label())

			-- Show user-friendly error message in chat window
			local error_message = string.format("%s: *Error: ", provider_label())
				.. error_text
				.. "*\n"
				.. "Please check your connection and try again."

			if
				state.chat_window
				and state.chat_window.messages.bufnr
				and vim.api.nvim_buf_is_valid(state.chat_window.messages.bufnr)
			then
				window_append_text(error_message)
			else
				-- Store error in history even if window is closed
				table.insert(state.message_history, error_message)
			end

			-- Show notification
			vim.notify("Error sending message: " .. error_text, vim.log.levels.ERROR)
			return
		end

		-- Process successful response (existing code)
		local assistant_response = assistant_prefix() .. ":" .. response

		if
			state.chat_window
			and state.chat_window.messages.bufnr
			and vim.api.nvim_buf_is_valid(state.chat_window.messages.bufnr)
		then
			window_append_text(assistant_response)
		else
			table.insert(state.message_history, assistant_response)
			vim.notify("Chat response received and stored. Reopen chat to view.", vim.log.levels.INFO)
		end
	end)
end)

---Close chat window
local window_close = function()
	state.chat_window.layout:unmount()
	state.chat_window = nil
	state.is_visible = false
	state.zen_mode = false
	state.last_displayed_message = 0
end

---Start new conversation
local chat_new_conversation = async.void(function()
	if not state.session then
		vim.notify("No active session", vim.log.levels.ERROR)
		return
	end

	-- Clear source_buf
	state.source_buf = nil
	state.context_buffers = {}

	-- Close and reopen the window to get fresh buffer context
	window_close()
	M.window_toggle(state.session)

	-- Clear message history
	state.message_history = {}
	state.conversation_started = false

	-- Create new chat
	local chat_instance, err = create_chat(state.session, get_filename())
	if not chat_instance then
		vim.notify(err or "Failed to initialize chat", vim.log.levels.ERROR)
		return
	end
	state.chat = chat_instance
	state.chat_id = state.chat:create_chat()

	if not state.chat_id then
		vim.notify("Failed to create new chat conversation", vim.log.levels.ERROR)
		return
	end

	-- Clear the messages window
	if state.chat_window and state.chat_window.messages.bufnr then
		vim.api.nvim_buf_set_lines(state.chat_window.messages.bufnr, 0, -1, false, {})
	end

	vim.notify("Started new conversation", vim.log.levels.INFO)
end)

local create_split_layout = function()
	-- Setup highlight groups
	setup_highlights()

	local width = state.config.width
	vim.cmd(string.format("vsplit"))
	vim.cmd(string.format("vertical resize %d", width))
	local messages_win = vim.api.nvim_get_current_win()
	local messages_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(messages_win, messages_buf)

	-- Set buffer options for messages
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = messages_buf })
	vim.api.nvim_set_option_value("modifiable", true, { buf = messages_buf })
	vim.api.nvim_set_option_value("wrap", true, { win = messages_win })
	vim.api.nvim_set_option_value("cursorline", true, { win = messages_win })
	vim.api.nvim_set_option_value("number", false, { win = messages_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = messages_win })

	vim.cmd("split")
	local input_win = vim.api.nvim_get_current_win()
	local input_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(input_win, input_buf)

	-- Store the configured heights
	INPUT_HEIGHT_FOCUSED = (state.config and state.config.height) or 10
	INPUT_HEIGHT_UNFOCUSED = 3

	vim.cmd(string.format("resize %d", INPUT_HEIGHT_UNFOCUSED)) -- Start with unfocused size

	-- Set window options for input
	vim.api.nvim_set_option_value("wrap", true, { win = input_win })
	vim.api.nvim_set_option_value("number", false, { win = input_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = input_win })
	local input_winbar = "Message Input [Ctrl+S to send]"
	vim.api.nvim_set_option_value("winbar", input_winbar, { win = input_win })

	local messages = {
		bufnr = messages_buf,
		winid = messages_win,
		map = function(_, mode, key, fn, opts)
			vim.keymap.set(mode, key, fn, vim.tbl_extend("force", opts or {}, { buffer = messages_buf }))
		end,
	}

	local input = {
		bufnr = input_buf,
		winid = input_win,
		map = function(_, mode, key, fn, opts)
			vim.keymap.set(mode, key, fn, vim.tbl_extend("force", opts or {}, { buffer = input_buf }))
		end,
	}

	return {
		messages = messages,
		input = input,
		layout = {
			unmount = function()
				if vim.api.nvim_win_is_valid(input_win) then
					pcall(vim.api.nvim_win_close, input_win, true)
				end
				if vim.api.nvim_win_is_valid(messages_win) then
					pcall(vim.api.nvim_win_close, messages_win, true)
				end
			end,
			mount = function() end,
		},
		focus_input = function()
			if vim.api.nvim_win_is_valid(input_win) then
				vim.api.nvim_set_current_win(input_win)
				resize_input_window(INPUT_HEIGHT_FOCUSED) -- Expand when focused
			end
		end,
		focus_messages = function()
			if vim.api.nvim_win_is_valid(messages_win) then
				vim.api.nvim_set_current_win(messages_win)
				resize_input_window(INPUT_HEIGHT_UNFOCUSED) -- Shrink when messages focused
			end
		end,
	}
end

---Restore message history
local window_restore_messages = function()
	if not (state.chat_window and state.chat_window.messages.bufnr) then
		return
	end

	update_winbar()

	local bufnr = state.chat_window.messages.bufnr
	local all_lines = {}

	-- Process all messages and prepare lines
	for i = state.last_displayed_message + 1, #state.message_history do
		local msg = state.message_history[i]
		local lines = vim.split(msg, "\n")
		for _, line in ipairs(lines) do
			table.insert(all_lines, line)
		end
	end

	-- Set all lines at once
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, all_lines)

	-- Apply highlighting to all restored messages
	local line_offset = 0
	for i = state.last_displayed_message + 1, #state.message_history do
		local msg = state.message_history[i]
		apply_message_highlights(bufnr, line_offset, msg)
		local msg_lines = vim.split(msg, "\n")
		line_offset = line_offset + #msg_lines
	end

	state.last_displayed_message = #state.message_history

	-- Restore input history if exists
	if #state.input_history > 0 then
		vim.api.nvim_buf_set_lines(
			state.chat_window.input.bufnr,
			0,
			-1,
			false,
			state.input_history[#state.input_history]
		)
	end

	-- Scroll to bottom
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	vim.api.nvim_win_set_cursor(state.chat_window.messages.winid, { line_count, 0 })
end

local function toggle_zen_mode()
	state.zen_mode = not state.zen_mode

	if state.chat_window and state.chat_window.messages.bufnr then
		local bufnr = state.chat_window.messages.bufnr
		local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

		if state.zen_mode then
			-- Extract only code blocks
			local zen_lines = {}
			local in_code_block = false

			for _, line in ipairs(all_lines) do
				if line:match("^```") then
					in_code_block = not in_code_block
					table.insert(zen_lines, line)
				elseif in_code_block then
					table.insert(zen_lines, line)
				end
			end

			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, zen_lines)
		else
			-- Restore full chat history
			state.last_displayed_message = 0
			window_restore_messages()
		end
		update_winbar()
	end
end

local function open_completion_opts(bufnr)
	local items = {
		{ word = "#codebase" },
	}
	vim.bo[bufnr].omnifunc = "v:lua.HarvgateCompletion"
	_G.HarvgateCompletion = function(findstart, base)
		if findstart == 1 then
			-- Find start of the word
			local line = vim.api.nvim_get_current_line()
			local col = vim.api.nvim_win_get_cursor(0)[2]
			local start = col
			while start > 0 and line:sub(start, start):match("[%w#]") do
				start = start - 1
			end
			return start
		else
			-- Find matching items
			local results = {}
			base = base or ""
			for _, item in ipairs(items) do
				if vim.startswith(item.word, base) then
					table.insert(results, item)
				end
			end
			return results
		end
	end
end

local add_codebase = function()
	vim.notify("Adding codebase", vim.log.levels.INFO)
end

local setup_input_keymaps = function(input_win)
	utils.buffer_autocmd(input_win.bufnr, window_close)
	local keymaps = state.config.keymaps or {}
	local new_chat = async.void(function()
		chat_new_conversation()
	end)
	input_win:map("n", "<C-k>", state.chat_window.focus_messages, { noremap = true })
	input_win:map("n", "<Esc>", window_close, { noremap = true })
	input_win:map("n", "q", window_close, { noremap = true })
	input_win:map("n", keymaps.new_chat or "<C-g>", new_chat, { noremap = true })
	input_win:map("i", keymaps.new_chat or "<C-g>", new_chat, { noremap = true })
	input_win:map("n", keymaps.toggle_zen_mode, toggle_zen_mode, { noremap = true })

	input_win:map("i", "#", function()
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("#", true, false, true), "n", false)
		vim.schedule(function()
			open_completion_opts(input_win.bufnr)
			vim.api.nvim_command('call feedkeys("\\<C-x>\\<C-o>")')
		end)
	end, { noremap = true })

	local function send_input()
		local lines = vim.api.nvim_buf_get_lines(input_win.bufnr, 0, -1, false)
		local input_text = table.concat(lines, "\n")

		if input_text:match("#codebase") then
			add_codebase()
		end

		vim.api.nvim_buf_set_lines(input_win.bufnr, 0, -1, false, { "" })
		async.run(function()
			chat_send_message(input_text)
		end, function() end)
	end

	input_win:map("n", "<C-s>", function()
		async.run(function()
			send_input()
		end, function() end)
	end, { noremap = true })
	input_win:map("i", "<C-s>", function()
		async.run(function()
			send_input()
		end, function() end)
	end, { noremap = true })
end

local setup_messages_keymaps = function(messages_win)
	utils.buffer_autocmd(messages_win.bufnr, window_close)
	local keymaps = state.config.keymaps or {}
	local new_chat = async.void(function()
		chat_new_conversation()
	end)
	messages_win:map("n", "<C-j>", state.chat_window.focus_input, { noremap = true })
	messages_win:map("n", "<Esc>", window_close, { noremap = true })
	messages_win:map("n", "q", window_close, { noremap = true })
	messages_win:map("n", keymaps.new_chat or "<C-g>", new_chat, { noremap = true })
	messages_win:map("i", keymaps.new_chat or "<C-g>", new_chat, { noremap = true })
	messages_win:map("n", keymaps.toggle_zen_mode, toggle_zen_mode, { noremap = true })
	messages_win:map("n", keymaps.copy_code or "<C-y>", copy_code, { noremap = true })
	messages_win:map("n", keymaps.goto_line or "<C-f>", goto_matching_line, { noremap = true })
end

---@param session any Chat session
M.window_toggle = function(session)
	async.void(function()
		state.session = session
		if state.is_visible and state.chat_window then
			return window_close()
		end

		local current_buf = vim.api.nvim_get_current_buf()

		-- Add current buffer to context if not already there
		if #state.context_buffers == 0 then
			M.add_buffer_to_context(current_buf)
		end

		-- Always use the first context buffer as source
		state.source_buf = state.context_buffers[1]

		state.zen_mode = false
		state.chat_window = create_split_layout()
		window_restore_messages()
		setup_input_keymaps(state.chat_window.input)
		setup_messages_keymaps(state.chat_window.messages)
		setup_window_focus_autocmd()

		state.chat_window.layout:mount()
		state.is_visible = true
		update_winbar()

		-- Focus and expand the input window by default
		state.chat_window.focus_input()
	end)()
end

M.list_chats = async.void(function(session)
	if state.provider and state.provider.supports_list_chats and not state.provider.supports_list_chats() then
		vim.notify("Current provider does not support listing chats", vim.log.levels.WARN)
		return
	end

	local chat_instance, init_err = create_chat(session, nil)
	if not chat_instance then
		vim.notify(init_err or "Failed to initialize chat", vim.log.levels.ERROR)
		return
	end

	state.chat = chat_instance
	local all_chats, err = state.chat:get_all_chats()

	if err then
		vim.notify(err, vim.log.levels.ERROR)
		return
	end

	local width = 50
	local height = 25
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local win_config = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
	}

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, win_config)
	local chat_id_list = {}

	for i, chat in ipairs(all_chats) do
		chat_id_list[i] = chat.uuid
		local chat_name = chat.name:gsub("\n", " ")
		vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { chat_name })
	end

	local load_selected_chat = function()
		async.run(function()
			local selected_line = vim.api.nvim_win_get_cursor(win)
			state.chat_id = chat_id_list[selected_line[1]]
			local chat_data, chat_err = state.chat:get_single_chat(state.chat_id)

			if chat_err then
				vim.notify("Failed to load chat: " .. chat_err, vim.log.levels.ERROR)
				return
			end

			vim.api.nvim_win_close(win, true)

			-- get the first chat message attachment filename
			local filename = utils.safe_get(chat_data, {
				chat_messages = {
					attachments = {
						file_name = true,
					},
				},
			}, "")

			state.message_history = {}
			state.last_displayed_message = 0

			for _, msg in ipairs(chat_data.chat_messages) do
				local formatted_message
				if msg.sender == "human" then
					formatted_message = "\nYou: " .. msg.text .. "\n"
				elseif msg.sender == "assistant" then
					formatted_message = assistant_prefix() .. ":" .. msg.text
				end

				if formatted_message then
					table.insert(state.message_history, formatted_message)
				end
			end

			if not state.is_visible or not state.chat_window then
				M.window_toggle(state.session)
				state.source_buf = nil
			else
				window_restore_messages()
			end

			if filename ~= "" then
				vim.api.nvim_set_option_value(
					"winbar",
					"󱐏 Chat - " .. " " .. filename,
					{ win = state.chat_window.messages.winid }
				)
			end

			vim.notify("Loaded chat: " .. chat_data.name, vim.log.levels.INFO)
		end, function() end)
	end

	vim.keymap.set("n", "<CR>", load_selected_chat, { buffer = buf })
	vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf })
end)

M.add_buffer_to_context = function(bufnr)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		vim.notify("Invalid buffer", vim.log.levels.ERROR)
		return false
	end

	-- Check if buffer is already in context
	for _, buf in ipairs(state.context_buffers) do
		if buf == bufnr then
			vim.notify("Buffer already in chat context", vim.log.levels.WARN)
			return false
		end
	end

	-- Add buffer to context
	table.insert(state.context_buffers, bufnr)

	-- Get buffer name for notification
	local filename = vim.api.nvim_buf_get_name(bufnr)
	local file_basename = vim.fn.fnamemodify(filename, ":t")
	if file_basename == "" then
		file_basename = "[No Name]"
	end

	-- Update any open chat window
	if state.is_visible and state.chat_window then
		update_winbar()
	end

	if state.chat then
		-- Get content from the newly added buffer only
		local file_contents = {}
		if vim.api.nvim_buf_is_valid(bufnr) then
			local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
			file_contents[file_basename] = content

			-- Update the chat context with just the new file, merging with existing
			state.chat:update_context(file_contents, true)

			vim.notify(
				"Added buffer: " .. file_basename .. " to chat context and updated active chat",
				vim.log.levels.INFO
			)
		end
	else
		vim.notify("Added buffer: " .. file_basename .. " to chat context", vim.log.levels.INFO)
	end

	return true
end

-- Remove a buffer from the context
M.remove_buffer_from_context = function(bufnr)
	for i, buf in ipairs(state.context_buffers) do
		if buf == bufnr then
			table.remove(state.context_buffers, i)

			-- Get buffer name for notification
			local filename = vim.api.nvim_buf_get_name(bufnr)
			local file_basename = vim.fn.fnamemodify(filename, ":t")
			if file_basename == "" then
				file_basename = "[No Name]"
			end

			-- Update any open chat window
			if state.is_visible and state.chat_window then
				update_winbar()
			end

			vim.notify("Removed buffer: " .. file_basename .. " from chat context", vim.log.levels.INFO)
			return true
		end
	end

	vim.notify("Buffer not found in chat context", vim.log.levels.WARN)
	return false
end

-- List buffers in context
M.list_context_buffers = function()
	if #state.context_buffers == 0 then
		vim.notify("No buffers in chat context", vim.log.levels.INFO)
		return
	end

	local buffer_list = {}
	for i, bufnr in ipairs(state.context_buffers) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			local filename = vim.api.nvim_buf_get_name(bufnr)
			local file_basename = vim.fn.fnamemodify(filename, ":t")
			if file_basename == "" then
				file_basename = "[No Name]"
			end
			table.insert(buffer_list, string.format("%d: %s", i, file_basename))
		else
			table.insert(buffer_list, string.format("%d: [Invalid Buffer]", i))
		end
	end

	vim.api.nvim_echo({ { "\nBuffers in chat context:\n", "Title" } }, false, {})
	for _, msg in ipairs(buffer_list) do
		vim.api.nvim_echo({ { msg .. "\n", "Normal" } }, false, {})
	end
end

M.setup = function(config)
	state.config = config
	if not state.config.width then
		state.config.width = 70
	end
	if not state.config.height then
		state.config.height = 10
	end
	if not utils.is_number(state.config.width) or state.config.width < 40 then
		state.config.width = 70
		vim.notify("Invalid width value should be at least 40, falling back to default", vim.log.levels.WARN)
	end
	if not utils.is_number(state.config.height) or state.config.height > 20 then
		state.config.height = 10
		vim.notify("Invalid height value should be at most 20, falling back to default", vim.log.levels.WARN)
	end
end

return M
