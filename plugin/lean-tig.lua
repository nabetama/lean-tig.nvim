if vim.g.loaded_lean_tig then
  return
end
vim.g.loaded_lean_tig = true

-- Create user command
vim.api.nvim_create_user_command('LeanTig', function()
  require('lean-tig').open()
end, { desc = 'Open lean-tig Git status UI' })
