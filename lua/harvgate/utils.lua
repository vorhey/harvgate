local M = {}

-- Seed RNG once per load for UUIDs; avoid per-call seeding
do
	local hr = os.time()
	math.randomseed(hr % 0x7fffffff)
	-- warm up
	math.random()
	math.random()
	math.random()
end

M.MAX_MESSAGE_LENGTH = 1000 -- Maximum characters per message

function M.uuidv4()
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
			local close_cmds = {
				q = true,
				["q!"] = true,
				quit = true,
				["quit!"] = true,
				wq = true,
				["wq!"] = true,
				x = true,
				["x!"] = true,
				xit = true,
				["xit!"] = true,
				exit = true,
				["exit!"] = true,
				qa = true,
				["qa!"] = true,
				qall = true,
				["qall!"] = true,
				wqa = true,
				["wqa!"] = true,
				wqall = true,
				["wqall!"] = true,
				xa = true,
				["xa!"] = true,
				xall = true,
				["xall!"] = true,
			}
			if close_cmds[cmd] then
				vim.schedule(cb)
			end
		end,
	})
end

local function get_current_distro()
	local os_release = io.open("/etc/os-release", "r")
	if not os_release then
		return nil
	end

	local distro_name = nil
	for line in os_release:lines() do
		if line:match("^NAME=") then
			distro_name = line:match('NAME="(.-)"') or line:match("NAME=(.-)$")
			break
		end
	end
	os_release:close()

	return distro_name
end

function M.is_number(value)
	return type(value) == "number"
end

function M.is_distro(distro_names)
	local current_distro = get_current_distro()
	if not current_distro then
		return false
	end

	current_distro = current_distro:lower()

	for _, distro_name in ipairs(distro_names) do
		if current_distro:match(distro_name:lower()) then
			return true
		end
	end

	return false
end

function M.safe_get(t, structure, default)
	if t == nil then
		return default
	end
	local current = t

	local function extract_path(struct)
		local path = {}
		local current_struct = struct

		while true do
			if type(current_struct) ~= "table" or next(current_struct) == nil then
				break
			end

			local k, v = next(current_struct)
			table.insert(path, k)

			if type(v) == "table" then
				if next(v) then
					local subkey, _ = next(v)
					if type(subkey) == "string" then
						table.insert(path, 1)
					end
				end
				current_struct = v
			else
				-- Reached a leaf node
				break
			end
		end

		return path
	end

	local path = extract_path(structure)

	for _, key in ipairs(path) do
		if type(current) ~= "table" then
			return default
		end
		current = current[key]
		if current == nil then
			return default
		end
	end

	return current
end

return M
