return {
	{
		headers = function(self)
			return {
				["Accept"] = "application/json",
				["Cookie"] = self.cookie,
				["User-Agent"] = self.user_agent,
				["Origin"] = "https://claude.ai",
				["Referer"] = "https://claude.ai",
			}
		end,
		options = function()
			return {
				http_version = "HTTP/2",
				raw = { "--tlsv1.3", "--ipv4" },
			}
		end,
	},
	{
		headers = function(self)
			return {
				["Accept-Encoding"] = "gzip, deflate, br",
				["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
				["Accept-Language"] = "en-US,en;q=0.5",
				["Connection"] = "keep-alive",
				["Cookie"] = self.cookie,
				["Host"] = "claude.ai",
				["DNT"] = "1",
				["Sec-Fetch-Dest"] = "document",
				["Sec-Fetch-Mode"] = "navigate",
				["Sec-Fetch-Site"] = "none",
				["Sec-Fetch-User"] = "?1",
				["Upgrade-Insecure-Requests"] = "1",
				["User-Agent"] = self.user_agent,
			}
		end,
		options = function()
			return {
				agent = "chrome110",
			}
		end,
	},
}
