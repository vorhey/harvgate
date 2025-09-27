# Harvgate

A Neovim plugin for chatting with Anthropic Claude, GitHub Copilot, or Ollama Cloud directly in your editor. Claude support uses your web session cookie, Copilot piggybacks on copilot.lua authentication, and Ollama Cloud relies on your API key.

[![chat example](https://i.postimg.cc/HLm40CZ5/example.png)](https://postimg.cc/4Y89ZjTN)

## Features
- Split window interface for chatting with your selected provider
- Quick conversation reset
- Provider-specific authentication: Claude via browser cookie, Copilot via copilot.lua or token, Ollama Cloud via API key

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


Harvgate defaults to the Claude backend and will still read `CLAUDE_COOKIE` for backwards compatibility. Use the `provider` option to switch providers and populate the `providers` table for per-backend settings.

```lua
require('harvgate').setup({
  provider = "claude", -- or "copilot"
  width = 80,
  height = 10,
  keymaps = {
    new_chat = "<C-g>",
    toggle_zen_mode = "<C-r>",
    copy_code = "<C-y>",
  },
  providers = {
    claude = {
      cookie = os.getenv('CLAUDE_COOKIE'),
      organization_id = nil,
      model = nil,
    },
    copilot = {
      -- authentication is resolved via copilot.lua; override if you need to
      token = os.getenv('COPILOT_TOKEN'),
      model = 'gpt-4o-mini',
      temperature = 0.2,
    },
    ollama = {
      api_key = os.getenv('OLLAMA_API_KEY'),
      model = 'gpt-oss:120b',
      base_url = 'https://ollama.com/api/chat', -- optional override
      stream = false, -- Harvgate expects buffered responses
    },
  },
})
```

The legacy top-level `cookie`, `organization_id`, and `model` fields continue to work for the Claude provider, so existing configurations do not need to change immediately.

### Copilot authentication

Harvgate reuses the session handled by [`copilot.lua`](https://github.com/zbirenbaum/copilot.lua). Configure it as you normally would (e.g. `:Copilot auth`), and Harvgate will pull the token via `copilot.auth`. As a fallback you can expose a token through `COPILOT_TOKEN` or `providers.copilot.token`, or rely on the Copilot `hosts.json` file (usually stored in `~/.config/github-copilot/`).

### Ollama Cloud authentication

The Ollama Cloud provider uses the HTTPS API available at `https://ollama.com/api/chat`. Set `OLLAMA_API_KEY` in your environment or provide `providers.ollama.api_key` in your setup to authenticate. You can override the default model (`gpt-oss:120b`) with `providers.ollama.model`, and adjust request behaviour with keys like `options` or `keep_alive`. Harvgate currently expects non-streaming responses, so leave `stream` as `false` (the default).

Like Copilot, Ollama Cloud does not currently expose chat history, so commands such as `:HarvgateListChats` are disabled when it is the active provider.

The `:HarvgateListChats` command is only available for providers that expose server-side chat history (currently Claude).

## Usage

| Keybinding | Action | Mode |
|-----------|---------|------|
| `:HarvgateChat` | Toggle chat window | Command |
| `:HarvgateListChats` | List chats (Claude only) | Command |
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
