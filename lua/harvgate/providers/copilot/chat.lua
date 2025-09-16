local curl = require("plenary.curl")
local async = require("plenary.async")
local utils = require("harvgate.utils")

---@class CopilotChat
---@field session CopilotSession
---@field conversation_id string
---@field primary_file string|nil
---@field additional_files table<string, string>
---@field pending_files table<string, string>
---@field has_sent_context boolean
---@field context_updated boolean
---@field messages table
---@field config table
local Chat = {}
Chat.__index = Chat

local function normalize_content(content)
	if type(content) == "table" then
		return table.concat(content, "\n")
	end
	return content or ""
end

local function render_context_block(filename, content)
	local normalized = normalize_content(content)
	return string.format("Filename: %s\n```\n%s\n```", filename, normalized)
end

local function gather_context(self)
	local attachments = {}

	if not self.has_sent_context and self.primary_file and #self.primary_file > 0 then
		if vim.fn.filereadable(self.primary_file) == 1 then
			local content = vim.fn.readfile(self.primary_file)
			if content and #content > 0 then
				local filename = vim.fn.fnamemodify(self.primary_file, ":t")
				attachments[filename] = content
			end
		end
	end

	local files_to_send
	if not self.has_sent_context then
		files_to_send = self.additional_files or {}
	else
		files_to_send = self.pending_files or {}
	end

	for filename, content in pairs(files_to_send) do
		if not attachments[filename] then
			attachments[filename] = content
		end
	end

	if vim.tbl_isempty(attachments) then
		return nil
	end

	self.has_sent_context = true
	self.context_updated = false
	self.pending_files = {}

	local blocks = {}
	for filename, content in pairs(attachments) do
		blocks[#blocks + 1] = render_context_block(filename, content)
	end

	return table.concat(blocks, "\n\n")
end

local function build_user_message(prompt, context)
	local text = prompt
	if context and context ~= "" then
		text = string.format("%s\n\n[Context]\n%s", prompt, context)
	end

	return {
		role = "user",
		content = {
			{
				type = "text",
				text = text,
			},
		},
	}
end

local function extract_text_from_choice(choice)
	if type(choice) ~= "table" then
		return nil
	end

	local container = choice.delta or choice.message
	if type(container) ~= "table" then
		return nil
	end

	local parts = {}
	if type(container.content) == "table" then
		for _, item in ipairs(container.content) do
			if type(item) == "table" and item.type == "text" and item.text then
				parts[#parts + 1] = item.text
			end
		end
	elseif type(container.text) == "string" then
		parts[#parts + 1] = container.text
	end

	if #parts == 0 then
		return nil
	end

	return table.concat(parts, "")
end

local function parse_stream_body(body)
	if not body or body == "" then
		return nil, nil, "Empty response body"
	end

	local fragments = {}
	local conversation_id = nil

	for line in body:gmatch("[^\r\n]+") do
		local payload = line:match("^data:%s*(.+)")
		if payload and payload ~= "[DONE]" then
			local ok, decoded = pcall(vim.json.decode, payload)
			if ok and decoded then
				conversation_id = decoded.conversation_id or conversation_id
				if type(decoded.choices) == "table" then
					for _, choice in ipairs(decoded.choices) do
						local text = extract_text_from_choice(choice)
						if text and text ~= "" then
							fragments[#fragments + 1] = text
						end
					end
				end
			end
		end
	end

	if #fragments == 0 then
		return nil, conversation_id, "No completion chunks returned"
	end

	return table.concat(fragments, ""), conversation_id, nil
end

---@param session CopilotSession
---@param file_path string|nil
---@param additional_files table<string, string>|nil
---@param config table|nil
---@return CopilotChat
function Chat.new(session, file_path, additional_files, config)
	assert(type(session) == "table", "Invalid Copilot session")

	return setmetatable({
		session = session,
		conversation_id = utils.uuidv4(),
		primary_file = file_path,
		additional_files = additional_files or {},
		pending_files = {},
		has_sent_context = false,
		context_updated = false,
		messages = {},
		config = config or {},
	}, Chat)
end

Chat.create_chat = async.wrap(function(self, cb)
	cb(self.conversation_id, nil)
end, 1)

---@async
---@param chat_id string
---@param prompt string
---@param cb fun(response:string|nil, err:string|nil)
Chat.send_message = async.wrap(function(self, chat_id, prompt, cb)
	local context = gather_context(self)
	local user_message = build_user_message(prompt, context)

	local message_history = vim.deepcopy(self.messages)
	message_history[#message_history + 1] = user_message

	local payload = {
		model = self.config.model or self.session.model,
		intent = "conversation",
		conversation_id = self.conversation_id or chat_id,
		messages = message_history,
		stream = true,
		temperature = self.config.temperature or self.session.temperature,
		top_p = self.config.top_p or self.session.top_p,
		n = 1,
	}

	local url, opts, err = self.session:build_request(payload)
	if not url then
		cb(nil, err or "Failed to prepare Copilot request")
		return
	end

	opts.callback = vim.schedule_wrap(function(response)
		if not response then
			cb(nil, "Failed to receive response")
			return
		end

		if response.status ~= 200 then
			local err_msg = string.format("Request failed with status: %d", response.status)
			if response.body then
				local ok_body, decoded = pcall(vim.json.decode, response.body)
				if ok_body and decoded and decoded.error and decoded.error.message then
					err_msg = err_msg .. " - " .. decoded.error.message
				end
			end
			cb(nil, err_msg)
			return
		end

		local text, new_conversation_id, parse_err = parse_stream_body(response.body)
		if not text then
			cb(nil, parse_err or "Failed to parse response data")
			return
		end

		self.conversation_id = new_conversation_id or self.conversation_id
		self.messages = message_history
		self.messages[#self.messages + 1] = {
			role = "assistant",
			content = {
				{
					type = "text",
					text = text,
				},
			},
		}

		cb(text, nil)
	end)

	local ok_request, request_err = pcall(curl.post, url, opts)
	if not ok_request then
		cb(nil, request_err)
	end
end, 4)

function Chat:update_context(additional_files, should_merge)
	if not self.additional_files then
		self.additional_files = {}
	end

	self.pending_files = self.pending_files or {}

	if type(additional_files) == "table" then
		if not should_merge then
			self.additional_files = {}
			self.pending_files = {}
		end

		for filename, content in pairs(additional_files) do
			if not self.additional_files[filename] or self.additional_files[filename] ~= content then
				self.pending_files[filename] = content
				self.context_updated = true
			end

			self.additional_files[filename] = content
		end
	end
end

function Chat:get_all_chats()
	return nil, "Copilot provider does not expose chat history"
end

function Chat:get_single_chat(_)
	return nil, "Copilot provider does not expose chat history"
end

function Chat:rename_chat(_, _)
	return nil
end

return Chat
