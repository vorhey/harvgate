local utils = require("harvgate.providers.copilot.utils")

---@class CopilotSession
---@field model string
---@field temperature number
---@field top_p number
---@field static_token string|nil
---@field token string|nil
---@field expires_at number|nil
---@field auth table|nil
---@field integration_id string
---@field editor_version string
---@field plugin_version string
---@field user_agent string
---@field endpoint string
local Session = {}
Session.__index = Session

local DEFAULT_MODEL = "gpt-4o-mini"
local API_URL = "https://api.githubcopilot.com/chat/completions"
local TOKEN_REFRESH_BUFFER = 60 -- seconds

local function extract_token_from_auth(auth)
	if type(auth) ~= "table" then
		return nil, nil
	end

	local getter = auth.get_current_token or auth.current_token
	if type(getter) ~= "function" then
		return nil, nil
	end

	local ok, token_data = pcall(getter)
	if not ok then
		return nil, nil
	end

	if type(token_data) == "string" then
		return token_data, nil
	end

	if type(token_data) == "table" then
		local token = token_data.token or token_data.oauth_token
		local expires_at = token_data.expires_at
		if type(expires_at) == "string" then
			expires_at = utils.parse_expires_at(expires_at)
		end
		return token, expires_at
	end

	return nil, nil
end

local function ensure_auth(auth)
	if type(auth) ~= "table" then
		return
	end

	local ensure = auth.ensure_auth or auth.ensure_token
	if type(ensure) == "function" then
		pcall(ensure)
	end
end

---@param config table
---@return CopilotSession
function Session.new(config)
	config = config or {}

	local self = setmetatable({
		model = config.model or DEFAULT_MODEL,
		temperature = config.temperature or 0.2,
		top_p = config.top_p or 1,
		static_token = config.token,
		token = nil,
		expires_at = nil,
		auth = nil,
		integration_id = config.integration_id or "harvgate.nvim",
		editor_version = config.editor_version or utils.editor_version(),
		plugin_version = config.plugin_version or utils.plugin_version(),
		user_agent = config.user_agent or "harvgate.nvim",
		endpoint = API_URL,
	}, Session)

	if not self.static_token then
		local ok, auth_module = pcall(require, "copilot.auth")
		if ok and type(auth_module) == "table" then
			self.auth = auth_module
			ensure_auth(self.auth)
			self.token, self.expires_at = extract_token_from_auth(self.auth)
		end

		if not self.token then
			self.token, self.expires_at = utils.read_hosts_token()
		end
	else
		self.token = self.static_token
	end

	return self
end

---@return string|nil, string|nil
function Session:get_token()
	if self.static_token then
		return self.static_token, nil
	end

	local now = os.time()
	if self.token and (not self.expires_at or (self.expires_at - now) > TOKEN_REFRESH_BUFFER) then
		return self.token, nil
	end

	if self.auth then
		ensure_auth(self.auth)
		local token, expires = extract_token_from_auth(self.auth)
		if token then
			self.token = token
			self.expires_at = expires
			return self.token, nil
		end
	end

	local token, expires = utils.read_hosts_token()
	if token then
		self.token = token
		self.expires_at = expires
		return self.token, nil
	end

	return nil, "Unable to retrieve Copilot authentication token"
end

---@return table<string, string>|nil, string|nil
function Session:build_headers()
	local token, err = self:get_token()
	if not token then
		return nil, err
	end

	return {
		["Authorization"] = "Bearer " .. token,
		["Content-Type"] = "application/json",
		["Accept"] = "text/event-stream",
		["Editor-Version"] = self.editor_version,
		["Editor-Plugin-Version"] = self.plugin_version,
		["Copilot-Integration-Id"] = self.integration_id,
		["User-Agent"] = self.user_agent,
		["OpenAI-Intent"] = "conversation",
	}, nil
end

---@param payload table
---@return string|nil, table|nil, string|nil
function Session:build_request(payload)
	local headers, err = self:build_headers()
	if not headers then
		return nil, nil, err
	end

	local encoded = vim.json.encode(payload)
	headers["Content-Length"] = tostring(#encoded)

	return self.endpoint, {
		headers = headers,
		body = encoded,
	}, nil
end

return Session
