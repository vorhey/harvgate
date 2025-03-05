local curl = require("plenary.curl")
local async = require("plenary.async")
local utils = require("harvgate.utils")
local URLBuilder = require("harvgate.url_builder")
local OptionsBuilder = require("harvgate.opts_builder")

---@class Chat
---@field session Session
local Chat = {}
Chat.__index = Chat

local function process_stream_response(response)
	if not response or response.status ~= 200 then
		return nil
	end

	local completions = {}
	local data_string = response.body:gsub("\n+", "\n"):gsub("^%s*(.-)%s*$", "%1")

	for line in data_string:gmatch("[^\n]+") do
		local json_start, json_end = line:find("{.*}")
		if json_start then
			local ok, decoded = pcall(vim.json.decode, line:sub(json_start, json_end))
			if ok and decoded.completion then
				table.insert(completions, decoded.completion)
			end
		end
	end

	return #completions > 0 and table.concat(completions, "") or nil
end

---@param session Session
---@param file_path string|nil
---@return Chat
function Chat.new(session, file_path)
	assert(type(session) == "table" and session.cookie and session.organization_id, "Invalid session object")
	return setmetatable({
		session = session,
		named_chats = {},
		current_file = file_path,
		has_sent_file = false,
	}, Chat)
end

--- Creates a new chat conversation.
---@async
---@return string|nil The UUID of the newly created chat, or nil if an error occurred
Chat.create_chat = async.wrap(function(self, cb)
	local payload = {
		name = "",
		uuid = utils.uuidv4(),
		model = self.session.model,
		message = {
			attachments = {},
			files = {},
		},
	}

	local url = URLBuilder.new():chat_creation(self.session.organization_id)
	local opts = OptionsBuilder.new(self.session):for_chat_creation():with_body(payload):build()

	local response = curl.post(url, opts)

	if not response then
		cb(nil, "Async error: Failed to receive response.")
		return
	end

	if response.status ~= 201 then
		cb(nil, string.format("Request failed with status: %d", response.status))
		return
	end

	local ok, decoded_json = pcall(vim.json.decode, response.body)

	if not ok then
		cb(nil, "Failed to decode response JSON")
		return
	end

	cb(decoded_json.uuid, nil)
end, 2)

-- Send a message to the chat conversation and return the response.
---@async
---@param chat_id string The ID of the chat conversation.
---@param prompt string The message to send.
---@return string|nil The decoded response from the server, or nil if an error occurred.
Chat.send_message = async.wrap(function(self, chat_id, prompt, cb)
	local payload = {
		attachments = {},
		files = {},
		prompt = prompt,
		timezone = "UTC",
		model = self.session.model,
	}

	-- Attach file if not exists
	if self.current_file and #self.current_file > 0 and not self.has_sent_file then
		-- Check if file exists before trying to read it
		if vim.fn.filereadable(self.current_file) == 1 then
			local file_content = vim.fn.readfile(self.current_file)
			if file_content and #file_content > 0 then
				table.insert(payload.attachments, {
					file_name = vim.fn.fnamemodify(self.current_file, ":t"),
					file_type = "",
					file_size = #file_content,
					extracted_content = table.concat(file_content, "\n"),
				})
				self.has_sent_file = true
			end
		end
	end

	local url = URLBuilder.new():message_sending(self.session.organization_id, chat_id)
	local opts = OptionsBuilder.new(self.session):for_message_sending(chat_id):with_body(payload):build()

	curl.post(
		url,
		vim.tbl_extend("force", opts, {
			callback = vim.schedule_wrap(function(response)
				if not self.named_chats[chat_id] then
					async.run(function()
						self:rename_chat(chat_id, prompt)
						self.named_chats[chat_id] = true
					end)
				end
				cb(process_stream_response(response))
			end),
		})
	)
end, 4)

Chat.list_chats = async.wrap(function(self, cb)
	local url = URLBuilder.new():chat_listing(self.session.organization_id)
	local opts = OptionsBuilder.new(self.session):for_chat_listing():build()

	local response = curl.get(url, opts)

	if not response then
		cb(nil, "Async error: Failed to receive response.")
		return
	end

	if response.status ~= 200 then
		cb(nil, string.format("Request failed with status: %d", response.status))
		return
	end

	local ok, decoded_json = pcall(vim.json.decode, response.body)

	if not ok then
		cb(nil, "Failed to decode response JSON")
		return
	end

	cb(decoded_json, nil)
end, 2)

Chat.list_unnamed_chats = async.wrap(function(self, cb)
	local chats, err = self:list_chats()
	if err then
		cb(nil, err)
		return
	end

	local unnamed = vim.tbl_filter(function(chat)
		return chat.name == ""
	end, chats)

	cb(unnamed)
end, 2)

Chat.rename_chat = function(self, chat_id, first_message)
	local payload = {
		message_content = "Message 1:" .. first_message,
		recent_titles = {},
	}

	local url = URLBuilder.new():chat_renaming(self.session.organization_id, chat_id)
	local opts = OptionsBuilder.new(self.session):for_chat_renaming():with_body(payload):build()

	return async.wrap(function(cb)
		curl.post(
			url,
			vim.tbl_extend("force", opts, {
				callback = vim.schedule_wrap(function(response)
					cb(response)
				end),
			})
		)
	end, 1)()
end

return Chat
