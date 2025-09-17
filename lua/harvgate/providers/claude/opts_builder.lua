local utils = require("harvgate.utils")
---@class Session

---@class OptionsConfig
---@field headers table<string, string>
---@field body? string

---@class OptionsBuilder
---@field private session Session
---@field private config OptionsConfig
local OptionsBuilder = {}
OptionsBuilder.__index = OptionsBuilder

local BASE_URL = "https://claude.ai"

---@param session Session
---@return OptionsBuilder
function OptionsBuilder.new(session)
	local headers = {
		["Host"] = "claude.ai",
		["User-Agent"] = session.user_agent,
		["Accept-Language"] = "en-US,en;q=0.5",
		["Origin"] = BASE_URL,
		["DNT"] = "1",
		["Sec-Fetch-Dest"] = "empty",
		["Sec-Fetch-Mode"] = "cors",
		["Sec-Fetch-Site"] = "same-origin",
		["Connection"] = "keep-alive",
		["Cookie"] = session.cookie,
		["TE"] = "trailers",
	}
	if vim.fn.has("win32") == 1 then
		headers["Accept-Encoding"] = "identity"
	end

	return setmetatable({
		session = session,
		config = {
			headers = headers,
		},
	}, OptionsBuilder)
end

---@return OptionsBuilder
function OptionsBuilder:create_chat()
	self.config.headers["Accept"] = "*/*"
	self.config.headers["Content-Type"] = "application/json"
	self.config.headers["Referer"] = string.format("%s/chats", BASE_URL)
	return self
end

---@param chat_id string
---@return OptionsBuilder
function OptionsBuilder:send_message(chat_id)
	self.config.headers["Accept"] = "text/event-stream, text/event-stream"
	self.config.headers["Content-Type"] = "application/json"
	self.config.headers["Referer"] = string.format("%s/chat/%s", BASE_URL, chat_id)
	return self
end

---@return OptionsBuilder
function OptionsBuilder:get_all_chats()
	self.config.headers["Accept"] = "application/json"
	self.config.headers["Referer"] = string.format("%s/chats", BASE_URL)
	return self
end

---@return OptionsBuilder
function OptionsBuilder:get_single_chat(chat_id)
	self.config.headers["Accept"] = "application/json"
	self.config.headers["Referer"] = string.format("%s/chat/%s", BASE_URL, chat_id)
	return self
end

---@param payload table
---@return OptionsBuilder
function OptionsBuilder:with_body(payload)
	local encoded_payload = vim.json.encode(payload)
	self.config.body = encoded_payload
	self.config.headers["Content-Length"] = tostring(#encoded_payload)
	return self
end

---@return OptionsBuilder
function OptionsBuilder:rename_chat()
	self.config.headers["Accept"] = "*/*"
	self.config.headers["Content-Type"] = "application/json"
	return self
end

---@return OptionsConfig
function OptionsBuilder:build()
	local curl_opts = {
		headers = self.config.headers,
		body = self.config.body,
	}

	if vim.fn.has("win32") == 1 then
		curl_opts.raw = { "--tlsv1.3", "--ipv4" }
	end

	if utils.is_distro({ "ubuntu", "debian", "Pop!_OS", "Linux Mint" }) then
		curl_opts.http_version = "HTTP/2"
		curl_opts.raw = { "--tlsv1.3", "--ipv4" }
	end

	return curl_opts
end

return OptionsBuilder
