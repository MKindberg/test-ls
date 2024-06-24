# Test-ls
A language server that runs zig tests for the currently open file in the background when the file is saved and reports the results as diagnostics. Also allows hover actions to see the output from the test.

## Installation

Use one of the following methods:
* Download the binary from releases into your path (note that checksum isn't related to the binary)
* Download the repo, install zig 0.13 and run `zig build --release=safe --prefix <install_dir>`
* Install with [mason.nvim](https://github.com/williamboman/mason.nvim) by adding `github:mkindberg/test-ls` as a registry.

## Setup

### Neovim

Add the following to your config.lua:

```lua
local client = vim.lsp.start_client { name = "test-ls", cmd = { "<path_to_test-ls>" }, }

if not client then
    vim.notify("Failed to start test-ls")
else
    vim.api.nvim_create_autocmd("FileType",
        { pattern = {"<filetypes>", "<to>", "<run>", "<on>"}, callback = function() vim.lsp.buf_attach_client(0, client) end }
    )
end
```

