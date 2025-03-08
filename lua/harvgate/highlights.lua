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

M.add_claude_highlights = function(ns, bufnr, line_num, left_icon_length, label_length, right_icon_length)
	vim.api.nvim_buf_add_highlight(bufnr, ns, "ChatClaudeBorder", line_num, 0, label_length)
	vim.api.nvim_buf_add_highlight(
		bufnr,
		ns,
		"ChatClaudeLabel",
		line_num,
		left_icon_length,
		left_icon_length + label_length
	)
	vim.api.nvim_buf_add_highlight(
		bufnr,
		ns,
		"ChatClaudeBorder",
		line_num,
		left_icon_length + label_length,
		left_icon_length + label_length + right_icon_length
	)
end

M.add_user_highlights = function(ns, bufnr, line_num, left_icon_length, label_length, right_icon_length)
	vim.api.nvim_buf_add_highlight(bufnr, ns, "ChatUserBorder", line_num, 0, label_length)
	vim.api.nvim_buf_add_highlight(
		bufnr,
		ns,
		"ChatUserLabel",
		line_num,
		left_icon_length,
		left_icon_length + label_length
	)
	vim.api.nvim_buf_add_highlight(
		bufnr,
		ns,
		"ChatUserBorder",
		line_num,
		left_icon_length + label_length,
		left_icon_length + label_length + right_icon_length
	)
end

return M
