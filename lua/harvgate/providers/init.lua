local providers = {}

local function load_provider(name)
  if providers[name] then
    return providers[name]
  end

  if name == "claude" then
    providers[name] = require("harvgate.providers.claude")
  elseif name == "copilot" then
    providers[name] = require("harvgate.providers.copilot")
  elseif name == "ollama" then
    providers[name] = require("harvgate.providers.ollama")
  else
    error(string.format("harvgate: unknown provider '%s'", tostring(name)))
  end

  return providers[name]
end

return {
  get = function(name)
    local provider_name = name or "claude"
    return load_provider(provider_name)
  end,
  load = load_provider,
}
