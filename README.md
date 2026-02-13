# lean-tig.nvim

A minimal, tig-like Git status UI for Neovim.

<img width="1414" height="938" alt="image" src="https://github.com/user-attachments/assets/77d55aa1-4d7f-4f41-826b-2a74a1032dd6" />


## Features

- Floating window Git status viewer
- Stage/unstage, view diffs, commit
- Keyboard-driven navigation (tig-like)

## Requirements

- Neovim >= 0.9.0
- Git

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'nabetama/lean-tig.nvim',
  config = function()
    require('lean-tig').setup()
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'nabetama/lean-tig.nvim',
  config = function()
    require('lean-tig').setup()
  end,
}
```

## Configuration

```lua
require('lean-tig').setup({
  -- Keymap to open the Git status window
  -- Set to false to disable and define your own keymap
  keymaps = {
    open = '<Leader>gs',
  },
  -- Highlight colors (uses tokyonight-inspired defaults)
  highlights = {
    header = { fg = '#7aa2f7', bold = true },
    staged = { fg = '#9ece6a' },
    unstaged = { fg = '#e0af68' },
    untracked = { fg = '#f7768e' },
    branch = { fg = '#bb9af7' },
  },
})
```

### Custom Keymap

If you want to define your own keymap:

```lua
require('lean-tig').setup({
  keymaps = {
    open = false,  -- Disable default keymap
  },
})

vim.keymap.set('n', '<Leader>G', require('lean-tig').open, { desc = 'Git status' })
```

## Keybindings

| Key | Action |
|-----|--------|
| `j` / `k` | Navigate between files |
| `Enter` / `d` | View diff for the file under cursor |
| `u` | Stage/unstage the file under cursor |
| `C` | Open commit window |
| `R` | Refresh status |
| `q` / `Esc` | Close the window |

## License

Apache-2.0

## Author

Mao Nabeta [nabetama](https://nabetama.com/)
