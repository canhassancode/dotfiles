vim.cmd("set expandtab")
vim.cmd("set tabstop=2")
vim.cmd("set softtabstop=2")
vim.cmd("set shiftwidth=2")
vim.cmd("set number")
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"
vim.keymap.set('n', '<C-n>', ':Neotree filesystem reveal left<CR>')
