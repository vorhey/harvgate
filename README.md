# Harvgate

A Neovim plugin for chatting with Claude directly in your editor using your claude web subscription cookie for authentication.

## Features
- Chat with Claude
- Authenticate using your anthropic claude session browser cookie (no API key needed)
- Code-aware context sharing
- Syntax highlighted responses

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
  'nvim-lua/plenary.nvim',
  'MunifTanjim/nui.nvim',
 },
}
```

## Configuration
```lua
require('harvgate').setup({
  cookie = "your_claude_cookie", -- Required: Cookie from browser session
  window = {
    width = 0.8,    -- Width of chat window (0-1)
    height = 0.8,   -- Height of chat window (0-1)
    border = "rounded"
  }
})
```
