local curl = require("plenary.curl")
local async = require("plenary.async")
local strategies = require("harvgate.providers.claude.strategies")

---@class Session
---@field cookie string
---@field user_agent string
---@field model string | nil
---@field organization_id string
local M = {}
M.__index = M

local DEFAULT_USER_AGENT =
	"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
local BASE_URL = "https://claude.ai"

function M:request(url)
	local last_error
	for _, strategy in ipairs(strategies) do
		local headers = strategy.headers(self)
		local options = strategy.options()

		local success, response = pcall(
			curl.get,
			vim.tbl_extend("force", {
				url = url,
				headers = headers,
			}, options)
		)

		if success and response.status == 200 then
			return response
		end
		last_error = response or "Request failed"
	end
	error("All strategies failed. Last error: " .. vim.inspect(last_error))
end

---@param cookie string
---@param organization_id string | nil
---@return Session
function M.new(cookie, organization_id, model)
	assert(cookie and #cookie > 0, "Cookie is required and must be a non-empty string.")

	local self = setmetatable({
		cookie = cookie,
		user_agent = DEFAULT_USER_AGENT,
		model = model,
	}, M)

	if not organization_id then
		async.run(function()
			local organization_uuid = self:get_organization_id()
			if not organization_uuid then
				error("No organization ID returned")
			end
			self.organization_id = organization_uuid
			if self.model then
				self:set_model(organization_uuid, self.model)
			end
		end)
	else
		self.organization_id = organization_id
	end

	return self
end

function M:get_organization_id()
	local response = self:request(BASE_URL .. "/api/organizations")
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

function M:set_model(organization_id, model_id)
	local url = string.format("%s/api/organizations/%s/model_configs/%s", BASE_URL, organization_id, model_id)
	curl.get({
		url = url,
		headers = {
			["Host"] = "claude.ai",
			["User-Agent"] = self.user_agent,
			["Accept-Language"] = "en-US,en;q=0.5",
			["Accept-Encoding"] = "gzip, deflate, br",
			["Origin"] = BASE_URL,
			["DNT"] = "1",
			["Sec-Fetch-Dest"] = "empty",
			["Sec-Fetch-Mode"] = "cors",
			["Sec-Fetch-Site"] = "same-origin",
			["Connection"] = "keep-alive",
			["Cookie"] = self.cookie,
			["TE"] = "trailers",
		},
	})
end

return M
