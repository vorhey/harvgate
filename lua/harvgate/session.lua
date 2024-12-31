local curl = require("plenary.curl")
local async = require("plenary.async")

---@class Session
---@field cookie string
---@field user_agent string
---@field organization_id string
---@field timeout number
local M = {}
M.__index = M

local DEFAULT_USER_AGENT =
	"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36"
local DEFAULT_TIMEOUT = 30000
local BASE_URL = "https://claude.ai"

---@param cookie string
---@param organization_id string | nil
---@param user_agent string | nil
---@param timeout number | nil
---@return Session
function M.new(cookie, organization_id, user_agent, timeout)
	assert(cookie and #cookie > 0, "Cookie is required and must be a non-empty string.")

	local self = setmetatable({
		cookie = cookie,
		user_agent = user_agent or DEFAULT_USER_AGENT,
		timeout = timeout or DEFAULT_TIMEOUT,
	}, M)

	if not organization_id then
		async.run(function()
			local organization_uuid = self:get_organization_id()
			if not organization_uuid then
				error("No organization ID returned")
			end
			self.organization_id = organization_uuid
		end)
	else
		self.organization_id = organization_id
	end

	return self
end

function M:get_organization_id()
	local url = string.format("%s/api/organizations", BASE_URL)
	local headers = {
		["Accept-Encoding"] = "gzip, deflate, br",
		["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
		["Accept-Language"] = "en-US,en;q=0.5",
		["Connection"] = "keep-alive",
		["Cookie"] = self.cookie,
		["Host"] = "claude.ai",
		["DNT"] = "1",
		["Sec-Fetch-Dest"] = "document",
		["Sec-Fetch-Mode"] = "navigate",
		["Sec-Fetch-Site"] = "none",
		["Sec-Fetch-User"] = "?1",
		["Upgrade-Insecure-Requests"] = "1",
		["User-Agent"] = self.user_agent,
	}

	local response = curl.get({
		url = url,
		headers = headers,
		timeout = self.timeout,
		agent = "chrome110",
	})

	if response.status == 200 and response.body then
		local success, json = pcall(vim.json.decode, response.body)
		if success and json then
			for _, item in ipairs(json) do
				if item.api_disabled_reason == vim.NIL then
					return item.uuid
				end
			end
		end
	end

	error(string.format("Cannot retrieve Organization ID!\n%s", response.body))
end

return M
