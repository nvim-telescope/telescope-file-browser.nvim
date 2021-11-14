# telescope-file-browser.nvim

`telescope-file-browser.nvim` is a file browser extension for telescope.nvim. It supports synchronized creation, deletion, renaming, and moving of files and folders powered by telescope.nvim and [plenary.nvim](). 

# Demo

# Getting Started

## Installation

### packer 

```lua
use {'nvim-telescope/telescope-file-browser.nvim' }
```

### Vim-Plug 

```viml
Plug 'nvim-telescope/telescope-file-browser.nvim'
```

## Setup and Configuration

You configure the `telescope-file-browser` like any other `telescope.nvim` [picker](). See `:h fb_picker` for the full set of options.

```lua
-- You don't need to set any of these options.
-- IMPORTANT!: this is only a showcase of how you can set default options!
require('telescope').setup {
  extensions = {
    file_browser = {
        theme = "ivy"
        mappings = {
            ["i"] = {
                -- your custom insert mode mappings
            },
            ["n"] = {
                -- your custom normal mode mappings
            },
        }
    }
  }
}
-- To get telescope-file-browser loaded and working with telescope,
-- you need to call load_extension, somewhere after setup function:
require('telescope').load_extension('file_browser')
```

## Documentation


<!-- # Contributing -->

<!-- Contributions are very welcome! -->

<!-- ## Submitting a new feature -->

<!-- Thanks for considering to contribute to `telescope-file-browser.nvim`! --> 


# TODO

- [ ] Better handling of file overwriting
