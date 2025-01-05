---@class Config
---@field cookie string Claude AI cookie for authentication
---@field organization_id? string Optional organization ID
---@field width? number Window width
---@field height? number Window height
---@field keymaps? table Table Keybinding configurations

local ui = require("harvgate.ui")
local Session = require("harvgate.session")

---@type Session|nil
local session = nil

local M = {}

-- Default configuration
local default_config = {
	cookie = os.getenv("CLAUDE_COOKIE"),
	organization_id = nil,
	width = nil,
	height = nil,
	keymaps = {
		new_chat = "<C-g>",
	},
}

local function setup_session()
	return Session.new(M.config.cookie, M.config.organization_id)
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
		vim.notify("harvgate: cookie is required in setup()", vim.log.levels.INFO)
		return
	end

	ui.setup(M.config)

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

	ui.window_toggle(session)
end

return M
