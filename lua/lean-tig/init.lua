local M = {}

local config = {
  keymaps = {
    open = '<Leader>gs',
  },
  highlights = {
    header = { fg = '#7aa2f7', bold = true },
    staged = { fg = '#9ece6a' },
    unstaged = { fg = '#e0af68' },
    untracked = { fg = '#f7768e' },
    branch = { fg = '#bb9af7' },
  },
}

function M.setup(opts)
  config = vim.tbl_deep_extend('force', config, opts or {})

  vim.api.nvim_set_hl(0, 'LeanTigHeader', config.highlights.header)
  vim.api.nvim_set_hl(0, 'LeanTigStaged', config.highlights.staged)
  vim.api.nvim_set_hl(0, 'LeanTigUnstaged', config.highlights.unstaged)
  vim.api.nvim_set_hl(0, 'LeanTigUntracked', config.highlights.untracked)
  vim.api.nvim_set_hl(0, 'LeanTigBranch', config.highlights.branch)

  if config.keymaps.open then
    vim.keymap.set('n', config.keymaps.open, M.open, { desc = 'Lean Tig: Git status UI' })
  end
end

function M.open(restore_file)
  local git_root = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null'):gsub('\n', '')
  if vim.v.shell_error ~= 0 then
    vim.notify('Not a git repository', vim.log.levels.WARN)
    return
  end

  local function git(cmd)
    return 'git -C ' .. vim.fn.shellescape(git_root) .. ' ' .. cmd
  end

  -- Check if HEAD exists (for initial commit)
  local function has_head()
    vim.fn.system(git('rev-parse HEAD'))
    return vim.v.shell_error == 0
  end

  -- Stage a single file
  local function stage_file(filename)
    vim.fn.system(git('add ' .. vim.fn.shellescape(filename)))
  end

  -- Unstage a single file
  local function unstage_file(filename)
    if has_head() then
      vim.fn.system(git('restore --staged ' .. vim.fn.shellescape(filename)))
    else
      vim.fn.system(git('rm --cached ' .. vim.fn.shellescape(filename)))
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'lean-tig'

  local ns = vim.api.nvim_create_namespace('lean-tig')
  local file_map = {}
  local win

  local function build_status()
    local output = vim.fn.systemlist(git('status --porcelain -uall'))
    local branch = vim.fn.system(git('branch --show-current')):gsub('\n', '')
    local remote_status = vim.fn.system(git('status -sb')):match('%[(.-)%]') or ''

    local staged, unstaged, untracked = {}, {}, {}

    for _, line in ipairs(output) do
      if line ~= '' then
        local idx, wt = line:sub(1, 1), line:sub(2, 2)
        local file = line:sub(4)

        if line:sub(1, 2) == '??' then
          table.insert(untracked, { status = '?', file = file })
        else
          if idx ~= ' ' and idx ~= '?' then
            table.insert(staged, { status = idx, file = file })
          end
          if wt ~= ' ' and wt ~= '?' then
            table.insert(unstaged, { status = wt, file = file })
          end
        end
      end
    end

    local lines = {}
    local new_file_map = {}
    local first_file_line = nil

    -- Branch info
    local branch_line = 'On branch ' .. branch
    if remote_status ~= '' then
      branch_line = branch_line .. ' [' .. remote_status .. ']'
    end
    table.insert(lines, branch_line)
    table.insert(lines, '')

    -- Helper to add section
    local function add_section(title, files, section_name, header_section)
      table.insert(lines, title)
      local header_line = #lines
      if #files == 0 then
        table.insert(lines, '  (no files)')
      else
        new_file_map[header_line] = { section = header_section, files = files }
        if not first_file_line then
          first_file_line = header_line
        end
        for _, f in ipairs(files) do
          table.insert(lines, '  ' .. f.status .. ' ' .. f.file)
          new_file_map[#lines] = { file = f.file, section = section_name }
        end
      end
      table.insert(lines, '')
    end

    add_section('Changes to be committed:', staged, 'staged', 'staged_header')
    add_section('Changes not staged for commit:', unstaged, 'unstaged', 'unstaged_header')
    add_section('Untracked files:', untracked, 'untracked', 'untracked_header')

    table.insert(lines, '[j/k] move  [Enter/d] diff  [u] stage/unstage  [C] commit  [R] refresh  [q] close')

    return lines, new_file_map, first_file_line
  end

  local function apply_highlights(lines)
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for i, line in ipairs(lines) do
      local entry = file_map[i]
      if line:match('^On branch') then
        vim.api.nvim_buf_add_highlight(buf, ns, 'LeanTigBranch', i - 1, 0, -1)
      elseif line:match('^Changes to be committed') or line:match('^Changes not staged') or line:match('^Untracked files') then
        vim.api.nvim_buf_add_highlight(buf, ns, 'LeanTigHeader', i - 1, 0, -1)
      elseif entry and entry.section then
        local section = entry.section:gsub('_header$', '')
        local hl = ({
          staged = 'LeanTigStaged',
          unstaged = 'LeanTigUnstaged',
          untracked = 'LeanTigUntracked',
        })[section]
        if hl then
          vim.api.nvim_buf_add_highlight(buf, ns, hl, i - 1, 0, -1)
        end
      end
    end
  end

  local function refresh()
    local current_row = vim.api.nvim_win_get_cursor(win)[1]
    local current_entry = file_map[current_row]

    local lines, new_file_map, first_file_line = build_status()
    file_map = new_file_map

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    apply_highlights(lines)

    -- Restore cursor position
    local new_row = first_file_line or 1
    if current_entry and current_entry.file then
      for row, info in pairs(file_map) do
        if info.file == current_entry.file then
          new_row = row
          break
        end
      end
    end
    if new_row <= #lines then
      vim.api.nvim_win_set_cursor(win, { new_row, 0 })
    end
  end

  -- Initial build
  local lines, initial_file_map, first_file_line = build_status()
  file_map = initial_file_map

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines + 2, vim.o.lines - 4)

  win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Git ',
    title_pos = 'center',
  })

  vim.wo[win].cursorline = true
  apply_highlights(lines)

  -- Set initial cursor position
  local cursor_line = first_file_line
  if restore_file then
    for row, info in pairs(file_map) do
      if info.file == restore_file then
        cursor_line = row
        break
      end
    end
  end
  if cursor_line then
    vim.api.nvim_win_set_cursor(win, { cursor_line, 0 })
  end

  local function get_current_entry()
    return file_map[vim.api.nvim_win_get_cursor(win)[1]]
  end

  local function find_file_line(start, direction)
    local row = start
    local max_lines = vim.api.nvim_buf_line_count(buf)
    while row >= 1 and row <= max_lines do
      row = row + direction
      if file_map[row] then
        return row
      end
    end
    return nil
  end

  local function close_window()
    vim.cmd('noautocmd call nvim_win_close(' .. win .. ', v:true)')
  end

  local opts = { buffer = buf, silent = true, nowait = true }

  vim.keymap.set('n', 'q', close_window, opts)
  vim.keymap.set('n', '<Esc>', close_window, opts)

  vim.keymap.set('n', 'j', function()
    local next = find_file_line(vim.api.nvim_win_get_cursor(win)[1], 1)
    if next then
      vim.api.nvim_win_set_cursor(win, { next, 0 })
    end
  end, opts)

  vim.keymap.set('n', 'k', function()
    local prev = find_file_line(vim.api.nvim_win_get_cursor(win)[1], -1)
    if prev then
      vim.api.nvim_win_set_cursor(win, { prev, 0 })
    end
  end, opts)

  local function open_diff(f)
    local target_file = f.file
    close_window()

    if f.section == 'untracked' then
      vim.cmd('view ' .. vim.fn.fnameescape(git_root .. '/' .. target_file))
    else
      local cmd = f.section == 'staged'
          and git('diff --cached -- ' .. vim.fn.shellescape(target_file))
          or git('diff -- ' .. vim.fn.shellescape(target_file))

      local diff_output = vim.fn.systemlist(cmd)
      local diff_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, diff_output)
      vim.bo[diff_buf].filetype = 'diff'
      vim.bo[diff_buf].bufhidden = 'wipe'
      vim.bo[diff_buf].modifiable = false

      vim.cmd('split')
      vim.api.nvim_win_set_buf(0, diff_buf)
    end

    vim.keymap.set('n', 'q', function()
      vim.cmd('bdelete')
      vim.schedule(function() M.open(target_file) end)
    end, { buffer = true, silent = true })
  end

  vim.keymap.set('n', '<CR>', function()
    local entry = get_current_entry()
    if entry and entry.file then
      open_diff(entry)
    end
  end, opts)

  vim.keymap.set('n', 'd', function()
    local entry = get_current_entry()
    if entry and entry.file then
      open_diff(entry)
    end
  end, opts)

  vim.keymap.set('n', 'u', function()
    local entry = get_current_entry()
    if not entry then
      return
    end

    if entry.section == 'staged_header' then
      for _, f in ipairs(entry.files) do
        unstage_file(f.file)
      end
    elseif entry.section == 'unstaged_header' or entry.section == 'untracked_header' then
      for _, f in ipairs(entry.files) do
        stage_file(f.file)
      end
    elseif entry.section == 'staged' then
      unstage_file(entry.file)
    else
      stage_file(entry.file)
    end

    refresh()
  end, opts)

  vim.keymap.set('n', 'C', function()
    close_window()

    local commit_file = git_root .. '/.git/COMMIT_EDITMSG'
    local template = { '' }
    table.insert(template, '# Please enter the commit message for your changes. Lines starting')
    table.insert(template, "# with '#' will be ignored, and an empty message aborts the commit.")
    table.insert(template, '#')
    for _, line in ipairs(vim.fn.systemlist(git('status'))) do
      table.insert(template, '# ' .. line)
    end
    -- Add verbose diff (like git commit -v)
    table.insert(template, '# ------------------------ >8 ------------------------')
    table.insert(template, '# Do not modify or remove the line above.')
    table.insert(template, '# Everything below it will be ignored.')
    for _, line in ipairs(vim.fn.systemlist(git('diff --cached'))) do
      table.insert(template, line)
    end
    vim.fn.writefile(template, commit_file)

    local placeholder_buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(placeholder_buf, 0, -1, false, { '' })
    vim.api.nvim_win_set_buf(0, placeholder_buf)

    vim.cmd('noautocmd split ' .. vim.fn.fnameescape(commit_file))
    local commit_buf = vim.api.nvim_get_current_buf()
    local commit_win = vim.api.nvim_get_current_win()
    vim.bo[commit_buf].filetype = 'gitcommit'
    local committed = false
    local cleaning_up = false

    local group = vim.api.nvim_create_augroup('LeanTigCommit', { clear = true })

    local function cleanup_buffers_and_return()
      if cleaning_up then
        return
      end
      cleaning_up = true

      pcall(vim.api.nvim_del_augroup_by_name, 'LeanTigCommit')

      -- Delete buffers (window is already closed by :q)
      vim.schedule(function()
        pcall(function()
          if vim.api.nvim_buf_is_valid(commit_buf) then
            vim.cmd('noautocmd bwipeout! ' .. commit_buf)
          end
        end)
        pcall(function()
          if vim.api.nvim_buf_is_valid(placeholder_buf) then
            vim.cmd('noautocmd bwipeout! ' .. placeholder_buf)
          end
        end)
        M.open()
      end)
    end

    local function do_commit()
      if committed then
        return
      end
      committed = true

      -- Save content to file manually
      local lines = vim.api.nvim_buf_get_lines(commit_buf, 0, -1, false)
      vim.fn.writefile(lines, commit_file)
      -- Mark buffer as not modified to prevent "unsaved changes" warning
      vim.bo[commit_buf].modified = false

      local result = vim.fn.system(git('commit --allow-empty --cleanup=scissors --file=' ..
      vim.fn.shellescape(commit_file)))
      if vim.v.shell_error == 0 then
        vim.notify('Committed!', vim.log.levels.INFO)
      else
        vim.notify(vim.trim(result), vim.log.levels.ERROR)
      end
      -- Don't cleanup here - let WinClosed handle it after :q closes the window
    end

    -- BufWriteCmd intercepts :w
    vim.api.nvim_create_autocmd('BufWriteCmd', {
      group = group,
      buffer = commit_buf,
      callback = function()
        do_commit()
        -- Return true to indicate we handled the write
        return true
      end,
    })

    -- WinClosed handles when the commit window is closed (via :q, :wq, ZZ, etc.)
    vim.api.nvim_create_autocmd('WinClosed', {
      group = group,
      pattern = tostring(commit_win),
      callback = function()
        -- Whether committed or cancelled, cleanup and return to lean-tig
        if not cleaning_up then
          cleanup_buffers_and_return()
        end
      end,
    })

    vim.keymap.set('n', 'q', function()
      vim.bo[commit_buf].modified = false
      vim.cmd('close')
    end, { buffer = commit_buf, silent = true })

    vim.keymap.set('n', 'ZZ', function()
      do_commit()
      vim.cmd('close')
    end, { buffer = commit_buf, silent = true })

    vim.keymap.set('n', 'ZQ', function()
      vim.bo[commit_buf].modified = false
      vim.cmd('close')
    end, { buffer = commit_buf, silent = true })

    vim.cmd('goto 1')
  end, opts)

  vim.keymap.set('n', 'R', refresh, opts)
end

return M
