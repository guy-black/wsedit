{-# LANGUAGE LambdaCase #-}

module WSEdit.Control.Text
    ( insert
    , insertRaw
    , insertTab
    , insertText
    , delLeft
    , delRight
    , smartHome
    , smartNewLine
    , dumbNewLine
    , cleanse
    ) where



import Control.Monad
    ( when
    )
import Control.Monad.RWS.Strict
    ( ask
    , get
    , modify
    )
import Data.Char
    ( isSpace
    )
import Safe
    ( fromJustNote
    , headNote
    , initNote
    , lastNote
    )

import WSEdit.Control.Base
    ( alterBuffer
    , alterState
    , moveCursor
    , moveCursorHome
    , refuseOnReadOnly
    , validateCursor
    )
import WSEdit.Data
    ( WSEdit
    , EdConfig
        ( tabWidth
        )
    , EdState
        ( cursorPos
        , edLines
        , overwrite
        , replaceTabs
        )
    )
import WSEdit.Data.Algorithms
    ( getCursor
    )
import WSEdit.Output
    ( stringWidth
    )
import WSEdit.Util
    ( delN
    , linesPlus
    , withPair
    , withSnd
    )

import qualified WSEdit.Buffer as B



fqn :: String -> String
fqn = ("WSEdit.Control.Text." ++)





-- | Inserts a character at the cursor location, moving the cursor to the
--   right and presenting autocomplete info in the status line.
insert :: Char -> WSEdit ()
insert c = alterBuffer $ insertRaw [c]



-- | Inserts a string at the cursor location, moving the cursor to the right.
--   Fast, but does not handle newlines correctly. Low-level function that
--   disregards undo functionality, read-only-ness, ...
insertRaw :: String -> WSEdit ()
insertRaw s = refuseOnReadOnly $ modify $ ins s
    where
        ins :: String -> EdState -> EdState
        ins s' st = st
            { edLines   = B.withCurr (withSnd (\l -> take (cursorPos st - 1) l
                                                  ++ s'
                                                  ++ drop ( cursorPos st
                                                          - if overwrite st
                                                               then 0
                                                               else 1
                                                          ) l
                                              )
                                     )
                        $ edLines st
            , cursorPos = cursorPos st + length s'
            }



-- | Inserts a tab character or the equivalent amount of spaces.
insertTab :: WSEdit ()
insertTab = alterBuffer $ do
    b      <- replaceTabs <$> get
    (r, c) <- getCursor

    -- Column the tab will sit in
    n <- (edLines <$> get)
     >>= (stringWidth r 1 . take (c - 1) . snd . B.pos)

    w <- tabWidth <$> ask

    if b
       then insertRaw $ replicate (w - n `mod` w) ' '
       else insertRaw "\t"



-- | Inserts text at the cursor position. The cursor will be positioned after
--   the inserted text. Low-level function that disregards undo functionality,
--   read-only-ness, ...
insertText :: String -> WSEdit ()
insertText s = refuseOnReadOnly $ do
    let l = linesPlus s
    modify $ \s' -> s' { edLines =
                            if length l == 1
                               then B.withCurr (withSnd (\c -> take (cursorPos s' - 1) c
                                                            ++ headNote (fqn "paste") l
                                                            ++ drop (cursorPos s' - 1) c
                                                        )
                                               )
                                  $ edLines s'

                               else B.insertLeft (False, lastNote (fqn "paste") l
                                                      ++ drop (cursorPos s' - 1)
                                                              (snd $ B.pos $ edLines s')
                                                 )
                                  $ flip (foldl (flip B.insertLeft))
                                         ( zip (repeat False)
                                         $ drop 1
                                         $ initNote (fqn "paste") l
                                         )
                                  $ B.withCurr (withSnd (\c -> take (cursorPos s' - 1) c
                                                            ++ headNote (fqn "paste") l
                                                        )
                                               )
                                  $ edLines s'
                       }

    if length l > 1
       then moveCursorHome
         >> moveCursor 0 (length $ last l)

       else moveCursor 0 $ length s



-- | Deletes the character left of the cursor, moving the cursor to the left.
--   If the cursor is at the front of its line, it will instead merge the line
--   to the previous one.
delLeft :: WSEdit ()
delLeft = alterBuffer
    $ getCursor >>= \case
        (1, 1) -> return ()
        (_, 1) -> modify merge

        (_, _) -> do
            moveCursor   0  (-   1)
            modify del'
    where
        del' :: EdState -> EdState
        del' s = s
            { edLines = B.withCurr (withSnd $ delN (cursorPos s - 1))
                      $ edLines s
            }

        merge :: EdState -> EdState
        merge s = s
            { edLines   = B.withCurr (withPair (|| (fst $ B.pos $ edLines s))
                                               (++ (snd $ B.pos $ edLines s))
                                     )
                        $ fromJustNote (fqn "delLeft:2")
                        $ B.deleteLeft
                        $ edLines s

            , cursorPos = (+1)
                        $ length
                        $ snd
                        $ fromJustNote (fqn "delLeft")
                        $ B.left
                        $ edLines s
            }



-- | Deletes the character right of the cursor. If the cursor is at the end of
--   its line, it will instead merge the line to the next one.
delRight :: WSEdit ()
delRight = alterBuffer $ do
    (cR, _) <- getCursor

    lns <- edLines <$> get

    let nLines  = B.length                                  lns
        lnWidth =   length $ snd $ B.atDef (undefined, "")  lns $ cR - 1

    getCursor >>= \case
        (r, c) | r == nLines && c == lnWidth + 1 -> return ()
        (_, c) |                c == lnWidth + 1 -> modify merge
        (_, _)                                   -> modify del'

    where
        del' :: EdState -> EdState
        del' s = s
            { edLines = B.withCurr (withSnd $ delN (cursorPos s - 1))
                      $ edLines s
            }

        merge :: EdState -> EdState
        merge s = s
            { edLines   = B.withCurr (withPair ((fst $ B.pos $ edLines s) ||)
                                               ((snd $ B.pos $ edLines s) ++)
                                     )
                        $ fromJustNote (fqn "delRight")
                        $ B.deleteRight
                        $ edLines s
            }



-- | Moves the cursor to the beginning of the text in the current line,
--   skipping leading whitespace. If the cursor is already there, it will
--   be moved to the front of the line instead.
smartHome :: WSEdit ()
smartHome = alterState $ do
    (_, cC) <- getCursor

    -- Calculate the target position
    pos <-  (+1)
         .  length
         .  takeWhile isSpace
         .  snd
         .  B.pos
         .  edLines
        <$> get

    moveCursorHome

    when (cC /= pos) $ moveCursor 0 $ pos - 1



-- | Splits the current line into two at the cursor position, indenting the
--   second resulting line to the level of the first.
smartNewLine :: WSEdit ()
smartNewLine = alterBuffer $ do
    modify snl
    smartHome

    where
        snl :: EdState -> EdState
        snl s =
            let
                ln = B.pos $ edLines s
            in
                s { edLines   = B.insertLeft (False, takeWhile isSpace      (snd ln)
                                                  ++ drop (cursorPos s - 1) (snd ln)
                                             )
                              $ B.withCurr (withSnd $ take (cursorPos s - 1))
                              $ edLines s

                  , cursorPos = 1
                  }



-- | Splits the current line into two at the current position.
dumbNewLine :: WSEdit ()
dumbNewLine = alterBuffer $ do
    modify nl
    moveCursorHome

    where
        nl :: EdState -> EdState
        nl s =
            let
                ln = B.pos $ edLines s
            in
                s { edLines = B.insertLeft (False, drop (cursorPos s - 1)
                                                 $ snd ln
                                           )
                            $ B.withCurr (withSnd $ take (cursorPos s - 1))
                            $ edLines s
                  }



-- | Removes all trailing whitespace in the text buffer.
cleanse :: WSEdit ()
cleanse = alterBuffer $ do
    modify (\s -> s { edLines = (\b -> if snd (B.last b) == ""
                                          then                      b
                                          else B.append (False, "") b
                                )
                              $ B.map (withSnd trim)
                              $ edLines s
                    }
           )

    validateCursor

    where
        trim :: String -> String
        trim = reverse . dropWhile isSpace . reverse
               -- performs awfully, but doesn't get executed too often...
