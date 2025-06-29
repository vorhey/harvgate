local curl = require("plenary.curl")
local async = require("plenary.async")
local utils = require("harvgate.utils")
local URLBuilder = require("harvgate.url_builder")
local OptionsBuilder = require("harvgate.opts_builder")

---@class Chat
---@field session Session
local Chat = {}
Chat.__index = Chat

local function parse_stream_data(response)
-- stylua: ignore start
	if not response then return nil, "No response provided" end
	if response.status ~= 200 then return nil, string.format("HTTP error: %d", response.status) end
	if not response.body or response.body == "" then return nil, "Empty response body" end
	-- stylua: ignore end
	local completions = {}
	local clean_body = response.body:gsub("\n+", "\n"):gsub("^%s*(.-)%s*$", "%1")
	for line in clean_body:gmatch("[^\r\n]+") do
		local json_to_parse = line:match("^data:%s*(.+)") or line:match("{.*}")
		if json_to_parse then
			local ok, decoded = pcall(vim.json.decode, json_to_parse)
			if ok and decoded.completion then
				completions[#completions + 1] = decoded.completion
			end
		end
	end

	return #completions > 0 and table.concat(completions, "") or nil
end

---@param session Session The session object containing authentication information
---@param file_path string|nil Optional path to a file to be included as primary file
---@param additional_files table|nil Optional table of additional files {[filename] = content}
---@return Chat A new Chat instance
function Chat.new(session, file_path, additional_files)
	assert(type(session) == "table" and session.cookie and session.organization_id, "Invalid session object")
	return setmetatable({
		session = session,
		named_chats = {},
		primary_file = file_path,
		additional_files = additional_files or {},
		has_sent_files = false,
		context_updated = false,
		pending_files = {}, -- Track files that need to be sent
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

	local url = URLBuilder.new():create_chat(self.session.organization_id)
	local opts = OptionsBuilder.new(self.session):create_chat():with_body(payload):build()

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

-- Helper function to create file attachment
local function create_attachment(filename, content)
	return {
		file_name = filename,
		file_type = "",
		file_size = #content,
		extracted_content = type(content) == "table" and table.concat(content, "\n") or content,
	}
end

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

	-- Handle file attachments if needed
	if not self.has_sent_files or self.context_updated then
		local added_files = {}

		-- Handle primary file
		if
			not self.has_sent_files
			and self.primary_file
			and #self.primary_file > 0
			and vim.fn.filereadable(self.primary_file) == 1
		then
			local content = vim.fn.readfile(self.primary_file)
			if content and #content > 0 then
				local filename = vim.fn.fnamemodify(self.primary_file, ":t")
				table.insert(payload.attachments, create_attachment(filename, content))
				added_files[filename] = true
			end
		end

		-- Handle additional and pending files
		local files_to_process = not self.has_sent_files and self.additional_files or self.pending_files or {}
		for filename, content in pairs(files_to_process) do
			if not added_files[filename] then
				table.insert(payload.attachments, create_attachment(filename, content))
			end
		end

		self.has_sent_files = true
		self.context_updated = false
		self.pending_files = {}
	end

	local url = URLBuilder.new():send_message(self.session.organization_id, chat_id)
	local opts = OptionsBuilder.new(self.session):send_message(chat_id):with_body(payload):build()

	curl.post(
		url,
		vim.tbl_extend("force", opts, {
			callback = vim.schedule_wrap(function(response)
				if not response then
					cb(nil, "Failed to receive response")
					return
				end
				if response.status ~= 200 then
					local err_msg = string.format("Request failed with status: %d", response.status)
					if response.body then
						local ok, decoded = pcall(vim.json.decode, response.body)
						if ok and decoded.message then
							err_msg = err_msg .. " - " .. decoded.message
						end
					end
					cb(nil, err_msg)
					return
				end
				if not self.named_chats[chat_id] then
					async.run(function()
						self:rename_chat(chat_id, prompt)
						self.named_chats[chat_id] = true
					end, function() end)
				end
				local parsed = parse_stream_data(response)
				if not parsed then
					cb(nil, "Failed to parse response data")
					return
				end
				cb(parsed, nil)
			end),
		})
	)
end, 4)

---@async
---@return table|nil, string|nil The list of all chats, or nil and an error message if an error occurred
Chat.get_all_chats = async.wrap(function(self, cb)
	local url = URLBuilder.new():get_all_chats(self.session.organization_id)
	local opts = OptionsBuilder.new(self.session):get_all_chats():build()

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

Chat.get_single_chat = async.wrap(function(self, chat_id, cb)
	local url = URLBuilder.new():get_single_chat(self.session.organization_id, chat_id)
	local opts = OptionsBuilder.new(self.session):get_single_chat(chat_id):build()

	local response = curl.get(url, opts)

	if not response then
		cb(nil, "Async error: Failed to receive response.")
		return
	end

	if response.status ~= 200 then
		cb(nil, string.format("Request failed with status: %d", response.status))
		return
	end

	local success, data = pcall(vim.json.decode, response.body)

	if not success then
		cb(nil, "Failed to parse response JSON")
		return
	end

	cb(data, nil)
end, 3)

---@async
---@return table|nil, string|nil The list of all unnamed chats, or nil and an error message if an error occurred
Chat.get_all_unnamed_chats = async.wrap(function(self, cb)
	local chats, err = self:get_all_chats()
	if err then
		cb(nil, err)
		return
	end

	local unnamed = vim.tbl_filter(function(chat)
		return chat.name == ""
	end, chats)

	cb(unnamed)
end, 2)

---@param chat_id string The ID of the chat conversation
---@param first_message string The first message of the chat to use for creating a title
---@return table|nil The response from the server, or nil if an error occurred
Chat.rename_chat = function(self, chat_id, first_message)
	local payload = {
		message_content = "Message 1:" .. first_message,
		recent_titles = {},
	}

	local url = URLBuilder.new():rename_chat(self.session.organization_id, chat_id)
	local opts = OptionsBuilder.new(self.session):rename_chat():with_body(payload):build()

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

-- Add a function to update context by adding more files without creating a new Chat
---@param additional_files table Table of additional files {[filename] = content}
function Chat:update_context(additional_files, should_merge)
	if not self.additional_files then
		self.additional_files = {}
	end

	-- Add tracking for only files that need to be sent
	self.pending_files = self.pending_files or {}

	if type(additional_files) == "table" then
		-- If merging, keep existing files, otherwise clear them
		if not should_merge then
			self.additional_files = {}
			self.pending_files = {}
		end

		-- Track which files are new and need to be sent
		for filename, content in pairs(additional_files) do
			-- If file is new or has changed
			if not self.additional_files[filename] or self.additional_files[filename] ~= content then
				self.pending_files[filename] = content
				self.context_updated = true
			end

			-- Update/add to additional_files
			self.additional_files[filename] = content
		end
	end
end

return Chat
