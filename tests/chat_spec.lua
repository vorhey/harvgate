local async = require("plenary.async")
local session_module = require("harvgate.providers.claude.session")
local assert = require("luassert")
local chat_module = require("harvgate.providers.claude.chat")

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

a.describe("Chat Session", function()
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

	a.describe("File Operations", function()
		a.it("should handle file attachments with primary file", function()
			async.util.block_on(async.wrap(function()
				-- Create a temporary test file
				local test_file = "/tmp/test_file.txt"
				vim.fn.writefile({ "line 1", "line 2", "line 3" }, test_file)
				local chat_with_file = chat_module.new(session, test_file)
				local uuid = chat_with_file:create_chat()
				assert.is_not_nil(uuid)
				local response = chat_with_file:send_message(uuid, "Test with file")
				assert.is_not_nil(response)
				-- Cleanup
				vim.fn.delete(test_file)
			end, 1))
		end)

		a.it("should handle additional files context", function()
			async.util.block_on(async.wrap(function()
				local additional_files = {
					["config.json"] = '{"key": "value"}',
					["readme.md"] = "# Test Project",
				}
				local chat_with_files = chat_module.new(session, nil, additional_files)
				local uuid = chat_with_files:create_chat()
				assert.is_not_nil(uuid)
				local response = chat_with_files:send_message(uuid, "Test with additional files")
				assert.is_not_nil(response)
			end, 1))
		end)

		a.it("should update context with new files", function()
			async.util.block_on(async.wrap(function()
				local chat_updatable = chat_module.new(session)
				local uuid = chat_updatable:create_chat()
				assert.is_not_nil(uuid)
				-- Send first message without files
				local response1 = chat_updatable:send_message(uuid, "First message")
				assert.is_not_nil(response1)
				-- Update context with new files
				chat_updatable:update_context({
					["new_file.txt"] = "New content",
				})
				-- Send second message with updated context
				local response2 = chat_updatable:send_message(uuid, "Second message with new file")
				assert.is_not_nil(response2)
			end, 1))
		end)

		a.it("should merge files when updating context", function()
			async.util.block_on(async.wrap(function()
				local initial_files = {
					["file1.txt"] = "Content 1",
				}
				local chat_merge = chat_module.new(session, nil, initial_files)
				-- Update context with merge=true (should keep existing files)
				chat_merge:update_context({
					["file2.txt"] = "Content 2",
				}, true)
				-- Check that both files are present
				assert.is_not_nil(chat_merge.additional_files["file1.txt"])
				assert.is_not_nil(chat_merge.additional_files["file2.txt"])
				assert.equals("Content 1", chat_merge.additional_files["file1.txt"])
				assert.equals("Content 2", chat_merge.additional_files["file2.txt"])
			end, 1))
		end)
	end)

	a.describe("Error Handling", function()
		a.it("should handle session validation errors", function()
			-- Test invalid session object
			assert.has_error(function()
				---@diagnostic disable-next-line: missing-fields
				chat_module.new({}) -- Invalid session
			end, "Invalid session object")

			assert.has_error(function()
				---@diagnostic disable-next-line: missing-fields
				chat_module.new({ cookie = "test" }) -- Missing organization_id
			end, "Invalid session object")
		end)

		a.it("should handle non-existent primary file", function()
			async.util.block_on(async.wrap(function()
				local chat_bad_file = chat_module.new(session, "/non/existent/file.txt")
				local uuid = chat_bad_file:create_chat()
				assert.is_not_nil(uuid)

				-- Should not error, just skip the file
				local response = chat_bad_file:send_message(uuid, "Test with bad file")
				assert.is_not_nil(response)
			end, 1))
		end)

		a.it("should handle empty file content", function()
			async.util.block_on(async.wrap(function()
				-- Create empty test file
				local empty_file = "/tmp/empty_test.txt"
				vim.fn.writefile({}, empty_file)

				local chat_empty = chat_module.new(session, empty_file)
				local uuid = chat_empty:create_chat()
				assert.is_not_nil(uuid)

				local response = chat_empty:send_message(uuid, "Test with empty file")
				assert.is_not_nil(response)

				-- Cleanup
				vim.fn.delete(empty_file)
			end, 1))
		end)
	end)

	a.describe("Chat Management", function()
		a.it("should get all chats", function()
			async.util.block_on(async.wrap(function()
				local chats, err = chat:get_all_chats()
				assert.is_nil(err)
				assert.is_not_nil(chats)
				assert.is_true(type(chats) == "table")
			end, 1))
		end)

		a.it("should get single chat", function()
			async.util.block_on(async.wrap(function()
				-- Create a chat first
				local uuid = chat:create_chat()
				assert.is_not_nil(uuid)

				-- Get the single chat
				local chat_data, err = chat:get_single_chat(uuid)
				assert.is_nil(err)
				assert.is_not_nil(chat_data)
				assert.equals(uuid, chat_data.uuid)
			end, 1))
		end)

		a.it("should get all unnamed chats", function()
			async.util.block_on(async.wrap(function()
				local unnamed_chats, err = chat:get_all_unnamed_chats()
				assert.is_nil(err)
				assert.is_not_nil(unnamed_chats)
				assert.is_true(type(unnamed_chats) == "table")
			end, 1))
		end)

		a.it("should handle chat renaming", function()
			async.util.block_on(async.wrap(function()
				local uuid = chat:create_chat()
				assert.is_not_nil(uuid)

				-- Send a message to trigger renaming
				local response = chat:send_message(uuid, "This is a test message for renaming")
				assert.is_not_nil(response)

				-- Note: rename_chat is called automatically, we just verify no errors
			end, 1))
		end)
	end)
end)
