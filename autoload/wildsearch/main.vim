scriptencoding utf-8

let s:enabled = 1
let s:init = 0
let s:auto = 0
let s:active = 0
let s:hidden = 0
let s:run_id = 0
let s:result_run_id = -1
let s:draw_done = 0
let s:force = 0
let s:auto_select = -1

let s:candidates = []
let s:selected = -1
let s:page = [-1, -1]

let s:opts = {
      \ 'modes': ['/', '?'],
      \ 'interval': 100,
      \ 'use_cmdlinechanged': 0,
      \ 'hooks': {
      \    'pre': 'wildsearch#main#save_statusline',
      \    'post': 'wildsearch#main#restore_statusline',
      \  },
      \ 'num_workers': 2,
      \ }

function! wildsearch#main#set_option(key, value) abort
  let s:opts[a:key] = a:value
endfunction

function! wildsearch#main#set_options(opts) abort
  let s:opts = extend(s:opts, a:opts)
endfunction

function! wildsearch#main#get_option(key) abort
  return s:opts[a:key]
endfunction

function! wildsearch#main#in_mode() abort
  return index(s:opts.modes, getcmdtype()) >= 0
endfunction

function! wildsearch#main#in_context() abort
  return wildsearch#main#in_mode() && !s:hidden && s:enabled
endfunction

function! wildsearch#main#enable_cmdline_enter() abort
  if !exists('#WildsearchCmdlineEnter')
    augroup WildsearchCmdlineEnter
      autocmd!
      autocmd CmdlineEnter * call wildsearch#main#start_auto()
    augroup END
  endif
endfunction

function! wildsearch#main#disable_cmdline_enter() abort
  if exists('#WildsearchCmdlineEnter')
    augroup WildsearchCmdlineEnter
      autocmd!
    augroup END
    augroup! WildsearchCmdlineEnter
  endif
endfunction

function! wildsearch#main#start_auto() abort
  if !wildsearch#main#in_mode() || !s:enabled
    return
  endif

  let s:auto = 1

  call s:start(1)

  return "\<Insert>\<Insert>"
endfunction

function! wildsearch#main#start_from_normal_mode() abort
  if !s:enabled
    return ''
  endif

  let s:auto = 1

  " skip check since it is still normal mode
  call s:start(0)

  return ''
endfunction

function! s:start(check) abort
  if a:check && !wildsearch#main#in_mode()
    call wildsearch#main#stop()
    return
  endif

  if has('nvim') && !s:init
    let s:init = 1
    call _wildsearch_init({'num_workers': s:opts.num_workers})
  endif

  if s:opts.use_cmdlinechanged
    if !exists('#WildsearchCmdlineChanged')
      augroup WildsearchCmdlineChanged
        autocmd!
        " directly calling s:do makes getcmdline return an empty string
        autocmd CmdlineChanged * call timer_start(0, {_ -> s:do(1)})
      augroup END
    endif
  elseif !exists('s:timer')
      let s:timer = timer_start(s:opts.interval,
            \ {_ -> s:do(1)}, {'repeat': -1})
  endif

  if s:auto && !exists('#WildsearchCmdlineLeave')
    augroup WildsearchCmdlineLeave
      autocmd!
      autocmd CmdlineLeave * call wildsearch#main#stop()
    augroup END
  endif

  if !exists('#WildsearchVimResized')
    augroup WildsearchVimResized
      autocmd!
        autocmd VimResized * call timer_start(0, {_ -> s:draw_resized()})
    augroup END
  endif

  let s:active = 1
  let s:hidden = 0
  let s:force = 0

  call s:pre_hook()

  call s:do(0)
endfunction

function! wildsearch#main#stop() abort
  if !s:active
    return
  endif

  if exists('#WildsearchCmdlineChanged')
    augroup WildsearchCmdlineChanged
      autocmd!
    augroup END
    augroup! WildsearchCmdlineChanged
  endif

  if exists('s:timer')
    call timer_stop(s:timer)
    unlet s:timer
  endif

  if exists('#WildsearchCmdlineLeave')
    augroup WildsearchCmdlineLeave
      autocmd!
    augroup END
    augroup! WildsearchCmdlineLeave
  endif

  if exists('#WildsearchVimResized')
    augroup WildsearchVimResized
      autocmd!
    augroup END
    augroup! WildsearchVimResized
  endif

  let s:active = 0
  let s:auto = 0
  let s:candidates = []
  let s:selected = -1
  let s:page = [-1, -1]

  if exists('s:previous_cmdline')
    unlet s:previous_cmdline
  endif

  if exists('s:completion')
    unlet s:completion
  endif

  if exists('s:error')
    unlet s:error
  endif

  if exists('s:replaced_cmdline')
    unlet s:replaced_cmdline
  endif

  if exists('s:replaced_cmdpos')
    unlet s:replaced_cmdpos
  endif

  if exists('s:menus')
    unlet s:menus
  endif

  if exists('s:previous_menu')
    unlet s:previous_menu
  endif

  if !s:hidden
    call s:post_hook()
  endif

  let s:hidden = 0
endfunction

function! s:pre_hook() abort
  if has_key(s:opts, 'hooks') && has_key(s:opts.hooks, 'pre')
    if type(s:opts.hooks.pre) is v:t_func
      call s:opts.hooks.pre()
    else
      call function(s:opts.hooks.pre)()
    endif
  endif

  call wildsearch#render#init()
endfunction

function! s:post_hook() abort
  call wildsearch#render#finish()

  if has_key(s:opts, 'hooks') && has_key(s:opts.hooks, 'post')
    if type(s:opts.hooks.post) is v:t_func
      call s:opts.hooks.post()
    else
      call function(s:opts.hooks.post)()
    endif
  endif
endfunction

function! s:do(check) abort
  if !s:active || !s:enabled
    return
  endif

  if a:check && !wildsearch#main#in_mode()
    call wildsearch#main#stop()
    return
  endif

  let l:cmdpos = getcmdpos()
  let l:cmdline = getcmdline()
  if l:cmdpos <= 1
    let l:input = ''
  else
    let l:input = l:cmdline[:l:cmdpos - 2]
  endif

  let l:has_completion = exists('s:completion') && l:input ==# s:completion
  let l:is_new_input = !exists('s:previous_cmdline')
  let l:input_changed = exists('s:previous_cmdline') && s:previous_cmdline !=# l:input

  if !s:auto && !s:force && !l:is_new_input && !l:has_completion && l:input_changed
    call wildsearch#main#stop()
    return
  endif

  if s:force || !l:has_completion
    if exists('s:completion')
      unlet s:completion
    endif

    if exists('s:replaced_cmdline')
      unlet s:replaced_cmdline
    endif

    if exists('s:replaced_cmdpos')
      unlet s:replaced_cmdpos
    endif

    let s:previous_cmdline = l:input
  endif

  let s:draw_done = 0

  if s:force || !l:has_completion && (l:input_changed || l:is_new_input)
    if !s:force && !l:has_completion && (l:input_changed || l:is_new_input)
      if exists('s:menus')
        unlet s:menus
      endif

      if exists('s:previous_menu')
        unlet s:previous_menu
      endif
    endif

    let l:ctx = {
        \ 'input': l:input,
        \ 'on_finish': 'wildsearch#main#on_finish',
        \ 'on_error': 'wildsearch#main#on_error',
        \ 'run_id': s:run_id,
        \ }

    let s:run_id += 1

    call wildsearch#pipeline#start(l:ctx, l:input)
  endif

  let s:force = 0

  let l:ctx = {
        \ 'selected': s:selected,
        \ 'done': s:run_id - 1 == s:result_run_id,
        \ }

  if exists('s:error')
    let l:ctx.error = s:error
  endif

  if !s:draw_done && (l:is_new_input ||
        \ wildsearch#render#components_need_redraw(wildsearch#render#get_components(), l:ctx, s:candidates))
    call s:draw()
  endif

  let s:auto_select = -1
endfunction

function! wildsearch#main#on_finish(ctx, x) abort
  if !s:active || !s:enabled
    return
  endif

  if a:ctx.run_id < s:result_run_id
    return
  endif

  let s:result_run_id = a:ctx.run_id

  let s:candidates = (a:x is v:false || a:x is v:true) ? [] : a:x
  let s:selected = -1
  let s:page = [-1, -1]
  " keep previous completion

  if exists('s:error')
    unlet s:error
  endif

  if a:x is v:true
    if !s:hidden
      let s:hidden = 1

      call s:post_hook()
    endif

    return
  endif

  if s:hidden
    let s:hidden = 0

    call s:pre_hook()
  endif

  if s:auto_select != -1
    if exists('s:previous_cmdline')
      unlet s:previous_cmdline
    endif

    call wildsearch#main#next()
    return
  endif

  call s:draw()
endfunction

function! wildsearch#main#on_error(ctx, x) abort
  if !s:active || !s:enabled
    return
  endif

  if a:ctx.run_id < s:result_run_id
    return
  endif

  let s:result_run_id = a:ctx.run_id

  let s:candidates = []
  let s:selected = -1
  " keep previous completion

  let s:error = a:x

  call s:draw()
endfunction

function! s:draw_resized() abort
  if !s:active || !s:enabled
    return
  endif

  call s:draw(0, 1)
endfunction

function! s:draw(...) abort
  if s:hidden
    return
  endif

  let l:direction = a:0 >= 1 ? a:1 : 0
  let l:has_resized = a:0 >= 2 ? a:2 : 0

  let l:ctx = {
        \ 'selected': s:selected,
        \ 'done': s:run_id - 1 == s:result_run_id,
        \ }

  let l:has_error = exists('s:error')

  if l:has_error
    let l:ctx.error = s:error
  endif

  let l:xs = l:has_error ? [] :
        \ map(copy(s:candidates), {_, x -> type(x) is v:t_dict ? get(x, 'draw', x.result) : x})

  let l:left_components = wildsearch#render#get_components('left')
  let l:right_components = wildsearch#render#get_components('right')

  let l:space_used = wildsearch#render#components_len(
        \ l:left_components + l:right_components,
        \ l:ctx, l:xs)
  let l:ctx.space = winwidth(0) - l:space_used

  let s:page = wildsearch#render#make_page(l:ctx, l:xs, s:page, l:direction, l:has_resized)
  let l:ctx.page = s:page

  if l:has_error
    let l:statusline = wildsearch#render#draw_error(
          \ l:left_components, l:right_components,
          \ l:ctx, s:error)
  else
    let l:statusline = wildsearch#render#draw(
          \ l:left_components, l:right_components,
          \ l:ctx, l:xs)
  endif

  call setwinvar(0, '&statusline', l:statusline)
  redrawstatus

  let s:draw_done = 1
endfunction

function! wildsearch#main#next() abort
  return wildsearch#main#step(1)
endfunction

function! wildsearch#main#previous() abort
  return wildsearch#main#step(-1)
endfunction

function! wildsearch#main#step(num_steps) abort
  if !s:enabled
    " returning '' seems to prevent async completions from finishing
    " or prevent redrawing
    return "\<Insert>\<Insert>"
  endif

  if !s:active
    call s:start(1)
    return "\<Insert>\<Insert>"
  endif

  if s:hidden
    return "\<Insert>\<Insert>"
  endif

  if !exists('s:replaced_cmdline')
    let s:replaced_cmdline = getcmdline()
    let s:replaced_cmdpos = getcmdpos()
  endif

  if !exists('s:menus')
    let s:menus = []
  endif

  let l:len = len(s:candidates)
  if a:num_steps == 0
    " pass
  elseif l:len == 0
    let s:selected = -1
  elseif l:len == 1
    let s:selected = 0
  else
    if s:selected < 0
      if a:num_steps > 0
        let l:selected = a:num_steps - 1
      else
        let l:selected = a:num_steps
      endif

      while l:selected < 0
        let l:selected += l:len
      endwhile
    else
      let l:selected = s:selected + a:num_steps

      while l:selected < -1
        let l:selected += l:len
      endwhile
    endif

    while l:selected > l:len
      let l:selected -= l:len
    endwhile

    let s:selected = l:selected == l:len ? -1 : l:selected
  endif

  call s:draw(a:num_steps)

  if s:selected >= -1
    if s:selected >= 0
      let l:candidate = s:candidates[s:selected]
      let l:output = type(l:candidate) is v:t_dict ?
            \ get(l:candidate, 'output', l:candidate.result) :
            \ l:candidate

      let l:Replace = type(l:candidate) is v:t_dict ?
            \ get(l:candidate, 'replace', 'all') :
            \ 'all'
      if l:Replace ==# 'all'
        let l:Replace = function('s:replace_all')
      elseif type(l:Replace) ==# v:t_string
        let l:Replace = function(l:Replace)
      endif

      let l:cmdpos = s:replaced_cmdpos
      if l:cmdpos <= 1
        let l:cmdline = s:replaced_cmdline
        let l:new_cmdline = l:output
      else
        let l:cmdline = s:replaced_cmdline[: l:cmdpos - 2]
        let l:new_cmdline = l:Replace({}, l:cmdline, l:output)
      endif

      if exists('s:menus') &&
            \ (empty(s:menus) || s:menus[0] !=# l:cmdline)
        let s:menus = [l:cmdline] + s:menus
      endif
    else
      let l:cmdpos = s:replaced_cmdpos
      if l:cmdpos <= 1
        let l:new_cmdline = ''
      else
        let l:cmdline = s:replaced_cmdline
        let l:new_cmdline = l:cmdline[: l:cmdpos - 2]
      endif
    endif

    call s:feedkeys_cmdline(l:new_cmdline)

    let s:completion = l:new_cmdline
  else
    if exists('s:completion')
      unlet s:completion
    endif
  endif

  return "\<Insert>\<Insert>"
endfunction

function! s:feedkeys_cmdline(cmdline)
  let l:chars = split(a:cmdline, '\zs')

  let l:keys = "\<C-U>"

  for l:char in l:chars
    " control characters
    if l:char <# ' '
      let l:keys .= "\<C-Q>"
    endif

    let l:keys .= l:char
  endfor

  call feedkeys(l:keys, 'n')
endfunction

function! s:replace_all(ctx, cmdline, x)
  return a:x
endfunction

function! wildsearch#main#can_accept_completion()
  return wildsearch#main#in_context() &&
        \ exists('s:selected') && s:selected >= 0
endfunction

function! wildsearch#main#accept_completion() abort
  if exists('s:selected')
      let s:force = 1

      let s:auto_select = s:run_id
  endif

  return "\<Insert>\<Insert>"
endfunction

function! wildsearch#main#can_reject_completion()
  return wildsearch#main#in_context() && exists('s:menus')
endfunction

function! wildsearch#main#reject_completion() abort
  if exists('s:menus')
    if !empty(s:menus)
      let s:force = 1

      let s:previous_menu = s:menus[0]
      let s:menus = s:menus[1 :]

      " cmdline did not change, go 1 more step back
      if !empty(s:menus) && s:previous_menu ==# getcmdline()
        let s:previous_menu = s:menus[0]
        let s:menus = s:menus[1 :]
      endif

      call s:feedkeys_cmdline(s:previous_menu)
    else
      unlet s:menus
    endif
  endif

  return "\<Insert>\<Insert>"
endfunction

function! wildsearch#main#save_statusline() abort
  let s:old_laststatus = &laststatus
  let &laststatus = 2

  let s:old_statusline = &statusline
endfunction

function! wildsearch#main#restore_statusline() abort
  let &laststatus = s:old_laststatus
  let &statusline = s:old_statusline
  redrawstatus
endfunction

function! wildsearch#main#enable()
  let s:enabled = 1

  return ''
endfunction

function! wildsearch#main#disable()
  let s:enabled = 0

  call wildsearch#main#stop()

  return ''
endfunction

function! wildsearch#main#toggle()
  if s:enabled
    return wildsearch#main#disable()
  endif

  return wildsearch#main#enable()
endfunction
