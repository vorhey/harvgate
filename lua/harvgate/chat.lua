local curl = require("plenary.curl")
local async = require("plenary.async")
local utils = require("harvgate.utils")

---@class Chat
---@field session Session
local Chat = {}
Chat.__index = Chat

local BASE_URL = "https://claude.ai"

local function new_chat_request_config(self, payload)
	return {
		headers = {
			["Host"] = "claude.ai",
			["User-Agent"] = self.session.user_agent,
			["Accept"] = "*/*",
			["Accept-Language"] = "en-US,en;q=0.5",
			["Accept-Encoding"] = "gzip, deflate, br",
			["Content-Type"] = "application/json",
			["Content-Length"] = #payload,
			["Referer"] = string.format("%s/chats", BASE_URL),
			["Origin"] = BASE_URL,
			["DNT"] = "1",
			["Sec-Fetch-Dest"] = "empty",
			["Sec-Fetch-Mode"] = "cors",
			["Sec-Fetch-Site"] = "same-origin",
			["Connection"] = "keep-alive",
			["Cookie"] = self.session.cookie,
			["TE"] = "trailers",
		},
		url = string.format("%s/api/organizations/%s/chat_conversations", BASE_URL, self.session.organization_id),
		body = payload,
		timeout = self.session.timeout,
	}
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
		message = {
			content = "Please give this chat a title based on my first message.",
			attachments = {},
			files = {},
		},
	}
	local encoded_payload = vim.json.encode(payload)
	local config = new_chat_request_config(self, encoded_payload)

	local function send_request(options, callback)
		curl.post({
			url = config.url,
			headers = config.headers,
			body = encoded_payload,
			timeout = self.session.timeout,
			http_version = options.http_version,
			raw = options.raw,
			callback = vim.schedule_wrap(function(response)
				if not response then
					callback(nil, "Async error: Failed to receive response.")
					return
				end

				if response.status ~= 201 then
					callback(nil, string.format("Request failed with status: %d", response.status))
					return
				end

				local ok, j = pcall(vim.json.decode, response.body)
				if not ok then
					callback(nil, "Failed to decode response JSON")
					return
				end

				callback(j.uuid, nil)
			end),
		})
	end

	send_request({ http_version = "HTTP/2", raw = { "--tlsv1.3", "--ipv4" } }, function(result)
		if result then
			cb(result)
			return
		end

		send_request({}, function(retry_result)
			if retry_result then
				cb(retry_result)
			else
				cb(nil)
			end
		end)
	end)
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

	local function send_request(options, callback)
		curl.post({
			url = url,
			headers = headers,
			body = encoded_payload,
			timeout = self.session.timeout,
			http_version = options.http_version,
			raw = options.raw,
			callback = vim.schedule_wrap(function(response)
				if not response or response.status ~= 200 then
					callback(
						nil,
						string.format(
							"Failed to send message to %s: %s",
							url,
							response and response.status or "no response"
						)
					)
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
					callback(nil, "No valid JSON lines in the response body.")
					return
				end

				local completions = {}
				for _, line in ipairs(data_lines) do
					local ok, decoded = pcall(vim.json.decode, line)
					if not ok then
						callback(nil, "Failed to decode JSON: " .. line)
						return
					end
					if decoded.completion then
						table.insert(completions, decoded.completion)
					end
				end

				callback(table.concat(completions, ""), nil)
			end),
		})
	end

	-- First attempt
	send_request({ http_version = "HTTP/2", raw = { "--tlsv1.3", "--ipv4" } }, function(result)
		if result then
			cb(result)
			return
		end

		-- Retry without http_version and raw if the first attempt fails
		send_request({}, function(retry_result)
			if retry_result then
				cb(retry_result)
			else
				cb(nil)
			end
		end)
	end)
end, 4)

Chat.list_chats = async.wrap(function(self, cb)
	local url = string.format("%s/api/organizations/%s/chat_conversations", BASE_URL, self.session.organization_id)
	local headers = {
		["Host"] = "claude.ai",
		["User-Agent"] = self.session.user_agent,
		["Accept"] = "application/json",
		["Accept-Language"] = "en-US,en;q=0.5",
		["Accept-Encoding"] = "gzip, deflate, br",
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
	curl.get({
		url = url,
		headers = headers,
		timeout = self.session.timeout,
		http_version = "HTTP/2",
		raw = {
			"--tlsv1.3",
			"--ipv4",
		},
		callback = vim.schedule_wrap(function(response)
			if not response then
				vim.notify("Async error: Failed to receive response.", vim.log.levels.ERROR)
				cb(nil)
				return
			end
			if response.status ~= 200 then
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
			cb(j)
		end),
	})
end, 2)

Chat.list_chats = async.wrap(function(self, cb)
	local url = string.format("%s/api/organizations/%s/chat_conversations", BASE_URL, self.session.organization_id)
	local headers = {
		["Host"] = "claude.ai",
		["User-Agent"] = self.session.user_agent,
		["Accept"] = "application/json",
		["Accept-Language"] = "en-US,en;q=0.5",
		["Accept-Encoding"] = "gzip, deflate, br",
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
	curl.get({
		url = url,
		headers = headers,
		timeout = self.session.timeout,
		http_version = "HTTP/2",
		raw = {
			"--tlsv1.3",
			"--ipv4",
		},
		callback = vim.schedule_wrap(function(response)
			if not response then
				vim.notify("Async error: Failed to receive response.", vim.log.levels.ERROR)
				cb(nil)
				return
			end
			if response.status ~= 200 then
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
			cb(j)
		end),
	})
end, 2)

return Chat
