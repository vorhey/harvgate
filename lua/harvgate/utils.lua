local M = {}

M.MAX_MESSAGE_LENGTH = 1000 -- Maximum characters per message

function M.uuidv4()
	math.randomseed(os.time())
	local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	return string.gsub(template, "[xy]", function(c)
		local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
		return string.format("%x", v)
	end)
end

-- Trim message if it exceeds the maximum length
---@param message string The message to trim
---@return string trimmed_message The trimmed message
function M.trim_message(message)
	if #message <= M.MAX_MESSAGE_LENGTH then
		return message
	end

	-- Find the last complete sentence within the limit
	local trim_point = M.MAX_MESSAGE_LENGTH
	while trim_point > 0 do
		local char = message:sub(trim_point, trim_point)
		if char:match("[.!?]") then
			break
		end
		trim_point = trim_point - 1
	end

	-- If no sentence boundary found, trim at the last space
	if trim_point == 0 then
		trim_point = M.MAX_MESSAGE_LENGTH
		while trim_point > 0 do
			local char = message:sub(trim_point, trim_point)
			if char:match("%s") then
				break
			end
			trim_point = trim_point - 1
		end
	end

	-- If still no good break point, just trim at the limit
	if trim_point == 0 then
		trim_point = M.MAX_MESSAGE_LENGTH
	end
	return message:sub(1, trim_point) .. "\n[Message truncated due to length]"
end

function M.buffer_autocmd(bufnr, cb)
	vim.api.nvim_create_autocmd("CmdlineLeave", {
		buffer = bufnr,
		callback = function()
			local cmd = vim.fn.getcmdline()
			if
				cmd == "q"
				or cmd == "q!"
				or cmd == "quit"
				or cmd == "quit!"
				or cmd == "wq"
				or cmd == "wq!"
				or cmd == "x"
				or cmd == "x!"
				or cmd == "xit"
				or cmd == "xit!"
				or cmd == "exit"
				or cmd == "exit!"
				or cmd == "qa"
				or cmd == "qa!"
				or cmd == "qall"
				or cmd == "qall!"
				or cmd == "wqa"
				or cmd == "wqa!"
				or cmd == "wqall"
				or cmd == "wqall!"
				or cmd == "xa"
				or cmd == "xa!"
				or cmd == "xall"
				or cmd == "xall!"
			then
				vim.schedule(function()
					cb()
				end)
			end
		end,
	})
end

return M
