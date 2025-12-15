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
- 🏢 **Organization Filtering**: Exclude repositories from specific organizations

## Requirements

- **Neovim 0.8+**: Required for the floating window and async features
- **[GitHub CLI (gh)](https://cli.github.com/)**: Must be installed and authenticated
  ```bash
  # Install
  # macOS
  brew install gh

  # Ubuntu/Debian
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt update
  sudo apt install gh

  # Authenticate
  gh auth login
  ```
- **GitHub repository**: With Actions enabled (optional for viewing repos you have access to)

## Installation

### Using vim.packadd (built-in)

1. Clone the repository to your Neovim pack directory:
   ```bash
   git clone https://github.com/your-username/nvim-pipeline.git ~/.local/share/nvim/site/pack/plugins/start/nvim-pipeline
   ```

2. Add to your `init.lua`:
   ```lua
   -- Load the plugin
   vim.cmd('packadd nvim-pipeline')

   -- Setup with optional configuration
   require('pipeline').setup({
     exclude_organisations = {"org1", "org2"} -- Optional: exclude specific organizations
   })
   ```

### Using lazy.nvim

```lua
{
  "your-username/nvim-pipeline",
  config = function()
    require('pipeline').setup({
      exclude_organisations = {"org1", "org2"} -- Optional: exclude specific organizations
    })
  end,
}
```

### Using packer.nvim

```lua
use {
  'your-username/nvim-pipeline',
  config = function()
    require('pipeline').setup({
      exclude_organisations = {"org1", "org2"} -- Optional: exclude specific organizations
    })
  end,
}
```

## Quick Start

1. **Install GitHub CLI** and authenticate:
   ```bash
   gh auth login
   ```

2. **Install the plugin** using one of the methods above

3. **Open the pipeline**:
   ```vim
   :Pipeline open
   ```

## Usage

### Commands

- `:Pipeline open` - Open the GitHub Actions pipeline viewer

### Keybindings in the floating window:
- `q` or `Esc` - Close the window

## Configuration

Configure the plugin by passing options to the `setup()` function:

```lua
require('pipeline').setup({
  exclude_organisations = {"microsoft", "google"} -- Exclude repos from these organizations
})
```

### Options

#### exclude_organisations
- **Type**: Array of strings
- **Default**: `{}`
- **Description**: Organizations whose repositories should be excluded from the pipeline display

**Example**: If you work with many organizations but only want to monitor your company's repos:

```lua
require('pipeline').setup({
  exclude_organisations = {"third-party-org", "personal-projects"}
})
```

This will hide all repositories owned by the specified organizations from appearing in the pipeline view, helping you focus on the repos that matter most to you.

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
