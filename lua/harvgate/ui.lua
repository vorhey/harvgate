local Popup = require("nui.popup")
local Layout = require("nui.layout")
local Chat = require("harvgate.chat")
local async = require("plenary.async")

---@class Layout
---@field mount function Mount the layout
---@field unmount function Unmount the layout

---@class Popup
---@field winid number Window ID
---@field bufnr number Buffer number
---@field map fun(mode: string, lhs: string, rhs: function|string, opts: table) Map key in window

---@class ChatWindow
---@field layout Layout Layout manager instance
---@field messages Popup Messages window popup
---@field input Popup Input window popup
---@field focus_input function Focus the input window
---@field focus_messages function Focus the messages window

---@class Chat
---@field new fun(session: Session): Chat Create new chat instance
---@field create_chat fun(self: Chat): string Create new chat conversation
---@field send_message fun(self: Chat, chat_id: string, message: string): string Send message to chat

--- Module for Claude chat interface
---@class ChatModule
---@field session any Current session
---@field chat_window ChatWindow|nil Current chat window
---@field current_chat Chat|nil Current chat instance
---@field chat_id string|nil Current chat ID
---@field is_chat_visible boolean|nil Chat visibility state
---@field message_history string[] Message history
local M = {}

-- Store the chat instance and current conversation
M.session = nil
M.chat_window = nil
M.current_chat = nil
M.chat_id = nil
M.is_chat_visible = nil
M.message_history = {}
M.saved_cursor_pos = nil

-- Creates the chat window layout (messages and input)
local function create_chat_layout()
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

---@param input_text string Message to send
M.send_message = async.void(function(input_text)
	if not M.current_chat then
		M.current_chat = Chat.new(M.session)
		M.chat_id = M.current_chat:create_chat()
		if not M.chat_id then
			vim.notify("Failed to create chat conversation", vim.log.levels.ERROR)
			return
		end
	end

	vim.schedule(function()
		M.append_text("\nYou: " .. input_text)
		M.append_text("\nClaude: *thinking...*", false)
	end)

	async.util.sleep(100) -- Small delay to ensure UI updates

	-- Send message to Claude
	local response = M.current_chat:send_message(M.chat_id, input_text)

	if response then
		vim.schedule(function()
			local last_line = vim.api.nvim_buf_line_count(M.chat_window.messages.bufnr)
			vim.api.nvim_buf_set_lines(M.chat_window.messages.bufnr, last_line - 1, last_line, false, {})
			M.append_text("Claude: \n" .. response)
		end)
	end
end)

---Start new conversation
M.new_conversation = async.void(function()
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
function M.close_chat()
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

local function setup_input_keymaps(input_win)
	input_win:map("n", "<Esc>", M.close_chat, { noremap = true })
	input_win:map("n", "q", M.close_chat, { noremap = true })
	input_win:map("n", "<C-g>", M.new_conversation, { noremap = true })
	input_win:map("n", "<C-k>", M.chat_window.focus_messages, { noremap = true })

	local function send_input()
		local lines = vim.api.nvim_buf_get_lines(input_win.bufnr, 0, -1, false)
		local input_text = table.concat(lines, "\n")
		vim.api.nvim_buf_set_lines(input_win.bufnr, 0, -1, false, { "" })
		M.send_message(input_text)
	end

	input_win:map("n", "<C-s>", send_input, { noremap = true })
	input_win:map("i", "<C-s>", send_input, { noremap = true })
end

local function setup_messages_keymaps(messages_win)
	messages_win:map("n", "<C-j>", M.chat_window.focus_input, { noremap = true })
	messages_win:map("n", "<Esc>", M.close_chat, { noremap = true })
	messages_win:map("n", "q", M.close_chat, { noremap = true })
	messages_win:map("n", "<C-g>", M.new_conversation, { noremap = true })
end

---@param session any Chat session
function M.toggle_chat(session)
	async.void(function()
		M.session = session
		if M.is_visible and M.chat_window then
			return M.close_chat()
		end

		M.chat_window = create_chat_layout()
		M.restore_messages()

		setup_input_keymaps(M.chat_window.input)
		setup_messages_keymaps(M.chat_window.messages)

		M.chat_window.layout:mount()
		M.is_visible = true
	end)()
end

---Restore message history
function M.restore_messages()
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

---@param text string Text to append
---@param save_history boolean? Save to history (default: true)
function M.append_text(text, save_history)
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

return M
