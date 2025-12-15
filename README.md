# nvim-pipeline

A Neovim plugin to display GitHub Actions in a beautiful floating window with real-time status updates.

## Features

- 📊 **Visual Pipeline Display**: Beautiful floating window with bordered action boxes
- 🟡 **Active Actions**: Yellow-bordered boxes for in-progress and queued actions
- ⏱️ **Runtime Duration**: Shows how long each action has been running
- 🔄 **Current Step**: Displays the active step name for running workflows
- 📋 **Recent History**: Shows previously completed actions in chronological order
- 🎨 **Status Colors**: Color-coded status indicators (success, failure, cancelled)
- 🚀 **Async Loading**: Non-blocking data fetching using vim.loop

## Requirements

- Neovim 0.8+
- [GitHub CLI (gh)](https://cli.github.com/) installed and authenticated
- A GitHub repository with Actions enabled

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "your-username/nvim-pipeline", -- Replace with your actual repo path
  config = function()
    require('pipeline').setup()
  end,
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'your-username/nvim-pipeline', -- Replace with your actual repo path
  config = function()
    require('pipeline').setup()
  end,
}
```

## Usage

Open the GitHub Actions pipeline viewer:

```vim
:Pipeline open
```

### Keybindings in the floating window:
- `q` or `Esc` - Close the window

## Setup

The plugin will automatically detect your repository and fetch GitHub Actions data. Make sure you're:

1. **Logged into GitHub CLI**: Run `gh auth login` if you haven't already
2. **In a GitHub repository**: The plugin works from within any git repository with a GitHub remote
3. **Have Actions enabled**: Your repository should have GitHub Actions workflows

## File Structure

```
lua/
├── action.lua     # Action class representing GitHub workflow runs
├── git.lua        # GitHub CLI integration and data fetching
├── display.lua    # Visual rendering and floating window management
└── pipeline.lua   # Main plugin entry point and command handling
```

## Development

The plugin is organized into clear modules:

- **Action class** (`lua/action.lua`): Represents individual GitHub Actions with properties like status, duration, and current step
- **Git integration** (`lua/git.lua`): Handles GitHub CLI communication using vim.loop for async operations
- **Display system** (`lua/display.lua`): Creates beautiful bordered boxes and manages the floating window layout
- **Main controller** (`lua/pipeline.lua`): Coordinates all components and provides the `:Pipeline` command

## License

MIT
