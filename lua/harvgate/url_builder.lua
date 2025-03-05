---@class URLBuilder
---@field private base_url string
local URLBuilder = {}
URLBuilder.__index = URLBuilder

-- Initialize with the base URL
---@return URLBuilder
function URLBuilder.new()
	return setmetatable({
		base_url = "https://claude.ai",
	}, URLBuilder)
end

---@param organization_id string
---@return string
function URLBuilder:chat_creation(organization_id)
	return string.format("%s/api/organizations/%s/chat_conversations", self.base_url, organization_id)
end

---@param organization_id string
---@param chat_id string
---@return string
function URLBuilder:message_sending(organization_id, chat_id)
	return string.format(
		"%s/api/organizations/%s/chat_conversations/%s/completion",
		self.base_url,
		organization_id,
		chat_id
	)
end

---@param organization_id string
---@return string
function URLBuilder:chat_listing(organization_id)
	return string.format("%s/api/organizations/%s/chat_conversations", self.base_url, organization_id)
end

---@param organization_id string
---@param chat_id string
---@return string
function URLBuilder:chat_renaming(organization_id, chat_id)
	return string.format("%s/api/organizations/%s/chat_conversations/%s/title", self.base_url, organization_id, chat_id)
end

---@param chat_id string
---@return string
function URLBuilder:chat_referrer(chat_id)
	return string.format("%s/chat/%s", self.base_url, chat_id)
end

---@return string
function URLBuilder:chats_referrer()
	return string.format("%s/chats", self.base_url)
end

return URLBuilder
