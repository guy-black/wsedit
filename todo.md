# More things I'd like to do here

- Make ctrl-P respect selections
- https://github.com/LadyBoonami/wsedit/issues/30
  - change pipeThrough at Control/Global.hs ln 670
  - bold :: Buffer (Bool, String)
    the older buffer
  - old :: String
    - basically whole buffer with \n between lines
    - need to change this to be just the higlighted text
  - getSelection (Data/Algorithms.hs ln 247)
    - :: WSEdit (Maybe String) with the higlighted text
  - readCreateProcessWithExitCode executes the shell or repl cmd the user types after ctrlp
    - sends old as standard input
    - returns (exitCode, stdout, stderr)
  - ln 710, b is a new buffer made up of the output from the piped command with
    the cursor moved to it's last location in the old buffer
  - ln 719, modify is setting the edLines value in EdState
  *** figure out how to split the old buffer into the section before the selected
      text, and the section after selected text, stick b inbetween
        delSelection Algorithms ln 279
        deletes seleced text
        insertBefore Buffer ln 393
        takes Hashable a and a buffer, and produces a new buffer with the a
         [(Bool, String)] is hashable
         also is the type of the buffer
         Buffer (Bool,String)

    ***also figure out how the buffer works
- custom keymap support
-- including modifying how many lines/columns ctrl/alt move cursor
