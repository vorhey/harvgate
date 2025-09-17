local Session = require("harvgate.providers.claude.session")
local Chat = require("harvgate.providers.claude.chat")

local provider = {}

function provider.new_session(config)
  return Session.new(config.cookie, config.organization_id, config.model)
end

function provider.new_chat(session, primary_file, additional_files, _)
  return Chat.new(session, primary_file, additional_files)
end

function provider.display_name()
  return "Claude"
end

function provider.validate_config(config)
  if not config.cookie or config.cookie == "" then
    return false, "harvgate.claude: missing cookie"
  end
  return true, nil
end

function provider.supports_list_chats()
  return true
end

return provider
