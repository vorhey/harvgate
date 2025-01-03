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
session = session_module.new(cookie, nil, nil)
chat = chat_module.new(session)

async.tests.describe("Chat Integration", function()
	async.tests.before_each(function()
		vim.wait(5000, function() end)
	end)

	async.tests.it("should create chat", function()
		local chat_id = chat:create_chat()
		assert.is_not_nil(chat_id, "chat_id should not be nil")
		assert.is_string(chat_id, "chat_id should be a string")
		assert.is_not.equals("", chat_id, "chat_id should not be empty")
		print("Successfully created chat with ID: " .. chat_id)
	end)

	async.tests.it("should send message", function()
		local prompt = "Hello"
		local chat_id = chat:create_chat()
		assert.is_not_nil(chat_id, "chat_id should not be nil")
		local message = chat:send_message(chat_id, prompt)
		assert.is_not_nil(message, "message should not be nil")
		assert.is_string(message, "message should be a string")
		assert.is_not.equals("", message, "message should not be empty")
		print("Successfully sent message: " .. prompt)
		print("Successfully received message: " .. message)
	end)

	async.tests.it("should list chats", function()
		local chats = chat:list_chats()
		assert.is_not_nil(chats, "chats should not be nil")
		assert.is_table(chats, "chats should be a table")
		for _, chat_item in ipairs(chats) do
			assert.is_not_nil(chat_item.uuid, "chat uuid should not be nil")
			assert.is_string(chat_item.uuid, "chat uuid should be a string")
			assert.is_not.equals("", chat_item.uuid, "chat uuid should not be empty")

			assert.is_not_nil(chat_item.name, "chat name should not be nil")
			assert.is_string(chat_item.name, "chat name should be a string")

			assert.is_not_nil(chat_item.created_at, "chat created_at should not be nil")
			assert.is_string(chat_item.created_at, "chat created_at should be a string")
			assert.is_not.equals("", chat_item.created_at, "chat created_at should not be empty")
		end
		print("Successfully retrieved chat list with " .. #chats .. " chats")
	end)
end)
