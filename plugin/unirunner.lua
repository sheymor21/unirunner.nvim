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
