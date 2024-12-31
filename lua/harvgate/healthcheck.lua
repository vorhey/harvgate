local M = {}

function M.check()
	local health = vim.health or require("health")
	local start = health.start or health.report_start
	local ok = health.ok or health.report_ok
	local error = health.error or health.report_error

	start("harvgate.nvim")

	-- Check for required dependencies
	local has_plenary, _ = pcall(require, "plenary.curl")
	if has_plenary then
		ok("plenary.nvim installed")
	else
		error("plenary.nvim not installed")
	end

	local has_nui, _ = pcall(require, "nui.popup")
	if has_nui then
		ok("nui.nvim installed")
	else
		error("nui.nvim not installed")
	end

	-- Check for optional dependencies if any
	-- Add more dependency checks as needed
end

return M
