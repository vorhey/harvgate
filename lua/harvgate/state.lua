local M = {}

-- Chat and session state
M.config = nil
M.session = nil
M.chat_window = nil
M.chat = nil
M.chat_id = nil
M.is_chat_visible = nil

-- History tracking
M.message_history = {}
M.input_history = {}
M.last_displayed_message = 0

-- Buffer management
M.source_buf = nil
M.context_buffers = {}

-- UI state
M.zen_mode = false

return M
