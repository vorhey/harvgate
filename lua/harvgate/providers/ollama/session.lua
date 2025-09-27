---@class OllamaSession
---@field api_key string
---@field model string
---@field base_url string
---@field stream boolean
---@field timeout integer
---@field keep_alive string|number|nil
---@field format string|nil
---@field options table<string, any>|nil
---@field headers table<string, string>|nil
local Session = {}
Session.__index = Session

local DEFAULT_MODEL = "gpt-oss:120b"
local DEFAULT_BASE_URL = "https://ollama.com/api/chat"
local DEFAULT_TIMEOUT = 30000 -- milliseconds

---@param config table|nil
---@return OllamaSession
function Session.new(config)
  config = config or {}

  local self = setmetatable({
    api_key = config.api_key,
    model = config.model or DEFAULT_MODEL,
    base_url = config.base_url or DEFAULT_BASE_URL,
    stream = config.stream == true,
    timeout = config.timeout or DEFAULT_TIMEOUT,
    keep_alive = config.keep_alive,
    format = config.format,
    options = config.options,
    headers = config.headers,
  }, Session)

  return self
end

---@return table<string, string>|nil, string|nil
function Session:build_headers()
  if not self.api_key or self.api_key == "" then
    return nil, "Missing Ollama Cloud API key"
  end

  local headers = {
    ["Authorization"] = "Bearer " .. self.api_key,
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/json",
  }

  if type(self.headers) == "table" then
    for key, value in pairs(self.headers) do
      headers[key] = value
    end
  end

  return headers, nil
end

---@param payload table
---@return string|nil, table|nil, string|nil
function Session:build_request(payload)
  local headers, err = self:build_headers()
  if not headers then
    return nil, nil, err
  end

  local ok, body = pcall(vim.json.encode, payload)
  if not ok then
    return nil, nil, "Failed to encode request payload"
  end

  return self.base_url, {
    headers = headers,
    body = body,
    timeout = self.timeout,
  }, nil
end

return Session
