local async = require("plenary.async")
local session_module = require("harvgate.session")
local assert = require("luassert")
local chat_module = require("harvgate.chat")

---@type Chat
local chat
---@type Session
local session

-- Create session once, outside of the test suite
local cookie = os.getenv("CLAUDE_COOKIE")
if not cookie then
	error("Please set CLAUDE_COOKIE environment variable")
end

async.tests.add_to_env()
session = session_module.new(cookie, nil)
chat = chat_module.new(session)

a.describe("Chat", function()
	a.it("should create a chat and send a message", function()
		async.util.block_on(async.wrap(function()
			local uuid = chat:create_chat()
			print("uuid: " .. uuid)
			assert.is_not_nil(uuid)
			local prompt = "Hello, world!"
			local message_response = chat:send_message(uuid, prompt)
			assert.is_not_nil(message_response)
			print("sent message: " .. prompt)
			print("response:" .. message_response)
		end, 1))
	end)
end)
