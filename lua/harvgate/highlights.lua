local M = {}

local function configure_highlight(group, opts)
	vim.api.nvim_set_hl(0, group, opts)
end

M.setup = function(config)
	configure_highlight("ChatClaudeLabel", {
		bg = config.highlights.claude_label_bg,
		fg = config.highlights.claude_label_fg,
		bold = true,
	})

	configure_highlight("ChatUserLabel", {
		bg = config.highlights.user_label_bg,
		fg = config.highlights.user_label_fg,
		bold = true,
	})

	configure_highlight("ChatClaudeBorder", {
		fg = config.highlights.claude_label_bg,
		bold = true,
	})

	configure_highlight("ChatUserBorder", {
		fg = config.highlights.user_label_bg,
		bold = true,
	})
end

return M
