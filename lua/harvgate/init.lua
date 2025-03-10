---@class Config
---@field cookie? string Claude AI cookie for authentication, can be set with $CLAUDE_COOKIE
---@field organization_id? string Optional organization ID
---@field model? string Optional model ID
---@field width? number Window width
---@field keymaps? table Table Keybinding configurations
---@field highlights? table Table Highlight configurations
---@field icons? table Table Icons configurations

local ui = require("harvgate.ui")
local Session = require("harvgate.session")

---@type Session|nil
local session = nil
local M = {}

-- Default configuration
local default_config = {
	cookie = os.getenv("CLAUDE_COOKIE"),
	organization_id = nil,
	model = nil,
	width = nil,
	keymaps = {
		new_chat = "<C-g>",
		toggle_zen_mode = "<C-r>",
		copy_code = "<C-y>",
	},
	highlights = {
		claude_label_bg = "#423b37",
		claude_label_fg = "#E6B99D",
		user_label_bg = "#3b3b3b",
		user_label_fg = "#919191",
	},
	icons = {
		chat = "󰭹",
		default_file = "",
		input = "",
	},
}

local function setup_session()
	return Session.new(M.config.cookie, M.config.organization_id, M.config.model)
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
	vim.api.nvim_create_user_command("HarvgateListChats", M.list_chats, {})
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

function M.list_chats()
	if not session then
		session = setup_session()
	end
	if not session then
		vim.notify("harvgate: Session not initialized. Call setup() first", vim.log.levels.ERROR)
		return
	end

	ui.list_chats(session)
end

return M
