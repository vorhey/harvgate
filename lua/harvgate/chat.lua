local curl = require("plenary.curl")
local async = require("plenary.async")
local utils = require("harvgate.utils")

---@class Chat
---@field session Session
local Chat = {}
Chat.__index = Chat

local BASE_URL = "https://claude.ai"

---@param session Session
---@return Chat
function Chat.new(session)
	assert(type(session) == "table" and session.cookie and session.organization_id, "Invalid session object")
	return setmetatable({ session = session }, Chat)
end

--- Creates a new chat conversation.
---@async
---@return string|nil The UUID of the newly created chat, or nil if an error occurred
function Chat:create_chat()
	local url = string.format("%s/api/organizations/%s/chat_conversations", BASE_URL, self.session.organization_id)
	local name = os.date("Chat - %Y-%m-%d %H:%M:%S")
	local new_uuid = utils.uuidv4()
	local payload = { name = name, uuid = new_uuid }
	local encoded_payload = vim.json.encode(payload)
	local headers = {
		["Host"] = "claude.ai",
		["User-Agent"] = self.session.user_agent,
		["Accept"] = "*/*",
		["Accept-Language"] = "en-US,en;q=0.5",
		["Accept-Encoding"] = "gzip, deflate, br",
		["Content-Type"] = "application/json",
		["Content-Length"] = #encoded_payload,
		["Referer"] = string.format("%s/chats", BASE_URL),
		["Origin"] = BASE_URL,
		["DNT"] = "1",
		["Sec-Fetch-Dest"] = "empty",
		["Sec-Fetch-Mode"] = "cors",
		["Sec-Fetch-Site"] = "same-origin",
		["Connection"] = "keep-alive",
		["Cookie"] = self.session.cookie,
		["TE"] = "trailers",
	}

	return async.wrap(function(callback)
		local response = curl.post({
			url = url,
			headers = headers,
			body = encoded_payload,
			timeout = self.session.timeout,
			agent = "chrome110",
		})
		if not response then
			vim.notify("Async error: Failed to receive response.", vim.log.levels.ERROR)
			callback(nil)
			return
		end
		if response.status ~= 201 then
			vim.notify(
				string.format("Request to %s failed with status: %d", url, response.status),
				vim.log.levels.ERROR
			)
			callback(nil)
			return
		end
		local ok, j = pcall(vim.json.decode, response.body)
		if not ok then
			callback(nil)
			return
		end
		callback(j.uuid)
	end, 1)()
end

-- Send a message to the chat conversation and return the response.
---@async
---@param chat_id string The ID of the chat conversation.
---@param prompt string The message to send.
---@return string|nil The decoded response from the server, or nil if an error occurred.
function Chat:send_message(chat_id, prompt)
	local url = string.format(
		"%s/api/organizations/%s/chat_conversations/%s/completion",
		BASE_URL,
		self.session.organization_id,
		chat_id
	)

	local payload = {
		attachments = {},
		files = {},
		prompt = prompt,
		timezone = "UTC",
		model = nil,
	}

	local encoded_payload = vim.json.encode(payload)

	local headers = {
		["Host"] = "claude.ai",
		["User-Agent"] = self.session.user_agent,
		["Accept"] = "text/event-stream, text/event-stream",
		["Accept-Language"] = "en-US,en;q=0.5",
		["Accept-Encoding"] = "gzip, deflate, br",
		["Content-Type"] = "application/json",
		["Content-Length"] = tostring(#encoded_payload),
		["Referer"] = string.format("%s/chat/%s", BASE_URL, chat_id),
		["Origin"] = BASE_URL,
		["DNT"] = "1",
		["Sec-Fetch-Dest"] = "empty",
		["Sec-Fetch-Mode"] = "cors",
		["Sec-Fetch-Site"] = "same-origin",
		["Connection"] = "keep-alive",
		["Cookie"] = self.session.cookie,
		["TE"] = "trailers",
	}

	return async.wrap(function(callback)
		local response = curl.post({
			url = url,
			headers = headers,
			body = vim.json.encode(payload),
			timeout = self.session.timeout,
			agent = "chrome110",
		})

		if response.status ~= 200 then
			vim.notify(string.format("Failed to send message to %s: %s", url, response.status), vim.log.levels.ERROR)
			callback(nil)
			return
		end

		local data_string = response.body:gsub("\n+", "\n"):gsub("^%s*(.-)%s*$", "%1")

		local data_lines = {}

		for line in data_string:gmatch("[^\n]+") do
			local json_start, json_end = line:find("{.*}")
			if json_start then
				table.insert(data_lines, line:sub(json_start, json_end))
			end
		end

		if #data_lines == 0 then
			vim.notify("No valid JSON lines in the response body.", vim.log.levels.WARN)
			callback(nil)
			return
		end

		local completions = {}
		for _, line in ipairs(data_lines) do
			local ok, decoded = pcall(vim.json.decode, line)
			if not ok then
				vim.notify("Failed to decode JSON: " .. line .. " from " .. url, vim.log.levels.ERROR)
				callback(nil)
				return
			end
			if decoded.completion then
				table.insert(completions, decoded.completion)
			end
		end

		callback(table.concat(completions, ""))
	end, 1)()
end

return Chat
