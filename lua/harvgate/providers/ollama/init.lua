local Session = require("harvgate.providers.ollama.session")
local Chat = require("harvgate.providers.ollama.chat")

local provider = {}

function provider.new_session(config)
  return Session.new(config)
end

function provider.new_chat(session, primary_file, additional_files, config)
  return Chat.new(session, primary_file, additional_files, config or {})
end

function provider.display_name()
  return "Ollama Cloud"
end

function provider.validate_config(config)
  if not config or config.api_key == nil or config.api_key == "" then
    return false, "harvgate.ollama: missing API key"
  end
  return true
end

function provider.supports_list_chats()
  return false
end

return provider
