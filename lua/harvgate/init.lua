---@class ProviderConfig
---@field provider? string Provider identifier ("claude" or "copilot")
---@field providers? table<string, table> Provider specific configuration
---@field cookie? string Legacy Claude cookie, can be set via $CLAUDE_COOKIE
---@field organization_id? string Optional Claude organization ID
---@field model? string Optional Claude model ID
---@field token? string Optional Copilot access token
---@field organization? string Optional Copilot organization slug
---@field copilot_model? string Optional Copilot model name
---@field width? number Window width
---@field height? number Window height
---@field keymaps? table<string, string> Keybinding configuration

local ui = require("harvgate.ui")
local providers = require("harvgate.providers")
local state = require("harvgate.state")

---@type table|nil
local active_provider = nil
---@type table|nil
local session = nil
local M = {}

local default_config = {
	provider = "claude",
	cookie = os.getenv("CLAUDE_COOKIE"),
	organization_id = nil,
	model = nil,
	token = nil,
	organization = nil,
	copilot_model = nil,
	width = nil,
	height = nil,
	keymaps = {
		new_chat = "<C-g>",
		toggle_zen_mode = "<C-r>",
		copy_code = "<C-y>",
	},
	providers = {},
}

---@return table<string, any>
local function build_provider_config(provider_name)
	local provider_configs = M.config.providers or {}
	local config = vim.deepcopy(provider_configs[provider_name] or {})

	if provider_name == "claude" then
		config.cookie = config.cookie or M.config.cookie or os.getenv("CLAUDE_COOKIE")
		config.organization_id = config.organization_id or M.config.organization_id
		config.model = config.model or M.config.model
	elseif provider_name == "copilot" then
		config.token = config.token or M.config.token or os.getenv("COPILOT_TOKEN")
		config.organization = config.organization or M.config.organization
		config.model = config.model or M.config.copilot_model
	end

	return config
end

---@return table|nil, string
local function load_provider()
	local provider_name = M.config.provider or "claude"
	if active_provider and state.provider_name == provider_name then
		return active_provider, provider_name
	end

	local ok, provider_or_err = pcall(providers.get, provider_name)
	if not ok then
		vim.notify("harvgate: " .. provider_or_err, vim.log.levels.ERROR)
		return nil, provider_name
	end

	active_provider = provider_or_err
	state.provider = active_provider
	state.provider_name = provider_name
	state.provider_label = (active_provider.display_name and active_provider.display_name()) or provider_name

	return active_provider, provider_name
end

---@param provider table|nil
---@return boolean
local function provider_supports_listing(provider)
	if not provider then
		return false
	end

	local value = provider.supports_list_chats
	if value == nil then
		return true
	end

	if type(value) == "function" then
		local ok, result = pcall(value, provider)
		if not ok then
			vim.notify("harvgate: failed to detect provider capabilities - " .. result, vim.log.levels.WARN)
			return false
		end
		return result
	end

	return value == true
end

---@param provider table
---@param provider_name string
---@param provider_config table
---@return boolean
local function validate_provider(provider, provider_name, provider_config)
	if provider.validate_config then
		local ok, err = provider.validate_config(provider_config)
		if not ok then
			vim.notify(err or string.format("harvgate: invalid configuration for provider '%s'", provider_name), vim.log.levels.ERROR)
			return false
		end
	end

	return true
end

---@return table|nil
local function setup_session()
	if session then
		return session
	end

	local provider, provider_name = load_provider()
	if not provider then
		return nil
	end

	local provider_config = build_provider_config(provider_name)
	if not validate_provider(provider, provider_name, provider_config) then
		return nil
	end

	local ok, new_session = pcall(provider.new_session, provider_config)
	if not ok then
		vim.notify(
			string.format("harvgate: failed to establish %s session - %s", provider_name, new_session),
			vim.log.levels.ERROR
		)
		return nil
	end

	session = new_session
	state.provider_config = provider_config

	return session
end

---@type ProviderConfig
M.config = vim.deepcopy(default_config)

---Setup the plugin with user configuration
---@param opts? ProviderConfig
function M.setup(opts)
	opts = opts or {}
	M.config = vim.tbl_deep_extend("force", default_config, opts)

	session = nil
	active_provider = nil

	local provider, provider_name = load_provider()
	if not provider then
		return
	end

	local provider_config = build_provider_config(provider_name)
	if not validate_provider(provider, provider_name, provider_config) then
		return
	end

	state.provider_config = provider_config
	ui.setup(M.config)

	pcall(vim.api.nvim_del_user_command, "HarvgateChat")
	pcall(vim.api.nvim_del_user_command, "HarvgateListChats")
	pcall(vim.api.nvim_del_user_command, "HarvgateAddBuffer")
	pcall(vim.api.nvim_del_user_command, "HarvgateRemoveBuffer")
	pcall(vim.api.nvim_del_user_command, "HarvgateListBuffers")

	vim.api.nvim_create_user_command("HarvgateChat", M.toggle, {})

	if provider_supports_listing(provider) then
		vim.api.nvim_create_user_command("HarvgateListChats", M.list_chats, {})
	end

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

---Toggle the chat window for the configured provider
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
	local provider = active_provider or select(1, load_provider())
	if not provider_supports_listing(provider) then
		vim.notify("harvgate: Current provider does not support listing chats", vim.log.levels.WARN)
		return
	end

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
