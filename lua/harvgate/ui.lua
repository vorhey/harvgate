local Popup = require("nui.popup")
local Layout = require("nui.layout")
local Chat = require("harvgate.chat")
local async = require("plenary.async")
local utils = require("harvgate.utils")

local M = {}

-- Store the chat instance and current conversation
M.session = nil
M.chat_window = nil
M.current_chat = nil
M.chat_id = nil
M.is_chat_visible = nil
M.message_history = {}
M.saved_cursor_pos = nil

---@param text string Text to append
---@param save_history boolean? Save to history (default: true)
local window_append_text = function(text, save_history)
	save_history = save_history ~= false
	if M.chat_window and M.chat_window.messages.bufnr then
		local lines = vim.split(text, "\n")
		if save_history then
			table.insert(M.message_history, text)
		end
		vim.api.nvim_buf_set_lines(M.chat_window.messages.bufnr, -1, -1, false, lines)
		-- Scroll to bottom
		local line_count = vim.api.nvim_buf_line_count(M.chat_window.messages.bufnr)
		vim.api.nvim_win_set_cursor(M.chat_window.messages.winid, { line_count, 0 })
	end
end

---@param input_text string Message to send
local chat_send_message = async.void(function(input_text)
	if not M.current_chat then
		M.current_chat = Chat.new(M.session)
		M.chat_id = M.current_chat:create_chat()
		if not M.chat_id then
			vim.notify("Failed to create chat conversation", vim.log.levels.ERROR)
			return
		end
	end

	vim.schedule(function()
		local trimmed_message = utils.trim_message(input_text)
		window_append_text("\nYou: " .. trimmed_message .. "\n")
		window_append_text("\nClaude: *thinking...*", false)
	end)

	async.util.sleep(100) -- Small delay to ensure UI updates

	-- Send message to Claude
	local response = M.current_chat:send_message(M.chat_id, input_text)

	vim.schedule(function()
		if not response then
			vim.notify("Error sending message: " .. tostring(response), vim.log.levels.ERROR)
			return
		end

		local last_line = vim.api.nvim_buf_line_count(M.chat_window.messages.bufnr)
		vim.api.nvim_buf_set_lines(M.chat_window.messages.bufnr, last_line - 1, last_line, false, {})
		window_append_text("Claude: \n" .. response)
	end)
end)

---Start new conversation
local chat_new_conversation = async.void(function()
	if not M.session then
		vim.notify("No active session", vim.log.levels.ERROR)
		return
	end

	-- Clear message history
	M.message_history = {}

	-- Create new chat
	M.current_chat = Chat.new(M.session)
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

---Close chat window
local window_close = function()
	if
		M.chat_window
		and M.chat_window.messages.winid
		and vim.api.nvim_get_current_win() == M.chat_window.messages.winid
	then
		M.saved_cursor_pos = vim.api.nvim_win_get_cursor(M.chat_window.messages.winid)
	end
	M.chat_window.layout:unmount()
	M.chat_window = nil
	M.is_visible = false
end

-- Creates the chat window layout (messages and input)
local create_chat_layout = function()
	-- Messages window
	local messages_popup = Popup({
		enter = false,
		focusable = true,
		border = {
			style = "rounded",
			text = {
				top = " Claude Chat ",
				top_align = "center",
			},
		},
		buf_options = {
			modifiable = true,
			readonly = false,
		},
		win_options = {
			wrap = true,
			cursorline = true,
		},
		relative = "editor",
	})
	vim.schedule(function()
		if messages_popup.bufnr then
			vim.api.nvim_buf_set_option(messages_popup.bufnr, "syntax", "markdown")
			vim.api.nvim_buf_set_option(messages_popup.bufnr, "filetype", "markdown")
		end
	end)
	-- Input window
	local input_popup = Popup({
		enter = true,
		focusable = true,
		border = {
			style = "rounded",
			text = {
				top = " Message (Ctrl+S to send) ",
				top_align = "left",
			},
		},
		buf_options = {
			modifiable = true,
			readonly = false,
		},
		win_options = {
			wrap = true,
		},
		relative = "editor",
	})

	-- Create layout
	local layout = Layout(
		{
			position = "50%", -- Position in the middle of the editor
			relative = "editor",
			size = {
				width = "80%",
				height = "100%",
			},
		},
		Layout.Box({
			Layout.Box(messages_popup, { size = "70%" }),
			Layout.Box(input_popup, { size = "30%" }),
		}, { dir = "col", size = "100%" })
	)

	-- Functions for focusing the input and message windows
	local function focus_input()
		if input_popup and input_popup.winid and vim.api.nvim_win_is_valid(input_popup.winid) then
			vim.schedule(function()
				vim.api.nvim_set_current_win(input_popup.winid)
			end)
		end
	end

	local function focus_messages()
		if messages_popup and messages_popup.winid and vim.api.nvim_win_is_valid(messages_popup.winid) then
			vim.schedule(function()
				vim.api.nvim_set_current_win(messages_popup.winid)
			end)
		end
	end

	return {
		layout = layout,
		messages = messages_popup,
		input = input_popup,
		focus_input = focus_input,
		focus_messages = focus_messages,
	}
end

local setup_input_keymaps = function(input_win)
	input_win:map("n", "<Esc>", window_close, { noremap = true })
	input_win:map("n", "q", window_close, { noremap = true })
	input_win:map("n", "<C-g>", chat_new_conversation, { noremap = true })
	input_win:map("n", "<C-k>", M.chat_window.focus_messages, { noremap = true })

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
	messages_win:map("n", "<C-j>", M.chat_window.focus_input, { noremap = true })
	messages_win:map("n", "<Esc>", window_close, { noremap = true })
	messages_win:map("n", "q", window_close, { noremap = true })
	messages_win:map("n", "<C-g>", chat_new_conversation, { noremap = true })
end

---Restore message history
local window_restore_messages = function()
	if M.chat_window and M.chat_window.messages.bufnr then
		for _, msg in ipairs(M.message_history) do
			local lines = vim.split(msg, "\n")
			vim.api.nvim_buf_set_lines(M.chat_window.messages.bufnr, -1, -1, false, lines)
		end
		if M.saved_cursor_pos then
			vim.schedule(function()
				vim.api.nvim_win_set_cursor(M.chat_window.messages.winid, M.saved_cursor_pos)
				local win_height = vim.api.nvim_win_get_height(M.chat_window.messages.winid)
				local cursor_line = M.saved_cursor_pos[1]
				vim.api.nvim_win_set_cursor(M.chat_window.messages.winid, { cursor_line, 0 })
				vim.fn.winrestview({ topline = math.max(1, cursor_line - math.floor(win_height / 2)) })
			end)
		end
	end
end

---@param session any Chat session
M.window_toggle = function(session)
	async.void(function()
		M.session = session
		if M.is_visible and M.chat_window then
			return window_close()
		end

		M.chat_window = create_chat_layout()
		window_restore_messages()

		setup_input_keymaps(M.chat_window.input)
		setup_messages_keymaps(M.chat_window.messages)

		M.chat_window.layout:mount()
		M.is_visible = true
	end)()
end

return M
