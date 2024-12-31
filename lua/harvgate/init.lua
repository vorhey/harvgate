---@class Config
---@field cookie string Claude AI cookie for authentication
---@field organization_id? string Optional organization ID
---@field user_agent? string Custom user agent string
---@field timeout? number Request timeout in milliseconds

local ui = require("harvgate.ui")
local Session = require("harvgate.session")
local Chat = require("harvgate.chat")

---@type Session|nil
local session = nil

local M = {}

-- Default configuration
local default_config = {
	cookie = os.getenv("CLAUDE_COOKIE"),
	organization_id = nil,
	user_agent = nil,
	timeout = 30000,
}

local function setup_session()
	return Session.new(M.config.cookie, M.config.organization_id, M.config.user_agent, M.config.timeout)
end

---@type Config
M.config = vim.deepcopy(default_config)

---Setup the plugin with user configuration
---@param opts? Config
function M.setup(opts)
	-- Merge user config with defaults
	opts = opts or {}
	M.config = vim.tbl_deep_extend("force", default_config, opts)

	-- Validate required configuration
	if not M.config.cookie then
		vim.notify("harvgate: cookie is required in setup()", vim.log.levels.ERROR)
		return
	end

	-- Create user commands
	vim.api.nvim_create_user_command("HarvgateChat", M.toggle, {})
end

---Toggle the Claude chat window
function M.toggle()
	if not session then
		session = setup_session()
	end

	if not session then
		vim.notify("harvgate: Session not initialized. Call setup() first", vim.log.levels.ERROR)
		return
	end

	ui.toggle_chat(session)
end

---Get a new chat instance
---@return Chat
function M.get_chat()
	if not session then
		error("harvgate: Session not initialized. Call setup() first")
	end
	return Chat.new(session)
end

-- Health check module
M.health = require("harvgate.healthcheck")

return M
