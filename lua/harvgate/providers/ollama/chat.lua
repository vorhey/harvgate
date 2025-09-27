local curl = require("plenary.curl")
local async = require("plenary.async")
local utils = require("harvgate.utils")

---@class OllamaChat
---@field session OllamaSession
---@field conversation_id string
---@field primary_file string|nil
---@field additional_files table<string, string>
---@field pending_files table<string, string>
---@field has_sent_context boolean
---@field context_updated boolean
---@field messages table
---@field config table
---@field system_message string|nil
local Chat = {}
Chat.__index = Chat

local function normalize_content(content)
  if type(content) == "table" then
    return table.concat(content, "\n")
  end
  return content or ""
end

local function render_context_block(filename, content)
  local normalized = normalize_content(content)
  return string.format("Filename: %s\n```\n%s\n```", filename, normalized)
end

local function gather_context(self)
  local attachments = {}

  if not self.has_sent_context and self.primary_file and #self.primary_file > 0 then
    if vim.fn.filereadable(self.primary_file) == 1 then
      local content = vim.fn.readfile(self.primary_file)
      if content and #content > 0 then
        local filename = vim.fn.fnamemodify(self.primary_file, ":t")
        attachments[filename] = content
      end
    end
  end

  local files_to_send
  if not self.has_sent_context then
    files_to_send = self.additional_files or {}
  else
    files_to_send = self.pending_files or {}
  end

  for filename, content in pairs(files_to_send) do
    if not attachments[filename] then
      attachments[filename] = content
    end
  end

  if vim.tbl_isempty(attachments) then
    return nil
  end

  self.has_sent_context = true
  self.context_updated = false
  self.pending_files = {}

  local blocks = {}
  for filename, content in pairs(attachments) do
    blocks[#blocks + 1] = render_context_block(filename, content)
  end

  return table.concat(blocks, "\n\n")
end

local function build_user_message(prompt, context)
  local text = prompt
  if context and context ~= "" then
    text = string.format("%s\n\n[Context]\n%s", prompt, context)
  end

  return {
    role = "user",
    content = text,
  }
end

local function build_message_history(self, user_message)
  local history = {}

  if self.system_message and self.system_message ~= "" then
    history[#history + 1] = {
      role = "system",
      content = self.system_message,
    }
  end

  for _, message in ipairs(self.messages) do
    history[#history + 1] = message
  end

  history[#history + 1] = user_message

  return history
end

local function merge_options(session_options, chat_options)
  local merged = {}

  if type(session_options) == "table" then
    for key, value in pairs(session_options) do
      merged[key] = value
    end
  end

  if type(chat_options) == "table" then
    for key, value in pairs(chat_options) do
      merged[key] = value
    end
  end

  if vim.tbl_isempty(merged) then
    return nil
  end

  return merged
end

---@param session OllamaSession
---@param file_path string|nil
---@param additional_files table<string, string>|nil
---@param config table|nil
---@return OllamaChat
function Chat.new(session, file_path, additional_files, config)
  assert(type(session) == "table", "Invalid Ollama session")

  config = config or {}

  return setmetatable({
    session = session,
    conversation_id = utils.uuidv4(),
    primary_file = file_path,
    additional_files = additional_files or {},
    pending_files = {},
    has_sent_context = false,
    context_updated = false,
    messages = {},
    config = config,
    system_message = config.system_prompt or config.system,
    warned_stream = false,
  }, Chat)
end

Chat.create_chat = async.wrap(function(self, cb)
  cb(self.conversation_id, nil)
end, 2)

---@async
---@param chat_id string
---@param prompt string
---@param cb fun(response:string|nil, err:string|nil)
Chat.send_message = async.wrap(function(self, chat_id, prompt, cb)
  local context = gather_context(self)
  local user_message = build_user_message(prompt, context)
  local history = build_message_history(self, user_message)

  local requested_stream
  if self.config.stream ~= nil then
    requested_stream = self.config.stream
  elseif self.session.stream ~= nil then
    requested_stream = self.session.stream
  end

  if requested_stream and not self.warned_stream then
    self.warned_stream = true
    vim.schedule(function()
      vim.notify("harvgate.ollama: streaming responses are not yet supported; falling back to buffered responses", vim.log.levels.WARN)
    end)
  end

  local payload = {
    model = self.config.model or self.session.model,
    messages = history,
    stream = false,
  }

  if self.config.keep_alive ~= nil then
    payload.keep_alive = self.config.keep_alive
  elseif self.session.keep_alive ~= nil then
    payload.keep_alive = self.session.keep_alive
  end

  if self.config.format ~= nil then
    payload.format = self.config.format
  elseif self.session.format ~= nil then
    payload.format = self.session.format
  end

  local options = merge_options(self.session.options, self.config.options)
  if options then
    payload.options = options
  end

  local url, opts, err = self.session:build_request(payload)
  if not url then
    cb(nil, err)
    return
  end

  opts.callback = vim.schedule_wrap(function(response)
    if not response then
      cb(nil, "Failed to receive response")
      return
    end

    if response.status ~= 200 then
      local err_msg = string.format("Request failed with status: %d", response.status)
      if response.body and response.body ~= "" then
        local ok_body, decoded = pcall(vim.json.decode, response.body)
        if ok_body and type(decoded) == "table" then
          local message
          if type(decoded.error) == "table" then
            message = decoded.error.message or decoded.error.detail
          elseif type(decoded.error) == "string" then
            message = decoded.error
          elseif type(decoded.message) == "string" then
            message = decoded.message
          end

          if message and message ~= "" then
            err_msg = string.format("%s - %s", err_msg, message)
          end
        else
          err_msg = string.format("%s - %s", err_msg, vim.trim(response.body))
        end
      end
      cb(nil, err_msg)
      return
    end

    if not response.body or response.body == "" then
      cb(nil, "Empty response body")
      return
    end

    local ok, decoded = pcall(vim.json.decode, response.body)
    if not ok or type(decoded) ~= "table" then
      cb(nil, "Failed to decode response body")
      return
    end

    local content
    if decoded.message and type(decoded.message) == "table" then
      content = decoded.message.content
    end

    if not content or content == "" then
      if type(decoded.response) == "string" then
        content = decoded.response
      elseif type(decoded.output) == "string" then
        content = decoded.output
      elseif type(decoded.content) == "string" then
        content = decoded.content
      end
    end

    if not content or content == "" then
      cb(nil, "No completion returned")
      return
    end

    self.messages[#self.messages + 1] = user_message
    self.messages[#self.messages + 1] = {
      role = "assistant",
      content = content,
    }

    cb(content, nil)
  end)

  local ok_request, request_err = pcall(curl.post, url, opts)
  if not ok_request then
    cb(nil, request_err)
  end
end, 4)

function Chat:update_context(additional_files, should_merge)
  if not self.additional_files then
    self.additional_files = {}
  end

  self.pending_files = self.pending_files or {}

  if type(additional_files) == "table" then
    if not should_merge then
      self.additional_files = {}
      self.pending_files = {}
    end

    for filename, content in pairs(additional_files) do
      if not self.additional_files[filename] or self.additional_files[filename] ~= content then
        self.pending_files[filename] = content
        self.context_updated = true
      end

      self.additional_files[filename] = content
    end
  end
end

function Chat:get_all_chats()
  return nil, "Ollama provider does not expose chat history"
end

function Chat:get_single_chat(_)
  return nil, "Ollama provider does not expose chat history"
end

function Chat:get_all_unnamed_chats()
  return nil, "Ollama provider does not expose chat history"
end

function Chat:rename_chat(_, _)
  return nil
end

return Chat
