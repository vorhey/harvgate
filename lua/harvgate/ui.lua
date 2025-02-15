local Chat = require("harvgate.chat")
local async = require("plenary.async")
local utils = require("harvgate.utils")

local M = {}

-- Store the chat instance and current conversation
M.config = nil
M.session = nil
M.chat_window = nil
M.current_chat = nil
M.chat_id = nil
M.is_chat_visible = nil
M.message_history = {}
M.input_history = {}
M.source_buf = nil
M.zen_mode = false
M.last_displayed_message = 0

local HIGHLIGHT_NS = vim.api.nvim_create_namespace("chat highlights")

local icons = {
	left_circle = "",
	right_circle = "",
}

local function setup_highlights()
	vim.api.nvim_set_hl(0, "ChatClaudeLabel", {
		bg = M.config.highlights.claude_label_bg,
		fg = M.config.highlights.claude_label_fg,
		bold = true,
	})

	vim.api.nvim_set_hl(0, "ChatUserLabel", {
		bg = M.config.highlights.user_label_bg,
		fg = M.config.highlights.user_label_fg,
		bold = true,
	})

	vim.api.nvim_set_hl(0, "ChatClaudeBorder", {
		fg = M.config.highlights.claude_label_bg,
		bold = true,
	})

	vim.api.nvim_set_hl(0, "ChatUserBorder", {
		fg = M.config.highlights.user_label_bg,
		bold = true,
	})
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

				vim.api.nvim_buf_add_highlight(
					M.chat_window.messages.bufnr,
					HIGHLIGHT_NS,
					"ChatClaudeBorder",
					line_num,
					0,
					label_length
				)

				vim.api.nvim_buf_add_highlight(
					M.chat_window.messages.bufnr,
					HIGHLIGHT_NS,
					"ChatClaudeLabel",
					line_num,
					left_icon_length,
					left_icon_length + label_length
				)

				vim.api.nvim_buf_add_highlight(
					M.chat_window.messages.bufnr,
					HIGHLIGHT_NS,
					"ChatClaudeBorder",
					line_num,
					left_icon_length + label_length,
					left_icon_length + label_length + right_icon_length
				)
			elseif line:match(icons.left_circle .. " You:") then
				local label_length = #" You: "

				vim.api.nvim_buf_add_highlight(
					M.chat_window.messages.bufnr,
					HIGHLIGHT_NS,
					"ChatUserBorder",
					line_num,
					0,
					label_length
				)
				vim.api.nvim_buf_add_highlight(
					M.chat_window.messages.bufnr,
					HIGHLIGHT_NS,
					"ChatUserLabel",
					line_num,
					left_icon_length,
					left_icon_length + label_length
				)
				vim.api.nvim_buf_add_highlight(
					M.chat_window.messages.bufnr,
					HIGHLIGHT_NS,
					"ChatUserBorder",
					line_num,
					left_icon_length + label_length,
					left_icon_length + label_length + right_icon_length
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
		local current_file = get_filename()
		local zen_indicator = M.zen_mode and " [ZEN]" or ""
		local winbar_text
		if not current_file then
			winbar_text = string.format(" %s Chat%s - [No File]", M.config.icons.chat, zen_indicator)
		else
			local file_name = vim.fn.fnamemodify(current_file, ":t")
			local file_icon = get_file_icon(current_file)
			winbar_text =
				string.format(" %s Chat%s - [%s %s]", M.config.icons.chat, zen_indicator, file_icon, file_name)
		end
		vim.api.nvim_set_option_value("winbar", winbar_text, { win = M.chat_window.messages.winid })
	end
end

---@param input_text string Message to send
local chat_send_message = async.void(function(input_text)
	if not M.current_chat then
		local current_file = get_filename()
		M.current_chat = Chat.new(M.session, current_file)
		M.chat_id = M.current_chat:create_chat()
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
	local response = M.current_chat:send_message(M.chat_id, input_text)

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
	M.current_chat = Chat.new(M.session, get_filename())
	M.chat_id = M.current_chat:create_chat()

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

	-- Add current file to messages window title
	local winbar_text
	if not M.source_buf or not vim.api.nvim_buf_is_valid(M.source_buf) then
		winbar_text = string.format(" %s Chat - [No File]", M.config.icons.chat)
	else
		local full_path = vim.api.nvim_buf_get_name(M.source_buf)
		local file_name = vim.fn.fnamemodify(full_path, ":t")
		local file_icon = get_file_icon(full_path)
		winbar_text = string.format(" %s Chat - [%s %s]", M.config.icons.chat, file_icon, file_name)
	end
	vim.api.nvim_set_option_value("winbar", winbar_text, { win = messages_win })

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
	vim.cmd("resize 10")

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
					vim.api.nvim_win_close(input_win, true)
				end
				if vim.api.nvim_win_is_valid(messages_win) then
					vim.api.nvim_win_close(messages_win, true)
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
	local highlights = {}

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
				table.insert(highlights, {
					line_num = line_num,
					highlights = {
						{ "ChatClaudeBorder", 0, left_icon_length },
						{ "ChatClaudeLabel", left_icon_length, left_icon_length + label_length },
						{
							"ChatClaudeBorder",
							left_icon_length + label_length,
							left_icon_length + label_length + right_icon_length,
						},
					},
				})
			elseif line:match("^You:") then
				local label = icons.left_circle .. " You: " .. icons.right_circle
				local modified_line = label .. line:sub(5) -- 5 to account for "You: "
				table.insert(all_lines, modified_line)

				local line_num = start_line + j - 1
				local label_length = #" You: "

				-- Store highlight information
				table.insert(highlights, {
					line_num = line_num,
					highlights = {
						{ "ChatUserBorder", 0, left_icon_length },
						{ "ChatUserLabel", left_icon_length, left_icon_length + label_length },
						{
							"ChatUserBorder",
							left_icon_length + label_length,
							left_icon_length + label_length + right_icon_length,
						},
					},
				})
			else
				table.insert(all_lines, line)
			end
		end
	end

	-- Set all lines at once
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, all_lines)

	-- Apply all highlights
	for _, hl_info in ipairs(highlights) do
		for _, hl in ipairs(hl_info.highlights) do
			vim.api.nvim_buf_add_highlight(
				bufnr,
				HIGHLIGHT_NS,
				hl[1], -- highlight group
				hl_info.line_num, -- line number
				hl[2], -- start col
				hl[3] -- end col
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
end

---@param session any Chat session
M.window_toggle = function(session)
	async.void(function()
		M.session = session
		if M.is_visible and M.chat_window then
			return window_close()
		end

		if not M.source_buf or not M.current_chat then
			M.source_buf = vim.api.nvim_get_current_buf()
		end

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

---@param config Config
M.setup = function(config)
	M.config = config
	if M.config.width and (not utils.is_number(M.config.width) or M.config.width < 40) then
		vim.notify("Invalid width value should be at least 40, falling back to default", vim.log.levels.WARN)
	end
	setup_highlights()
end

return M
