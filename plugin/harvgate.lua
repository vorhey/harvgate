if vim.fn.has("nvim-0.7.0") == 0 then
	vim.api.nvim_err_writeln("harvgate requires at least nvim-0.7.0")
	return
end

-- prevent loading the plugin multiple times
if vim.g.loaded_harvgate == 1 then
	return
end
vim.g.loaded_harvgate = 1

require("harvgate")
