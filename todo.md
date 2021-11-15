# More things I'd like to do here

- Make ctrl-P respect selections
- https://github.com/LadyBoonami/wsedit/issues/30
  - change pipeThrough at Control/Global.hs ln 670
  - bold :: Buffer (Bool, String)
  - old :: String
    - basically whole buffer with \n between lines
    - need to change this to be just the higlighted text
  - getSelection (Data/Algorithms.hs ln 247)
    - :: WSEdit (Maybe String) with the higlighted text
  - readCreateProcessWithExitCode executes the shell or repl cmd the user types after ctrlp
    - sends old as standard input
    - returns (exitCode, stdout, stderr)
  ***figure out whats happening around ln 713 Control/Global.hs
  ***also figure out how the buffer works
- custom keymap support
-- including modifying how many lines/columns ctrl/alt move cursor
