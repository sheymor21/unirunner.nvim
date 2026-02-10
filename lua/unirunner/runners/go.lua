local M = {}

function M.detect(root)
  local go_files = vim.fn.glob(root .. '/**/*.go', false, true)
  return vim.fn.filereadable(root .. '/go.mod') == 1
      or vim.fn.filereadable(root .. '/main.go') == 1
      or (type(go_files) == "table" and #go_files > 0)
end

function M.get_commands(root)
  local commands = {}
  local has_go_mod = vim.fn.filereadable(root .. '/go.mod') == 1
  
  -- Check for main package
  if vim.fn.filereadable(root .. '/main.go') == 1 then
    table.insert(commands, {
      name = 'run',
      command = 'go run main.go',
    })
    table.insert(commands, {
      name = 'build',
      command = 'go build -o ' .. vim.fn.fnamemodify(root, ':t'),
    })
  end
  
  -- Standard Go commands
  if has_go_mod then
    table.insert(commands, {
      name = 'test',
      command = 'go test ./...',
    })
    table.insert(commands, {
      name = 'test:v',
      command = 'go test -v ./...',
    })
    table.insert(commands, {
      name = 'fmt',
      command = 'go fmt ./...',
    })
    table.insert(commands, {
      name = 'vet',
      command = 'go vet ./...',
    })
    table.insert(commands, {
      name = 'mod tidy',
      command = 'go mod tidy',
    })
    table.insert(commands, {
      name = 'mod download',
      command = 'go mod download',
    })
  end
  
  -- Check for Makefile
  if vim.fn.filereadable(root .. '/Makefile') == 1 then
    table.insert(commands, {
      name = 'make',
      command = 'make',
    })
    table.insert(commands, {
      name = 'make build',
      command = 'make build',
    })
    table.insert(commands, {
      name = 'make test',
      command = 'make test',
    })
  end
  
  table.sort(commands, function(a, b)
    return a.name < b.name
  end)
  
  return commands
end

return M
