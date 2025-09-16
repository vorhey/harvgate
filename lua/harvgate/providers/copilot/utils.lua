local M = {}

local default_hosts_paths = nil

local function build_hosts_paths()
	if default_hosts_paths then
		return default_hosts_paths
	end

	local home = vim.loop.os_homedir() or "~"
	default_hosts_paths = {
		string.format("%s/.config/github-copilot/hosts.json", home),
		string.format("%s/Library/Application Support/GitHub Copilot/hosts.json", home),
		string.format("%s/AppData/Roaming/GitHub Copilot/hosts.json", home),
	}

	return default_hosts_paths
end

function M.hosts_paths()
	return build_hosts_paths()
end

local function parse_expires_at(value)
	if type(value) ~= "string" then
		return nil
	end

	local trimmed = value:sub(1, 19)
	local ok, parsed = pcall(vim.fn.strptime, "%Y-%m-%dT%H:%M:%S", trimmed)
	if not ok then
		return nil
	end

	if parsed == 0 then
		return nil
	end

	return parsed
end

function M.parse_expires_at(value)
	return parse_expires_at(value)
end

---Read the GitHub Copilot hosts file and return the stored token if available
---@return string|nil, number|nil
function M.read_hosts_token()
	for _, path in ipairs(build_hosts_paths()) do
		if vim.fn.filereadable(path) == 1 then
			local ok, content = pcall(vim.fn.readfile, path)
			if ok and content then
				local decoded_ok, data = pcall(vim.json.decode, table.concat(content, "\n"))
				if decoded_ok and type(data) == "table" then
					local entry = data["github.com"] or data[1]
					if entry and type(entry) == "table" then
						local token = entry.oauth_token or entry.token
						if token and token ~= "" then
							return token, parse_expires_at(entry.expires_at)
						end
					end
				end
			end
		end
	end

	return nil, nil
end

function M.editor_version()
	local version = vim.version()
	return string.format("Neovim/%d.%d.%d", version.major, version.minor, version.patch)
end

function M.plugin_version()
	return "harvgate.nvim/0.1.0"
end

return M
