local Chat = require("harvgate.chat")
local async = require("plenary.async")
local utils = require("harvgate.utils")
local highlights = require("harvgate.highlights")
local state = require("harvgate.state")

local M = {}

local function goto_matching_line()
	local bufnr = state.chat_window.messages.bufnr
	local winid = state.chat_window.messages.winid

	local cursor_line = vim.api.nvim_win_get_cursor(winid)[1]
	local line_text = vim.api.nvim_buf_get_lines(bufnr, cursor_line - 1, cursor_line, false)[1]

	local source_lines = vim.api.nvim_buf_get_lines(state.source_buf, 0, -1, false)
	local source_winid = nil
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == state.source_buf then
			source_winid = win
			break
		end
	end

	if not source_winid then
		return
	end

	for i, line in ipairs(source_lines) do
		if line:match(line_text) then
			vim.api.nvim_set_current_win(source_winid)
			vim.api.nvim_win_set_cursor(0, { i, 0 })
			break
		end
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
		for i, line in ipairs(lines) do
			if line:match("^Claude:") then
				local label = state.icons.left_circle .. "  Claude: " .. state.icons.right_circle
				lines[i] = label .. line:sub(8) -- 8 to account for "Claude: "
			elseif line:match("^You:") then
				local label = state.icons.left_circle .. " You: " .. state.icons.right_circle
				lines[i] = label .. line:sub(5) -- 5 to account for "You: "
			end
		end
		if save_history then
			table.insert(state.message_history, text)
		end
		local buf_line_count = vim.api.nvim_buf_line_count(state.chat_window.messages.bufnr)
		local is_first_message = buf_line_count == 1
			and vim.api.nvim_buf_get_lines(state.chat_window.messages.bufnr, 0, 1, false)[1] == ""
		local start_line = is_first_message and 0 or buf_line_count
		-- If this is the first message and buffer has only an empty line
		if is_first_message then
			vim.api.nvim_buf_set_lines(state.chat_window.messages.bufnr, 0, 1, false, lines)
		else
			vim.api.nvim_buf_set_lines(state.chat_window.messages.bufnr, -1, -1, false, lines)
		end
		for i, line in ipairs(lines) do
			local line_num = start_line + i - 1
			local left_icon_length = #state.icons.left_circle
			local right_icon_length = #state.icons.right_circle
			if line:match(state.icons.left_circle .. "  Claude:") then
				local label_length = #"  Claude: "
				highlights.add_claude_highlights(
					state.hlns,
					state.chat_window.messages.bufnr,
					line_num,
					left_icon_length,
					label_length,
					right_icon_length
				)
			elseif line:match(state.icons.left_circle .. " You:") then
				local label_length = #" You: "

				highlights.add_user_highlights(
					state.hlns,
					state.chat_window.messages.bufnr,
					line_num,
					left_icon_length,
					label_length,
					right_icon_length
				)
			end
		end
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
		return state.config.icons.default_file
	end

	local extension = vim.fn.fnamemodify(filename, ":e")
	local file_icon, _ = require("nvim-web-devicons").get_icon(filename, extension, { default = true })
	return file_icon or state.config.icons.default_file
end

local update_winbar = function()
	if
		state.chat_window
		and state.chat_window.messages.winid
		and vim.api.nvim_win_is_valid(state.chat_window.messages.winid)
	then
		local zen_indicator = state.zen_mode and " [ZEN]" or ""
		local winbar_text = string.format(" %s Chat", state.config.icons.chat)

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
					table.insert(filenames, file_icon .. " " .. file_basename)
				end
			end

			if #filenames > 0 then
				winbar_text = string.format(
					" %s Chat%s: %s",
					state.config.icons.chat,
					zen_indicator,
					table.concat(filenames, ", ")
				)
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
		state.chat = Chat.new(state.session, nil, file_contents)
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

	-- Only update window if it exists
	if
		state.chat_window
		and state.chat_window.messages.bufnr
		and vim.api.nvim_buf_is_valid(state.chat_window.messages.bufnr)
	then
		window_append_text(user_message, false)
		window_append_text("Claude: *thinking...*", false)
	end

	async.util.sleep(100) -- Small delay to ensure UI updates

	-- Send message to Claude
	local response, error_msg = state.chat:send_message(state.chat_id, input_text)

	vim.schedule(function()
		if not response then
			local error_text = error_msg or "Unknown error"
			vim.notify("Error sending message: " .. error_text, vim.log.levels.ERROR)
		end

		-- Store Claude's response in history
		local claude_response = "Claude:" .. response

		-- Only update window if it exists and is valid
		if
			state.chat_window
			and state.chat_window.messages.bufnr
			and vim.api.nvim_buf_is_valid(state.chat_window.messages.bufnr)
		then
			-- Remove thinking message
			local last_line = vim.api.nvim_buf_line_count(state.chat_window.messages.bufnr)
			vim.api.nvim_buf_set_lines(state.chat_window.messages.bufnr, last_line - 1, last_line, false, {})
			-- Append actual response
			window_append_text(claude_response)
		else
			-- When window is closed, just store in history WITHOUT calling window_append_text
			table.insert(state.message_history, claude_response)
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
	state.chat = Chat.new(state.session, get_filename())
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
	local width = state.config.width or 60
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
	local height = state.config.height or 10
	vim.cmd(string.format("resize %d", height))

	-- Set window options for input
	vim.api.nvim_set_option_value("wrap", true, { win = input_win })
	vim.api.nvim_set_option_value("number", false, { win = input_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = input_win })
	local input_winbar = string.format("%s Message Input [Ctrl+S to send]", state.config.icons.input)
	vim.api.nvim_set_option_value("winbar", input_winbar, { win = input_win })

	-- Create wrapper objects that match nui.popup interface
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
			end
		end,
		focus_messages = function()
			if vim.api.nvim_win_is_valid(messages_win) then
				vim.api.nvim_set_current_win(messages_win)
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
	local highlight_info = {}

	-- Process all messages and prepare lines with proper labels and icons
	for i = state.last_displayed_message + 1, #state.message_history do
		local msg = state.message_history[i]
		local start_line = #all_lines
		local lines = vim.split(msg, "\n")

		for j, line in ipairs(lines) do
			local left_icon_length = #state.icons.left_circle
			local right_icon_length = #state.icons.right_circle

			if line:match("^Claude:") then
				local label = state.icons.left_circle .. "  Claude: " .. state.icons.right_circle
				local modified_line = label .. line:sub(8) -- 8 to account for "Claude: "
				table.insert(all_lines, modified_line)

				local line_num = start_line + j - 1
				local label_length = #"  Claude: "

				-- Store highlight information
				table.insert(highlight_info, {
					line_num = line_num,
					type = "claude",
					left_icon_length = left_icon_length,
					label_length = label_length,
					right_icon_length = right_icon_length,
				})
			elseif line:match("^You:") then
				local label = state.icons.left_circle .. " You: " .. state.icons.right_circle
				local modified_line = label .. line:sub(5) -- 5 to account for "You: "
				table.insert(all_lines, modified_line)

				local line_num = start_line + j - 1
				local label_length = #" You: "

				-- Store highlight information
				table.insert(highlight_info, {
					line_num = line_num,
					type = "user",
					left_icon_length = left_icon_length,
					label_length = label_length,
					right_icon_length = right_icon_length,
				})
			else
				table.insert(all_lines, line)
			end
		end
	end

	-- Set all lines at once
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, all_lines)

	-- Apply all highlights
	for _, hi in ipairs(highlight_info) do
		if hi.type == "claude" then
			highlights.add_claude_highlights(
				state.hlns,
				bufnr,
				hi.line_num,
				hi.left_icon_length,
				hi.label_length,
				hi.right_icon_length
			)
		else -- user
			highlights.add_user_highlights(
				state.hlns,
				bufnr,
				hi.line_num,
				hi.left_icon_length,
				hi.label_length,
				hi.right_icon_length
			)
		end
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
			window_restore_messages()
		end
		update_winbar()
	end
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

	local function send_input()
		local lines = vim.api.nvim_buf_get_lines(input_win.bufnr, 0, -1, false)
		local input_text = table.concat(lines, "\n")
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

		state.chat_window.layout:mount()
		state.is_visible = true
		update_winbar()
	end)()
end

M.list_chats = async.void(function(session)
	state.chat = Chat.new(session, nil)
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
		border = "rounded",
	}

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, win_config)
	local chat_id_list = {}

	for i, chat in ipairs(all_chats) do
		chat_id_list[i] = chat.uuid
		vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { chat.name })
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
					formatted_message = "Claude:" .. msg.text
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

---@param config Config
M.setup = function(config)
	state.config = config
	if state.config.width and (not utils.is_number(state.config.width) or state.config.width < 40) then
		vim.notify("Invalid width value should be at least 40, falling back to default", vim.log.levels.WARN)
	end
	if state.config.height and (not utils.is_number(state.config.height) or state.config.height > 20) then
		vim.notify("Invalid height value should be at most 20, falling back to default", vim.log.levels.WARN)
	end
	highlights.setup(config)
end

return M
