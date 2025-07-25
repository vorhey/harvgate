if vim.fn.has("nvim-0.7.0") == 0 then
	vim.api.nvim_echo({
		{ "harvgate requires at least nvim-0.7.0", "ErrorMsg" },
	}, true, { err = true })
	return
end

-- prevent loading the plugin multiple times
if vim.g.loaded_harvgate == 1 then
	return
end
vim.g.loaded_harvgate = 1

require("harvgate")
