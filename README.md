# Harvgate

A Neovim plugin for chatting with Claude directly in your editor using your claude web subscription cookie for authentication.

## Features
- Chat with Claude
- Authenticate using your anthropic claude session browser cookie (no API key needed)
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


Harvgate will attempt to load your cookie from the environment variable `CLAUDE_COOKIE` if it is set.

```lua
require('harvgate').setup({
  cookie = "your_claude_cookie", -- Required: Cookie from browser session, e.g. sessionKey=sk-ant-sidxx-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
})
```
