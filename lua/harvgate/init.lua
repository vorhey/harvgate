---@class Config
---@field cookie? string Claude AI cookie for authentication, can be set with $CLAUDE_COOKIE
---@field organization_id? string Optional organization ID
---@field model? string Optional model ID
---@field width? number Window width
---@field height? number Window width
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
	model = nil,
	width = nil,
	height = nil,
	keymaps = {
		new_chat = "<C-g>",
		toggle_zen_mode = "<C-r>",
		copy_code = "<C-y>",
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
	vim.api.nvim_create_user_command("HarvgateListChats", M.list_chats, {})
	vim.api.nvim_create_user_command("HarvgateAddBuffer", function(options)
		local bufnr = options.args ~= "" and tonumber(options.args) or vim.api.nvim_get_current_buf()
		M.add_buffer(bufnr)
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("HarvgateRemoveBuffer", function(options)
		local bufnr = options.args ~= "" and tonumber(options.args) or vim.api.nvim_get_current_buf()
		M.remove_buffer(bufnr)
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("HarvgateListBuffers", function()
		M.list_buffers()
	end, {})
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

function M.add_buffer(bufnr)
	if not session then
		session = setup_session()
	end
	if not session then
		vim.notify("harvgate: Session not initialized. Call setup() first", vim.log.levels.ERROR)
		return
	end

	ui.add_buffer_to_context(bufnr or vim.api.nvim_get_current_buf())
end

function M.remove_buffer(bufnr)
	ui.remove_buffer_from_context(bufnr or vim.api.nvim_get_current_buf())
end

function M.list_buffers()
	ui.list_context_buffers()
end

return M
