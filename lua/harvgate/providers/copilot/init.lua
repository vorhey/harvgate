local Session = require("harvgate.providers.copilot.session")
local Chat = require("harvgate.providers.copilot.chat")
local utils = require("harvgate.providers.copilot.utils")

local provider = {}

function provider.new_session(config)
	return Session.new(config)
end

function provider.new_chat(session, primary_file, additional_files, config)
	return Chat.new(session, primary_file, additional_files, config or {})
end

function provider.display_name()
	return "Copilot"
end

local function has_auth_source(config)
	if config and config.token and config.token ~= "" then
		return true
	end

	if os.getenv("COPILOT_TOKEN") and os.getenv("COPILOT_TOKEN") ~= "" then
		return true
	end

	local ok = pcall(require, "copilot.auth")
	if ok then
		return true
	end

	local token = utils.read_hosts_token()
	if token then
		return true
	end

	return false
end

function provider.validate_config(config)
	if has_auth_source(config) then
		return true
	end

	return false,
		"harvgate.copilot: unable to locate an authentication token. Install copilot.lua or provide COPILOT_TOKEN/token in the provider configuration."
end

function provider.supports_list_chats()
	return false
end

return provider
