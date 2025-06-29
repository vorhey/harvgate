# Harvgate

A Neovim plugin for chatting with Claude directly in your editor using your claude web subscription cookie for authentication.

[![logo](https://i.postimg.cc/BZ58DKWh/09f5972d-d30f-4d53-8dd7-9b7fdab59b2f.jpg)](https://postimg.cc/t7TCG74P)

[![chat example](https://i.postimg.cc/HLm40CZ5/example.png)](https://postimg.cc/4Y89ZjTN)

## Features
- Split window interface for chatting with Claude
- Quick conversation reset
- Session persistence using browser cookie authentication

## Requirements
- Neovim >= 0.8.0
- curl
- plenary.nvim

## Installation
Using [lazy.nvim](https://github.com/folke/lazy.nvim):
```lua
{
 'vorhey/harvgate',
 dependencies = {
  'nvim-tree/nvim-web-devicons',
 }
}
```

## Configuration


Harvgate will attempt to load your cookie from the environment variable `CLAUDE_COOKIE` if it is set.

```lua
require('harvgate').setup({
  cookie = "your_claude_cookie", -- Required: Cookie from browser session, e.g. sessionKey=sk-ant-sidxx-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  organization_id = nil,
  model = nil,
  width = 80, -- Optional: Width of chat window (default: 60)
  keymaps = { -- Optional: Custom keymaps
      new_chat = "<C-g>",  -- Start new conversation
      toggle_zen_mode = "<C-r>" -- Codeblocks display only  
  },
  icons = { -- Optional: Custom icons
      chat = "󰭹",
      default_file = "",
      input = "",
  },
})
```
## Usage

| Keybinding | Action | Mode |
|-----------|---------|------|
| `:HarvgateChat` | Toggle chat window | Command |
| `:HarvgateListChats` | List chats | Command |
| `<C-s>` | Send message | Normal, Insert |
| `<C-k>` | Focus messages window | Normal |
| `<C-j>` | Focus input window | Normal |
| `<C-y>` | Copy code snippet | Normal |
| `<C-f>` | Go to matching line | Normal |
| `<C-g>` | Start new conversation | Normal, Insert |
| `<C-r>` | Toggle Zen Mode | Normal |
| `q` or `<Esc>` | Close chat/list window | Normal |


## Contributing

No guidelines yet, maybe someday if it ever gets some traction.

### Commit Convention

This project follows the [Conventional Commits](https://www.conventionalcommits.org/) specification.

# Testing

This project uses [Plenary.nvim](https://github.com/nvim-lua/plenary.nvim) for testing. The test suite is designed to be easy to run both as a one-off command and in watch mode during development.

## Prerequisites

Before running tests, ensure you have:
- Neovim installed and available in your PATH
- [Plenary.nvim](https://github.com/nvim-lua/plenary.nvim) installed
- `make` installed on your system
- `entr` installed (for watch mode)

## Running Tests

There are several ways to run the tests:

### Single Test Run

```bash
make test
```

This command will:
- Start Neovim in headless mode
- Execute all tests in the `tests` directory
- Exit with appropriate status code

### Watch Mode

```bash
make watch
```

Watch mode will:
- Monitor all `.lua` files in both `lua` and `tests` directories
- Automatically run tests when any monitored file changes
- Display test results in real-time

### Cleaning Up

```bash
make clean
```

This will remove any temporary files generated during testing.

## Test Structure

Tests should be placed in the `tests` directory and follow this naming convention:
```
tests/
  ├── feature1_spec.lua
  └── feature2_spec.lua
```

## Writing Tests

Here's a basic example of how to write a test:

```lua
async.tests.it("should create chat", function()
    local chat_id = chat:create_chat()
    assert.is_not_nil(chat_id, "chat_id should not be nil")
    assert.is_string(chat_id, "chat_id should be a string")
    assert.is_not.equals("", chat_id, "chat_id should not be empty")
    print("Successfully created chat with ID: " .. chat_id)
end)
```

## Makefile Reference

The included Makefile provides these targets:
- `test`: Run tests once in headless mode
- `watch`: Watch for file changes and run tests automatically
- `clean`: Clean up temporary files
- Default target is set to `test`
