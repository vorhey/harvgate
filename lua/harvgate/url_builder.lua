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
function URLBuilder:create_chat(organization_id)
	return string.format("%s/api/organizations/%s/chat_conversations", self.base_url, organization_id)
end

---@param organization_id string
---@param chat_id string
---@return string
function URLBuilder:send_message(organization_id, chat_id)
	return string.format(
		"%s/api/organizations/%s/chat_conversations/%s/completion",
		self.base_url,
		organization_id,
		chat_id
	)
end

---@param organization_id string
---@return string
function URLBuilder:get_all_chats(organization_id)
	return string.format("%s/api/organizations/%s/chat_conversations", self.base_url, organization_id)
end

---@param organization_id string
---@param chat_id string
---@return string
function URLBuilder:rename_chat(organization_id, chat_id)
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

---@return string
function URLBuilder:get_single_chat(organization_id, chat_id)
	return string.format(
		"%s/api/organizations/%s/chat_conversations/%s?tree=True&rendering_mode=messages",
		self.base_url,
		organization_id,
		chat_id
	)
end

return URLBuilder
