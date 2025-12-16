# nvim-pipeline

A Neovim plugin to display GitHub Actions in a beautiful floating window with real-time status updates.

## Installation

```lua
-- ensure the github cli is installed (https://cli.github.com)
-- run `gh auth login` in your terminal to authenticate before using the plugin
 -- in your init.lua
vim.pack.add {
    {'https://github.com/jesses-code-adventures/pipeline.nvim'}
}
require('pipeline').setup({
    exclude_organisations = {"microsoft", "google"} -- Exclude repos from these organizations
})

-- keymaps - use whatever you want
vim.keymap.set('n', '<leader>pl', ':Pipeline open<CR>')
```

Lazy Install

```lua
    {
        "jesses-code-adventures/pipeline.nvim",
        config = function()
            require("pipeline").setup({
                exclude_organisations = {"microsoft", "google"} -- Exclude repos from these organizations
            })

            vim.keymap.set('n', '<leader>pl', ':Pipeline open<CR>')
        end
    },
```

## Usage

### Commands

- `:Pipeline open` - Open the GitHub Actions pipeline viewer

### Keybindings in the floating window:
- `q` or `Esc` - Close the window

## License

MIT
