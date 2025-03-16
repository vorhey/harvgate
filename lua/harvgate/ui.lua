local Chat = require("harvgate.chat")
local async = require("plenary.async")
local utils = require("harvgate.utils")
local highlights = require("harvgate.highlights")

local M = {}

-- Store the chat instance and current conversation
M.config = nil
M.session = nil
M.chat_window = nil
M.chat = nil
M.chat_id = nil
M.is_chat_visible = nil
M.message_history = {}
M.input_history = {}
M.source_buf = nil
M.zen_mode = false
M.last_displayed_message = 0
M.context_buffers = {}

local hlns = vim.api.nvim_create_namespace("chat highlights")

local icons = {
	left_circle = "",
	right_circle = "",
}

local function goto_matching_line()
	local bufnr = M.chat_window.messages.bufnr
	local winid = M.chat_window.messages.winid

	local cursor_line = vim.api.nvim_win_get_cursor(winid)[1]
	local line_text = vim.api.nvim_buf_get_lines(bufnr, cursor_line - 1, cursor_line, false)[1]

	local source_lines = vim.api.nvim_buf_get_lines(M.source_buf, 0, -1, false)
	local source_winid = nil
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == M.source_buf then
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
	local bufnr = M.chat_window.messages.bufnr
	local winid = M.chat_window.messages.winid

	-- Early return if invalid buffer/window
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		vim.notify("No active chat window", vim.log.levels.ERROR)
		return
	end

	local cursor_line = vim.api.nvim_win_get_cursor(winid)[1]

	-- Use a limited range of lines for efficiency instead of reading entire buffer
	local search_range = 100 -- Adjust based on your typical code block size
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
	if M.chat_window and M.chat_window.messages.bufnr then
		local lines = vim.split(text, "\n")
		for i, line in ipairs(lines) do
			if line:match("^Claude:") then
				local label = icons.left_circle .. "  Claude: " .. icons.right_circle
				lines[i] = label .. line:sub(8) -- 8 to account for "Claude: "
			elseif line:match("^You:") then
				local label = icons.left_circle .. " You: " .. icons.right_circle
				lines[i] = label .. line:sub(5) -- 5 to account for "You: "
			end
		end
		if save_history then
			table.insert(M.message_history, text)
		end
		local buf_line_count = vim.api.nvim_buf_line_count(M.chat_window.messages.bufnr)
		local is_first_message = buf_line_count == 1
			and vim.api.nvim_buf_get_lines(M.chat_window.messages.bufnr, 0, 1, false)[1] == ""
		local start_line = is_first_message and 0 or buf_line_count
		-- If this is the first message and buffer has only an empty line
		if is_first_message then
			vim.api.nvim_buf_set_lines(M.chat_window.messages.bufnr, 0, 1, false, lines)
		else
			vim.api.nvim_buf_set_lines(M.chat_window.messages.bufnr, -1, -1, false, lines)
		end
		for i, line in ipairs(lines) do
			local line_num = start_line + i - 1
			local left_icon_length = #icons.left_circle
			local right_icon_length = #icons.right_circle
			if line:match(icons.left_circle .. "  Claude:") then
				local label_length = #"  Claude: "
				highlights.add_claude_highlights(
					hlns,
					M.chat_window.messages.bufnr,
					line_num,
					left_icon_length,
					label_length,
					right_icon_length
				)
			elseif line:match(icons.left_circle .. " You:") then
				local label_length = #" You: "

				highlights.add_user_highlights(
					hlns,
					M.chat_window.messages.bufnr,
					line_num,
					left_icon_length,
					label_length,
					right_icon_length
				)
			end
		end
		-- Scroll to bottom
		local line_count = vim.api.nvim_buf_line_count(M.chat_window.messages.bufnr)
		vim.api.nvim_win_set_cursor(M.chat_window.messages.winid, { line_count, 0 })
	end
end

local get_filename = function()
	if M.source_buf and vim.api.nvim_buf_is_valid(M.source_buf) then
		return vim.api.nvim_buf_get_name(M.source_buf)
	end
	return nil
end

local function get_file_icon(filename)
	if not filename then
		return M.config.icons.default_file
	end

	local extension = vim.fn.fnamemodify(filename, ":e")
	local file_icon, _ = require("nvim-web-devicons").get_icon(filename, extension, { default = true })
	return file_icon or M.config.icons.default_file
end

local update_winbar = function()
	if M.chat_window and M.chat_window.messages.winid and vim.api.nvim_win_is_valid(M.chat_window.messages.winid) then
		local zen_indicator = M.zen_mode and " [ZEN]" or ""
		local winbar_text = string.format(" %s Chat", M.config.icons.chat)

		-- Check if we have any context buffers
		if #M.context_buffers > 0 then
			local filenames = {}
			for _, bufnr in ipairs(M.context_buffers) do
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
				winbar_text =
					string.format(" %s Chat%s: %s", M.config.icons.chat, zen_indicator, table.concat(filenames, ", "))
			end
		end

		vim.api.nvim_set_option_value("winbar", winbar_text, { win = M.chat_window.messages.winid })
	end
end

---@param input_text string Message to send
local chat_send_message = async.void(function(input_text)
	if not M.chat then
		-- Get content from all context buffers
		local file_contents = {}
		for _, bufnr in ipairs(M.context_buffers) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				local filename = vim.api.nvim_buf_get_name(bufnr)
				local file_basename = vim.fn.fnamemodify(filename, ":t")
				if file_basename == "" then
					file_basename = "[Buffer " .. bufnr .. "]"
				end
				file_contents[file_basename] = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
			end
		end

		M.chat = Chat.new(M.session, nil, file_contents)
		M.chat_id = M.chat:create_chat()
		if not M.chat_id then
			vim.notify("Failed to create chat conversation", vim.log.levels.ERROR)
			return
		end
	end

	-- Store the user message in history
	local trimmed_message = utils.trim_message(input_text)
	local user_message = "\nYou: " .. trimmed_message .. "\n"
	table.insert(M.message_history, user_message)

	-- Only update window if it exists
	if M.chat_window and M.chat_window.messages.bufnr and vim.api.nvim_buf_is_valid(M.chat_window.messages.bufnr) then
		window_append_text(user_message, false)
		window_append_text("Claude: *thinking...*", false)
	end

	async.util.sleep(100) -- Small delay to ensure UI updates

	-- Send message to Claude
	local response = M.chat:send_message(M.chat_id, input_text)

	vim.schedule(function()
		if not response then
			vim.notify("Error sending message: " .. tostring(response), vim.log.levels.ERROR)
			return
		end

		-- Store Claude's response in history
		local claude_response = "Claude:" .. response

		-- Only update window if it exists and is valid
		if
			M.chat_window
			and M.chat_window.messages.bufnr
			and vim.api.nvim_buf_is_valid(M.chat_window.messages.bufnr)
		then
			-- Remove thinking message
			local last_line = vim.api.nvim_buf_line_count(M.chat_window.messages.bufnr)
			vim.api.nvim_buf_set_lines(M.chat_window.messages.bufnr, last_line - 1, last_line, false, {})
			-- Append actual response
			window_append_text(claude_response)
		else
			-- When window is closed, just store in history WITHOUT calling window_append_text
			table.insert(M.message_history, claude_response)
			vim.notify("Chat response received and stored. Reopen chat to view.", vim.log.levels.INFO)
		end
	end)
end)

---Close chat window
local window_close = function()
	M.chat_window.layout:unmount()
	M.chat_window = nil
	M.is_visible = false
	M.zen_mode = false
	M.last_displayed_message = 0
end

---Start new conversation
local chat_new_conversation = async.void(function()
	if not M.session then
		vim.notify("No active session", vim.log.levels.ERROR)
		return
	end

	-- Clear source_buf
	M.source_buf = nil

	-- Close and reopen the window to get fresh buffer context
	window_close()
	M.window_toggle(M.session)

	-- Clear message history
	M.message_history = {}
	M.conversation_started = false

	-- Create new chat
	M.chat = Chat.new(M.session, get_filename())
	M.chat_id = M.chat:create_chat()

	if not M.chat_id then
		vim.notify("Failed to create new chat conversation", vim.log.levels.ERROR)
		return
	end

	-- Clear the messages window
	if M.chat_window and M.chat_window.messages.bufnr then
		vim.api.nvim_buf_set_lines(M.chat_window.messages.bufnr, 0, -1, false, {})
	end

	vim.notify("Started new conversation", vim.log.levels.INFO)
end)

local create_split_layout = function()
	local width = M.config.width or 60
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
	local height = M.config.height or 10
	vim.cmd(string.format("resize %d", height))

	-- Set window options for input
	vim.api.nvim_set_option_value("wrap", true, { win = input_win })
	vim.api.nvim_set_option_value("number", false, { win = input_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = input_win })
	local input_winbar = string.format("%s Message Input [Ctrl+S to send]", M.config.icons.input)
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
	if not (M.chat_window and M.chat_window.messages.bufnr) then
		return
	end

	update_winbar()

	local bufnr = M.chat_window.messages.bufnr
	local all_lines = {}
	local highlight_info = {}

	-- Process all messages and prepare lines with proper labels and icons
	for i = M.last_displayed_message + 1, #M.message_history do
		local msg = M.message_history[i]
		local start_line = #all_lines
		local lines = vim.split(msg, "\n")

		for j, line in ipairs(lines) do
			local left_icon_length = #icons.left_circle
			local right_icon_length = #icons.right_circle

			if line:match("^Claude:") then
				local label = icons.left_circle .. "  Claude: " .. icons.right_circle
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
				local label = icons.left_circle .. " You: " .. icons.right_circle
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
				hlns,
				bufnr,
				hi.line_num,
				hi.left_icon_length,
				hi.label_length,
				hi.right_icon_length
			)
		else -- user
			highlights.add_user_highlights(
				hlns,
				bufnr,
				hi.line_num,
				hi.left_icon_length,
				hi.label_length,
				hi.right_icon_length
			)
		end
	end

	M.last_displayed_message = #M.message_history

	-- Restore input history if exists
	if #M.input_history > 0 then
		vim.api.nvim_buf_set_lines(M.chat_window.input.bufnr, 0, -1, false, M.input_history[#M.input_history])
	end

	-- Scroll to bottom
	local line_count = vim.api.nvim_buf_line_count(bufnr)
	vim.api.nvim_win_set_cursor(M.chat_window.messages.winid, { line_count, 0 })
end

local function toggle_zen_mode()
	M.zen_mode = not M.zen_mode

	if M.chat_window and M.chat_window.messages.bufnr then
		local bufnr = M.chat_window.messages.bufnr
		local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

		if M.zen_mode then
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
	local keymaps = M.config.keymaps or {}
	local new_chat = async.void(function()
		chat_new_conversation()
	end)
	input_win:map("n", "<C-k>", M.chat_window.focus_messages, { noremap = true })
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
		end)
	end

	input_win:map("n", "<C-s>", function()
		async.run(function()
			send_input()
		end)
	end, { noremap = true })
	input_win:map("i", "<C-s>", function()
		async.run(function()
			send_input()
		end)
	end, { noremap = true })
end

local setup_messages_keymaps = function(messages_win)
	utils.buffer_autocmd(messages_win.bufnr, window_close)
	local keymaps = M.config.keymaps or {}
	local new_chat = async.void(function()
		chat_new_conversation()
	end)
	messages_win:map("n", "<C-j>", M.chat_window.focus_input, { noremap = true })
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
		M.session = session
		if M.is_visible and M.chat_window then
			return window_close()
		end

		local current_buf = vim.api.nvim_get_current_buf()

		-- Add current buffer to context if not already there
		if #M.context_buffers == 0 then
			M.add_buffer_to_context(current_buf)
		end

		-- Always use the first context buffer as source
		M.source_buf = M.context_buffers[1]

		M.zen_mode = false
		M.chat_window = create_split_layout()
		window_restore_messages()
		setup_input_keymaps(M.chat_window.input)
		setup_messages_keymaps(M.chat_window.messages)

		M.chat_window.layout:mount()
		M.is_visible = true
		update_winbar()
	end)()
end

M.list_chats = async.void(function(session)
	M.chat = Chat.new(session, nil)
	local all_chats, err = M.chat:get_all_chats()

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
			M.chat_id = chat_id_list[selected_line[1]]
			local chat_data, chat_err = M.chat:get_single_chat(M.chat_id)

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

			M.message_history = {}
			M.last_displayed_message = 0

			for _, msg in ipairs(chat_data.chat_messages) do
				local formatted_message
				if msg.sender == "human" then
					formatted_message = "\nYou: " .. msg.text .. "\n"
				elseif msg.sender == "assistant" then
					formatted_message = "Claude:" .. msg.text
				end

				if formatted_message then
					table.insert(M.message_history, formatted_message)
				end
			end

			if not M.is_visible or not M.chat_window then
				M.window_toggle(M.session)
				M.source_buf = nil
			else
				window_restore_messages()
			end

			if filename ~= "" then
				vim.api.nvim_set_option_value(
					"winbar",
					"󱐏 Chat - " .. " " .. filename,
					{ win = M.chat_window.messages.winid }
				)
			end

			vim.notify("Loaded chat: " .. chat_data.name, vim.log.levels.INFO)
		end)
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
	for _, buf in ipairs(M.context_buffers) do
		if buf == bufnr then
			vim.notify("Buffer already in chat context", vim.log.levels.WARN)
			return false
		end
	end

	-- Add buffer to context
	table.insert(M.context_buffers, bufnr)

	-- Get buffer name for notification
	local filename = vim.api.nvim_buf_get_name(bufnr)
	local file_basename = vim.fn.fnamemodify(filename, ":t")
	if file_basename == "" then
		file_basename = "[No Name]"
	end

	-- Update any open chat window
	if M.is_visible and M.chat_window then
		update_winbar()
	end

	vim.notify("Added buffer: " .. file_basename .. " to chat context", vim.log.levels.INFO)
	return true
end

-- Remove a buffer from the context
M.remove_buffer_from_context = function(bufnr)
	for i, buf in ipairs(M.context_buffers) do
		if buf == bufnr then
			table.remove(M.context_buffers, i)

			-- Get buffer name for notification
			local filename = vim.api.nvim_buf_get_name(bufnr)
			local file_basename = vim.fn.fnamemodify(filename, ":t")
			if file_basename == "" then
				file_basename = "[No Name]"
			end

			-- Update any open chat window
			if M.is_visible and M.chat_window then
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
	if #M.context_buffers == 0 then
		vim.notify("No buffers in chat context", vim.log.levels.INFO)
		return
	end

	local buffer_list = {}
	for i, bufnr in ipairs(M.context_buffers) do
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
	M.config = config
	if M.config.width and (not utils.is_number(M.config.width) or M.config.width < 40) then
		vim.notify("Invalid width value should be at least 40, falling back to default", vim.log.levels.WARN)
	end
	if M.config.height and (not utils.is_number(M.config.height) or M.config.height > 20) then
		vim.notify("Invalid height value should be at most 20, falling back to default", vim.log.levels.WARN)
	end
	highlights.setup(config)
end

return M
