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
Chat.create_chat = async.wrap(function(self, cb)
	local url = string.format("%s/api/organizations/%s/chat_conversations", BASE_URL, self.session.organization_id)
	local new_uuid = utils.uuidv4()
	local payload = {
		name = "",
		uuid = new_uuid,
		message = {
			content = "Please give this chat a title based on my first message.",
			attachments = {},
			files = {},
		},
	}
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

	curl.post({
		url = url,
		headers = headers,
		body = encoded_payload,
		timeout = self.session.timeout,
		agent = "chrome110",
		callback = vim.schedule_wrap(function(response)
			if not response then
				vim.notify("Async error: Failed to receive response.", vim.log.levels.ERROR)
				cb(nil)
				return
			end

			if response.status ~= 201 then
				vim.notify(
					string.format("Request to %s failed with status: %d", url, response.status),
					vim.log.levels.ERROR
				)
				cb(nil)
				return
			end

			local ok, j = pcall(vim.json.decode, response.body)
			if not ok then
				vim.notify("Failed to decode response JSON", vim.log.levels.ERROR)
				cb(nil)
				return
			end

			cb(j.uuid)
		end),
	})
end, 2)

-- Send a message to the chat conversation and return the response.
---@async
---@param chat_id string The ID of the chat conversation.
---@param prompt string The message to send.
---@return string|nil The decoded response from the server, or nil if an error occurred.
Chat.send_message = async.wrap(function(self, chat_id, prompt, cb)
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

	curl.post({
		url = url,
		headers = headers,
		body = encoded_payload,
		timeout = self.session.timeout,
		agent = "chrome110",
		callback = vim.schedule_wrap(function(response)
			if not response or response.status ~= 200 then
				vim.notify(
					string.format(
						"Failed to send message to %s: %s",
						url,
						response and response.status or "no response"
					),
					vim.log.levels.ERROR
				)
				cb(nil)
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
				cb(nil)
				return
			end

			local completions = {}
			for _, line in ipairs(data_lines) do
				local ok, decoded = pcall(vim.json.decode, line)
				if not ok then
					vim.notify("Failed to decode JSON: " .. line .. " from " .. url, vim.log.levels.ERROR)
					cb(nil)
					return
				end
				if decoded.completion then
					table.insert(completions, decoded.completion)
				end
			end

			cb(table.concat(completions, ""))
		end),
	})
end, 4)

return Chat
