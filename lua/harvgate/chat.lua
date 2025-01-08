local curl = require("plenary.curl")
local async = require("plenary.async")
local utils = require("harvgate.utils")
local RequestBuilder = require("harvgate.request_builder")

---@class Chat
---@field session Session
local Chat = {}
Chat.__index = Chat

local function process_stream_response(response)
	if not response or response.status ~= 200 then
		return nil
	end

	local data_string = response.body:gsub("\n+", "\n"):gsub("^%s*(.-)%s*$", "%1")
	local completions = {}

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
---@return Chat
function Chat.new(session)
	assert(type(session) == "table" and session.cookie and session.organization_id, "Invalid session object")
	return setmetatable({ session = session }, Chat)
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
			content = "Please give this chat a title based on my first message.",
			attachments = {},
			files = {},
		},
	}
	local builder = RequestBuilder.new(self.session)
	local config = builder:for_chat_creation():with_body(payload):build()

	--- Send a curl request with the specified options
	--- @param options table Options for the curl request
	--- @return table|nil response Response table or nil if failed
	local function send_request(options)
		return async.wrap(function(inner_cb)
			curl.post(vim.tbl_extend("force", {
				url = config.url,
				headers = config.headers,
				body = config.body,
				callback = vim.schedule_wrap(function(response)
					inner_cb(response)
				end),
			}, options))
		end, 1)()
	end

	-- Attempt the first request with http2 options
	local response = send_request({
		http_version = "HTTP/2",
		raw = { "--tlsv1.3", "--ipv4" },
	})

	-- If the first attempt fails, retry without http2 options
	if not response or response.status ~= 201 then
		response = send_request({})
	end

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
	local builder = RequestBuilder.new(self.session)
	local config = builder:for_message_sending(chat_id):with_body(payload):build()

	--- Send a curl request with the specified options
	--- @param options table Options for the curl request
	--- @return table|nil response Response table or nil if failed
	local function send_request(options, inner_cb)
		curl.post(vim.tbl_extend("force", {
			url = config.url,
			headers = config.headers,
			body = config.body,
			callback = vim.schedule_wrap(function(response)
				inner_cb(process_stream_response(response))
			end),
		}, options))
	end

	-- Attempt the first request with http2 options
	send_request({
		http_version = "HTTP/2",
		raw = { "--tlsv1.3", "--ipv4" },
	}, function(result)
		if result then
			cb(result)
			return
		end
		-- Attempt the second request without http2 options
		send_request({}, function(retry_result)
			cb(retry_result)
		end)
	end)
end, 4)

Chat.list_chats = async.wrap(function(self, cb)
	local builder = RequestBuilder.new(self.session)
	local config = builder:for_chat_listing().build()

	--- Send a curl request with the specified options
	--- @param options table Options for the curl request
	--- @return table|nil response Response table or nil if failed
	local function send_request(options)
		return async.wrap(function(inner_cb)
			curl.post(vim.tbl_extend("force", {
				url = config.url,
				headers = config.headers,
				body = config.body,
				callback = vim.schedule_wrap(function(response)
					inner_cb(response)
				end),
			}, options))
		end, 1)()
	end

	-- Attempt the first request with http2 options
	local response = send_request({
		http_version = "HTTP/2",
		raw = { "--tlsv1.3", "--ipv4" },
	})

	-- If the first attempt fails, retry without http2 options
	if not response or response.status ~= 201 then
		response = send_request({})
	end

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

	cb(decoded_json, nil)
end, 2)

return Chat
