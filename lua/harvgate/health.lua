local M = {}

function M.check()
	local health = vim.health or require("health")
	local start = health.start
	local ok = health.ok
	local warn = health.warn
	local error = health.error

	start("harvgate.nvim")

	-- Check for required dependencies
	local has_plenary, _ = pcall(require, "plenary.curl")
	if has_plenary then
		ok("plenary.nvim installed")
	else
		error("plenary.nvim not installed")
	end

	local env_cookie = os.getenv("CLAUDE_COOKIE")
	if env_cookie then
		warn(
			"CLAUDE_COOKIE environment variable is set. This will be used as default if no cookie is provided in setup()"
		)
	end

	local config = require("harvgate").config
	if config.cookie then
		ok("Cookie is configured")
	else
		error("Cookie is not set. Configure it in setup()")
	end

	if config.organization_id then
		ok("Organization ID is configured")
	else
		warn("Organization ID is not set (optional)")
	end
end

return M
