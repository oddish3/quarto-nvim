local M = {}
local api = vim.api
local cfg = require 'quarto.config'
local tools = require 'quarto.tools'
local util = require 'lspconfig.util'

function M.quartoPreview(opts)
    opts = opts or {}
    local args = opts.args or ''
    
    -- Enhanced Debug: Print detailed options
    print("[QuartoPreview] Options passed:")
    print("  opts:", vim.inspect(opts))
    print("  args:", vim.inspect(args))

    -- Find root directory / check if it is a project
    local buffer_path = api.nvim_buf_get_name(0)
    print("[QuartoPreview] Buffer path:", buffer_path)

    -- Enhanced root directory detection debug
    local root_dir = util.root_pattern('_quarto.yml')(buffer_path)
    print("[QuartoPreview] Root directory:", vim.inspect(root_dir))

    local cmd
    local mode

    if root_dir then
        mode = 'project'
        cmd = 'quarto preview ' .. args
        print("[QuartoPreview] Project mode detected")
    else
        mode = 'file'
        
        -- Debug for platform-specific command construction
        local platform = vim.loop.os_uname().sysname
        print("[QuartoPreview] Platform:", platform)

        if platform == 'Windows_NT' then
            cmd = 'quarto preview "' .. buffer_path .. '"' .. ' ' .. args
            print("[QuartoPreview] Windows command constructed")
        else
            cmd = "quarto preview '" .. buffer_path .. "'" .. ' ' .. args
            print("[QuartoPreview] Non-Windows command constructed")
        end
    end

    -- Debug: Print the mode and constructed command
    print("[QuartoPreview] Mode:", mode)
    print("[QuartoPreview] Command to execute:", cmd)

    -- Enhanced file extension validation
    local quarto_extensions = { '.qmd', '.Rmd', '.ipynb', '.md' }
    local file_extension = buffer_path:match('^.+(%..+)$') or ''
    
    print("[QuartoPreview] Detected file extension:", file_extension)

    if mode == 'file' then
        if not file_extension then
            print("[QuartoPreview] Error: Not in a valid file")
            vim.notify('Not in a file. Exiting.', vim.log.levels.ERROR)
            return
        end

        if not tools.contains(quarto_extensions, file_extension) then
            print("[QuartoPreview] Error: Invalid Quarto file extension")
            vim.notify('Not a Quarto file, ends in ' .. file_extension .. '. Exiting.', vim.log.levels.WARN)
            return
        end
    end

    -- Enhanced error handling for terminal command
    local success, err = pcall(function()
        print("[QuartoPreview] Attempting to open terminal...")
        vim.cmd('tabedit term://' .. cmd)
    end)

    if not success then
        print("[QuartoPreview] Terminal command failed")
        print("[QuartoPreview] Error details:", err)
        vim.notify('Error opening terminal: ' .. tostring(err), vim.log.levels.ERROR)
        return
    end

    local quartoOutputBuf = vim.api.nvim_get_current_buf()
    print("[QuartoPreview] Quarto output buffer:", quartoOutputBuf)

    vim.cmd 'tabprevious'
    api.nvim_buf_set_var(0, 'quartoOutputBuf', quartoOutputBuf)

    if not cfg.config then
        print("[QuartoPreview] No configuration found")
        return 
    end

    -- Close preview terminal on exit of the Quarto buffer
    if cfg.config.closePreviewOnExit then
        print("[QuartoPreview] Setting up exit autocmd")
        api.nvim_create_autocmd({ 'QuitPre', 'WinClosed' }, {
            buffer = api.nvim_get_current_buf(),
            group = api.nvim_create_augroup('quartoPreview', { clear = true }),
            callback = function()
                print("[QuartoPreview] Checking to close output buffer")
                if api.nvim_buf_is_loaded(quartoOutputBuf) then
                    print("[QuartoPreview] Deleting output buffer")
                    api.nvim_buf_delete(quartoOutputBuf, { force = true })
                end
            end,
        })
    end
end

function M.quartoClosePreview()
  local success, quartoOutputBuf = pcall(api.nvim_buf_get_var, 0, 'quartoOutputBuf')
  if not success then
    return
  end
  if api.nvim_buf_is_loaded(quartoOutputBuf) then
    api.nvim_buf_delete(quartoOutputBuf, { force = true })
  end
end

M.searchHelp = function(cmd_input)
  local topic = cmd_input.args
  local url = 'https://quarto.org/?q=' .. topic .. '&show-results=1'
  local sysname = vim.loop.os_uname().sysname
  local cmd
  if sysname == 'Linux' then
    cmd = 'xdg-open "' .. url .. '"'
  elseif sysname == 'Darwin' then
    cmd = 'open "' .. url .. '"'
  else
    print 'sorry, I do not know how to make Windows open a url with the default browser. This feature currently only works on linux and mac.'
    return
  end
  vim.fn.jobstart(cmd)
end

M.activate = function()
  local tsquery = nil
  if cfg.config.lspFeatures.chunks == 'curly' then
    tsquery = [[
      (fenced_code_block
      (info_string
        (language) @_lang
      ) @info
        (#match? @info "{")
      (code_fence_content) @content (#offset! @content)
      )
      ((html_block) @html @combined)

      ((minus_metadata) @yaml (#offset! @yaml 1 0 -1 0))
      ((plus_metadata) @toml (#offset! @toml 1 0 -1 0))

      ]]
  end
  require('otter').activate(cfg.config.lspFeatures.languages, cfg.config.lspFeatures.completion.enabled, cfg.config.lspFeatures.diagnostics.enabled, tsquery)
end

-- setup
M.setup = function(opt)
  cfg.config = vim.tbl_deep_extend('force', cfg.defaultConfig, opt or {})

  if cfg.config.codeRunner.enabled then
    -- setup top level run functions
    local runner = require 'quarto.runner'
    M.quartoSend = runner.run_cell
    M.quartoSendAbove = runner.run_above
    M.quartoSendBelow = runner.run_below
    M.quartoSendAll = runner.run_all
    M.quartoSendRange = runner.run_range
    M.quartoSendLine = runner.run_line

    -- setup run user commands
    api.nvim_create_user_command('QuartoSend', function(_)
      runner.run_cell()
    end, {})
    api.nvim_create_user_command('QuartoSendAbove', function(_)
      runner.run_above()
    end, {})
    api.nvim_create_user_command('QuartoSendBelow', function(_)
      runner.run_below()
    end, {})
    api.nvim_create_user_command('QuartoSendAll', function(_)
      runner.run_all()
    end, {})
    api.nvim_create_user_command('QuartoSendRange', function(_)
      runner.run_range()
    end, { range = 2 })
    api.nvim_create_user_command('QuartoSendLine', function(_)
      runner.run_line()
    end, {})
  end
end

return M
