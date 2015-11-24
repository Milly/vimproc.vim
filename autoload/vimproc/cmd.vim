"=============================================================================
" FILE: cmd.vim
" AUTHOR:  Shougo Matsushita <Shougo.Matsu@gmail.com>
" License: MIT license  {{{
"     Permission is hereby granted, free of charge, to any person obtaining
"     a copy of this software and associated documentation files (the
"     "Software"), to deal in the Software without restriction, including
"     without limitation the rights to use, copy, modify, merge, publish,
"     distribute, sublicense, and/or sell copies of the Software, and to
"     permit persons to whom the Software is furnished to do so, subject to
"     the following conditions:
"
"     The above copyright notice and this permission notice shall be included
"     in all copies or substantial portions of the Software.
"
"     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
"     OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
"     MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
"     IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
"     CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
"     TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
"     SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
" }}}
"=============================================================================

" Saving 'cpoptions' {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}

let s:meta_chars = '()%!^"<>&|'

function! s:quote_cmd_arg(arg, meta_chars) "{{{
  if strlen(a:arg) && a:arg !~ '[[:space:]"' . a:meta_chars . ']'
    return a:arg
  endif
  let res = '"'
  let in_quote = 0
  let even_quote = 1
  let s = split(a:arg, '\zs')
  let [i, max] = [0, len(s)]
  while i < max
    let backslashes = 0
    while i < max && s[i] ==# '\'
      let i += 1
      let backslashes += 1
    endwhile
    let res .= repeat('\', backslashes)
    if s[i] ==# '"'
      let in_quote = (backslashes % 2 == 0) ? !in_quote : in_quote
      let even_quote = !even_quote
    elseif in_quote && even_quote && stridx(a:meta_chars, s[i]) >= 0
      let res .= '^'
    endif
    let res .= s[i]
    let i += 1
  endwhile
  let res .= '"'
  return res
endfunction"}}}

function! s:quote_proc_arg(arg, meta_chars, even_quote) "{{{
  if strlen(a:arg) && a:arg !~ '[[:space:]"' . a:meta_chars . ']'
    return [a:arg, a:even_quote]
  endif
  let res = '"'
  let even_quote = !a:even_quote
  let s = split(a:arg, '\zs')
  let [i, max] = [0, len(s)]
  while i < max
    let backslashes = 0
    while i < max && s[i] ==# '\'
      let i += 1
      let backslashes += 1
    endwhile
    if i == max
      let res .= repeat('\', backslashes * 2)
      break
    elseif s[i] ==# '"'
      let res .= repeat('\', backslashes * 2 + 1)
      let even_quote = !even_quote
    else
      let res .= repeat('\', backslashes)
      if even_quote && stridx(a:meta_chars, s[i]) >= 0
        let res .= '^'
      endif
    endif
    let res .= s[i]
    let i += 1
  endwhile
  let res .= '"'
  return [res, !even_quote]
endfunction"}}}

function! s:build_cmdline(argv, console) "{{{
  if empty(a:argv)
    return ''
  endif

  if a:console
    let [meta1, meta2] = [s:meta_chars, '']
  else
    let [meta1, meta2] = ['', s:meta_chars]
  endif

  let arg0 = '"' . substitute(
        \ substitute(a:argv[0], '/', '\', 'g'),
        \ '"', '""', 'g') . '"'
  let even_quote = 1
  let args = []
  for arg in a:argv[1:]
    let [quoted, even_quote] = s:quote_proc_arg(arg, meta1, even_quote)
    call add(args, quoted)
  endfor

  " check a:argv[0] is cmd.exe
  if match(a:argv[0], '\c\%(\_^\|[/\\]\)cmd\%(.exe\)\?$') >= 0
    let pos = match(args, '\c/[ckr]') + 1
    if pos > 0
      let cmdlen = len(args) - pos
      if cmdlen == 1
        let args[pos] = s:quote_cmd_arg(a:argv[pos + 1], s:meta_chars)
      elseif cmdlen >= 2
        let args[pos] = s:quote_cmd_arg(join(args[pos :]), meta2)
        unlet args[pos + 1:]
      endif
    endif
  endif

  return join([arg0] + args)
endfunction"}}}

function! vimproc#cmd#build_cmdline(argv)
  return s:build_cmdline(a:argv, 0)
endfunction

function! vimproc#cmd#shellescape(string)
  return s:quote_proc_arg(a:string, '', 0)[0]
endfunction

if !vimproc#util#is_windows()
  function! vimproc#cmd#system(expr, ...)
    let timeout = get(a:000, 0, 0)
    return vimproc#system(a:expr, '', timeout)
  endfunction
  let &cpo = s:save_cpo
  finish
endif

" Based from : http://d.hatena.ne.jp/osyo-manga/20130611/1370950114

let s:cmd = {}
let s:read_timeout = 100
let s:prompt = '_-_EOF_-_$L$P$G'
let s:prompt_match = '^_-_EOF_-_<[^>]*>'
let s:prompt_cwd_match = '<\zs[^>]*\ze>'

augroup vimproc
  autocmd VimLeave * call s:cmd.close()
augroup END


function! s:print_error(string)
  echohl Error | echomsg '[vimproc] ' . a:string | echohl None
endfunction

function! s:cmd.open() "{{{
  if exists('self.vimproc') && self.vimproc.is_valid
    " Already opened.
    return
  endif

  let cmd = 'cmd.exe'
  let self.vimproc = vimproc#popen2(cmd)
  let self.cwd = getcwd()

  " Wait until getting first prompt.
  call self.vimproc.stdin.write("prompt " . s:prompt . "\n")
  let output = ''
  while output !~ s:prompt_match
    let output .= self.vimproc.stdout.read()
    let output = strpart(output, strridx(output, "\n") + 1)
  endwhile
endfunction"}}}

function! s:cmd.close() "{{{
  if exists('self.vimproc')
    call self.vimproc.waitpid()
  endif
endfunction"}}}

function! s:cmd.system(cmd, timeout) "{{{
  " Execute cmd.
  call self.open()

  if self.cwd !=# getcwd()
    " Execute cd.
    let input = '(cd /D "' . getcwd() . '" & ' . a:cmd . ')'
    let self.cwd = getcwd()
  else
    let input = a:cmd
  endif

  call self.vimproc.stdin.write(input . "\n")

  if a:timeout > 0 && has('reltime') && v:version >= 702
    let start = reltime()
    let deadline = a:timeout
    let timeout = a:timeout / 2
  else
    let start = 0
    let deadline = 0
    let timeout = s:read_timeout
  endif

  " Wait until getting prompt.
  let output = ''
  try
    while !self.vimproc.stdout.eof
      if deadline "{{{
        " Check timeout.
        let tick = reltimestr(reltime(start))
        let elapse = str2nr(tick[:-8] . tick[-6:-4], 10)
        if deadline <= elapse
          " Kill process.
          throw 'vimproc: vimproc#cmd#system(): Timeout.'
        endif
        let timeout = (deadline - elapse) / 2
      endif"}}}

      let output .= self.vimproc.stdout.read(-1, timeout)
      let lastnl = strridx(output, "\n")
      if lastnl >= 0 && match(output, s:prompt_match, lastnl + 1) >= 0
        break
      endif
    endwhile
    let self.cwd = matchstr(output, s:prompt_cwd_match, lastnl + 1)
    if &ssl
      let self.cwd = substitute(self.cwd, '\\', '/', 'g')
    endif
    let result = split(output, '\r\n\|\n')[1:-2]
  catch
    call self.close()
    let result = split(output, '\r\n\|\n')[1:]

    if v:exception !~ '^Vim:Interrupt'
      call s:print_error(v:throwpoint)
      call s:print_error(v:exception)
    endif
  endtry

  return join(result, "\n")
endfunction"}}}

function! vimproc#cmd#system(expr, ...)
  let cmd = type(a:expr) == type('') ? a:expr : s:build_cmdline(a:expr, 1)
  let timeout = get(a:000, 0, 0)
  return s:cmd.system(cmd, timeout)
endfunction

" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
" vim:foldmethod=marker:fen:sw=2:sts=2
