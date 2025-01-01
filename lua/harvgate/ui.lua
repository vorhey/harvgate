local Popup = require("nui.popup")
local Layout = require("nui.layout")
local Chat = require("harvgate.chat")
local async = require("plenary.async")

local M = {}

-- Store the chat instance and current conversation
M.chat_window = nil
M.current_chat = nil
M.chat_id = nil
M.message_history = {}

-- Create chat layout with messages and input
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
			position = "50%",
			relative = "editor",
			size = {
				width = "80%",
				height = "80%",
			},
		},
		Layout.Box({
			Layout.Box(messages_popup, { size = "80%" }),
			Layout.Box(input_popup, { size = "20%" }),
		}, { dir = "col" })
	)

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

-- Function to handle sending messages
local send_message = async.void(function(input_text)
	if not M.current_chat or not M.chat_id then
		vim.schedule(function()
			vim.notify("Chat not initialized", vim.log.levels.ERROR)
		end)
		return
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

-- Function to toggle the chat window
function M.toggle_chat(session)
	async.void(function()
		if not M.current_chat then
			M.current_chat = Chat.new(session)
			M.chat_id = M.current_chat:create_chat()
			if not M.chat_id then
				vim.notify("Failed to create chat conversation", vim.log.levels.ERROR)
				return
			end
		end

		M.chat_window = create_chat_layout()
		M.restore_messages()

		M.chat_window.input:map("n", "<C-k>", M.chat_window.focus_messages, { noremap = true })
		M.chat_window.messages:map("n", "<C-j>", M.chat_window.focus_input, { noremap = true })

		local function close_chat()
			if M.chat_window and M.chat_window.layout then
				M.chat_window.layout:unmount()
				M.chat_window = nil
			end
		end

		M.chat_window.messages:map("n", "<Esc>", close_chat, { noremap = true })
		M.chat_window.messages:map("n", "q", close_chat, { noremap = true })
		M.chat_window.input:map("n", "<Esc>", close_chat, { noremap = true })
		M.chat_window.input:map("n", "q", close_chat, { noremap = true })

		M.chat_window.input:map("n", "<C-s>", function()
			local lines = vim.api.nvim_buf_get_lines(M.chat_window.input.bufnr, 0, -1, false)
			local input_text = table.concat(lines, "\n")
			vim.api.nvim_buf_set_lines(M.chat_window.input.bufnr, 0, -1, false, { "" })
			send_message(input_text)
		end, { noremap = true })

		M.chat_window.input:map("i", "<C-s>", function()
			local lines = vim.api.nvim_buf_get_lines(M.chat_window.input.bufnr, 0, -1, false)
			local input_text = table.concat(lines, "\n")
			vim.api.nvim_buf_set_lines(M.chat_window.input.bufnr, 0, -1, false, { "" })
			send_message(input_text)
		end, { noremap = true })

		M.chat_window.layout:mount()
	end)()
end

function M.restore_messages()
	if M.chat_window and M.chat_window.messages.bufnr then
		for _, msg in ipairs(M.message_history) do
			local lines = vim.split(msg, "\n")
			vim.api.nvim_buf_set_lines(M.chat_window.messages.bufnr, -1, -1, false, lines)
		end
	end
end

-- Function to append text to chat window
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
