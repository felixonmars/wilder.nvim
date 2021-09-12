function! wilder#renderer#component#wildmenu_condition#(predicate, if_true, if_false) abort
  let l:state = {
        \ 'predicate': a:predicate,
        \ 'if_true': a:if_true,
        \ 'if_false': a:if_false,
        \ }

  let l:dynamic = wilder#renderer#is_dynamic_component(a:if_true) ||
        \ wilder#renderer#is_dynamic_component(a:if_false)

  return {
        \ 'value': {ctx, result -> s:value(l:state, ctx, result)},
        \ 'len': {ctx, result -> s:len(l:state, ctx, result)},
        \ 'pre_hook': {ctx -> s:pre_hook(l:state, ctx)},
        \ 'post_hook': {ctx -> s:post_hook(l:state, ctx)},
        \ 'dynamic': l:dynamic,
        \ }
endfunction

function! s:pre_hook(state, ctx) abort
  call wilder#renderer#call_component_pre_hook(a:ctx, a:state.if_true)
  call wilder#renderer#call_component_pre_hook(a:ctx, a:state.if_false)
endfunction

function! s:post_hook(state, ctx) abort
  call wilder#renderer#call_component_post_hook(a:ctx, a:state.if_true)
  call wilder#renderer#call_component_post_hook(a:ctx, a:state.if_false)
endfunction

function! s:len(state, ctx, result) abort
  let l:Chosen = a:state.predicate(a:ctx, a:result)
        \ ? a:state.if_true
        \ : a:state.if_false

  return wilder#renderer#wildmenu#get_item_len(l:Chosen, a:ctx, a:result)
endfunction

function! s:value(state, ctx, result) abort
  let l:Chosen = a:state.predicate(a:ctx, a:result)
        \ ? a:state.if_true
        \ : a:state.if_false

  return wilder#renderer#wildmenu#draw_item(l:Chosen, a:ctx, a:result)
endfunction
