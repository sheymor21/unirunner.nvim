local M = {}

local runners = {}

function M.register(name, runner)
  runners[name] = runner
end

function M.detect_runner(root)
  for name, runner in pairs(runners) do
    if runner.detect and runner.detect(root) then
      return runner, name
    end
  end
  return nil, nil
end

function M.get_all()
  return runners
end

return M
