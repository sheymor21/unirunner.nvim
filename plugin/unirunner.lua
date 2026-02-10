if vim.g.loaded_unirunner then
  return
end
vim.g.loaded_unirunner = 1

vim.api.nvim_create_user_command('UniRunner', function()
  require('unirunner').run()
end, { desc = 'Run last command or show command picker' })

vim.api.nvim_create_user_command('UniRunnerSelect', function()
  require('unirunner').run_select()
end, { desc = 'Show command picker' })

vim.api.nvim_create_user_command('UniRunnerLast', function()
  require('unirunner').run_last()
end, { desc = 'Run last command' })

vim.api.nvim_create_user_command('UniRunnerConfig', function()
  require('unirunner').open_config()
end, { desc = 'Open project configuration' })

vim.api.nvim_create_user_command('UniRunnerTerminal', function()
  require('unirunner').goto_terminal()
end, { desc = 'Go to terminal window' })

vim.api.nvim_create_user_command('UniRunnerCancel', function()
  require('unirunner').cancel()
end, { desc = 'Cancel running terminal process' })

vim.api.nvim_create_user_command('UniRunnerHistory', function()
  require('unirunner').show_output_history()
end, { desc = 'Show last 3 command outputs' })

vim.api.nvim_create_user_command('UniRunnerClearHistory', function()
  require('unirunner').clear_output_history()
end, { desc = 'Clear output history' })
