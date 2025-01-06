---@class Session

---@class RequestConfig
---@field headers table<string, string>
---@field url string
---@field body? string
---@field timeout? number

---@class RequestBuilder
---@field private session Session
---@field private config RequestConfig
local RequestBuilder = {}
RequestBuilder.__index = RequestBuilder

local BASE_URL = "https://claude.ai"

---@param session Session
---@return RequestBuilder
function RequestBuilder.new(session)
	return setmetatable({
		session = session,
		config = {
			headers = {
				["Host"] = "claude.ai",
				["User-Agent"] = session.user_agent,
				["Accept-Language"] = "en-US,en;q=0.5",
				["Accept-Encoding"] = "gzip, deflate, br",
				["Origin"] = BASE_URL,
				["DNT"] = "1",
				["Sec-Fetch-Dest"] = "empty",
				["Sec-Fetch-Mode"] = "cors",
				["Sec-Fetch-Site"] = "same-origin",
				["Connection"] = "keep-alive",
				["Cookie"] = session.cookie,
				["TE"] = "trailers",
			},
		},
	}, RequestBuilder)
end

---@return RequestBuilder
function RequestBuilder:for_chat_creation()
	self.config.headers["Accept"] = "*/*"
	self.config.headers["Content-Type"] = "application/json"
	self.config.headers["Referer"] = string.format("%s/chats", BASE_URL)
	self.config.url =
		string.format("%s/api/organizations/%s/chat_conversations", BASE_URL, self.session.organization_id)
	return self
end

---@param chat_id string
---@return RequestBuilder
function RequestBuilder:for_message_sending(chat_id)
	self.config.headers["Accept"] = "text/event-stream, text/event-stream"
	self.config.headers["Content-Type"] = "application/json"
	self.config.headers["Referer"] = string.format("%s/chat/%s", BASE_URL, chat_id)
	self.config.url = string.format(
		"%s/api/organizations/%s/chat_conversations/%s/completion",
		BASE_URL,
		self.session.organization_id,
		chat_id
	)
	return self
end

---@return RequestBuilder
function RequestBuilder:for_chat_listing()
	self.config.headers["Accept"] = "application/json"
	self.config.headers["Referer"] = string.format("%s/chats", BASE_URL)
	self.config.url =
		string.format("%s/api/organizations/%s/chat_conversations", BASE_URL, self.session.organization_id)
	return self
end

---@param payload table
---@return RequestBuilder
function RequestBuilder:with_body(payload)
	local encoded_payload = vim.json.encode(payload)
	self.config.body = encoded_payload
	self.config.headers["Content-Length"] = tostring(#encoded_payload)
	return self
end

---@return RequestBuilder
function RequestBuilder:with_timeout()
	self.config.timeout = self.session.timeout
	return self
end

---@return RequestConfig
function RequestBuilder:build()
	return self.config
end

return RequestBuilder
