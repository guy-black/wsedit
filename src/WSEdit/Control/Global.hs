{-# LANGUAGE LambdaCase
           , MultiWayIf
           #-}

module WSEdit.Control.Global
    ( simulateCrash
    , emergencySave
    , bail
    , dumpState
    , quitComplain
    , quit
    , forceQuit
    , canWriteFile
    , save
    , load
    , toggleTabRepl
    , toggleInsOvr
    , toggleReadOnly
    , undo
    , pipeThrough
    ) where


import Control.DeepSeq
    ( ($!!)
    , force
    )
import Control.Exception
    ( SomeException
    , evaluate
    , try
    )
import Control.Monad
    ( when
    , void
    )
import Control.Monad.IO.Class
    ( liftIO
    )
import Control.Monad.RWS.Strict
    ( ask
    , get
    , gets
    , local
    , modify
    , put
    )
import Data.Function
    ( on
    )
import Data.Maybe
    ( fromMaybe
    , isJust
    )
import Graphics.Vty
    ( Vty
        ( shutdown
        )
    , nextEvent
    )
import Safe
    ( fromJustNote
    , headDef
    )
import System.Directory
    ( copyPermissions
    , doesFileExist
    , getHomeDirectory
    , getPermissions
    , makeRelativeToCurrentDirectory
    , removeFile
    , renameFile
    , writable
    )
import System.Exit
    ( ExitCode
        ( ExitSuccess
        , ExitFailure
        )
    , exitFailure
    )
import System.IO
    ( IOMode
        ( AppendMode
        , ReadMode
        , WriteMode
        )
    , NewlineMode
    , hGetContents
    , hPutStr
    , hSetEncoding
    , hSetNewlineMode
    , mkTextEncoding
    , universalNewlineMode
    , withFile
    )
import System.Process
    ( CreateProcess
        ( CreateProcess
        , child_group
        , child_user
        , close_fds
        , cmdspec
        , create_group
        , create_new_console
        , cwd
        , delegate_ctlc
        , detach_console
        , env
        , new_session
        , std_err
        , std_in
        , std_out
        , use_process_jobs
        )
    , CmdSpec
        ( ShellCommand
        )
    , readCreateProcessWithExitCode
    )
import Text.Show.Pretty
    ( ppShow
    )

import WSEdit.Control.Autocomplete
    ( dictAddRec
    )
import WSEdit.Control.Base
    ( alterBuffer
    , alterState
    , askConfirm
    , fetchCursor
    , moveCursor
    , refuseOnReadOnly
    , standby
    , validateCursor
    )
import WSEdit.Control.Text
    ( cleanse
    , insertText
    )
import WSEdit.Data
    ( CanonicalPath
        ( getCanonicalPath
        )
    , EdConfig
        ( atomicSaves
        , encoding
        , initJMarks
        , newlineMode
        , preserveWsp
        , purgeOnClose
        , readEnc
        , vtyObj
        , wriCheck
        )
    , EdState
        ( changed
        , continue
        , cursorPos
        , detectTabs
        , dict
        , edLines
        , exitMsg
        , fname
        , lastEvent
        , loadPos
        , markPos
        , overwrite
        , readOnly
        , replaceTabs
        )
    , ReadEnc
        ( ReadEncSet
        , ReadEncAuto
        , ReadEncDef
        )
    , WSEdit
    , runWSEdit
    , version
    )
import WSEdit.Data.Algorithms
    ( canonicalPath
    , catchEditor
    , chopHist
    , delSelection
    , getCursor
    , getSelection
    , mapPast
    , popHist
    , setOffset
    , setStatus
    , tryEditor
    )
import WSEdit.Data.Pretty
    ( prettyEdConfig
    )
import WSEdit.Output
    ( drawExitFrame
    , getViewportDimensions
    )
import WSEdit.Util
    ( linesPlus
    , readEncFile
    , unlinesPlus
    , withFst
    , withPair
    )
import WSEdit.WordTree
    ( empty
    )

import qualified WSEdit.Buffer as B


fqn :: String -> String
fqn = ("WSEdit.Control.Global." ++)





-- | Crashes the editor. Used for debugging. Mapped to @F9@, test it if you
--   dare.
simulateCrash :: WSEdit ()
simulateCrash = error "Simulated crash."


-- | Dump the current file state into @$HOME/CRASH-RESCUE@ unconditionally using
--   the system's default encoding. This, as the name suggests, is an emergency
--   function so we're not taking any chances. I'd rather have a correct file in
--   the wrong format than a corrupted file in the right one.
emergencySave :: WSEdit ()
emergencySave = do
    h <- liftIO $ getHomeDirectory
    s <- get
    c <- ask

    liftIO $ writeF (h ++ "/CRASH-RESCUE") (newlineMode c)
           $ unlinesPlus
           $ map snd
           $ B.toList
           $ edLines s

    where
        writeF :: FilePath -> NewlineMode -> String -> IO ()
        writeF path nl cont = withFile path WriteMode $ \h -> do
            hSetNewlineMode h nl
            hPutStr h cont


-- | Shuts down vty gracefully, prints out an error message, creates a
--   (potentially quite sizeable) error dump at "./CRASH-DUMP" and finally exits
--   with return code 1. The optional first parameter can be used to indicate
--   the subsystem where the error occured.
bail :: Maybe String -> String -> WSEdit ()
bail mayComp s = do
    c  <- ask
    st <- get

    r <- tryEditor $ do
        h  <- liftIO $ getHomeDirectory

        flip catchEditor (const $ return ())
            $ standby
            $ unlinesPlus
                [ s
                , ""
                , "Writing state dump to $HOME/CRASH-DUMP ..."
                ]

        dumpState (h ++ "/CRASH-DUMP")
              $ "WSEDIT " ++ version ++ " CRASH LOG\n"
             ++ "Error message: " ++ (headDef "" $ lines s)
                   ++ maybe "" (\str -> " (" ++ str ++ ")") mayComp
             ++ "\nLast recorded event: "
                   ++ fromMaybe "-" (fmap show $ lastEvent st)

    drawExitFrame

    liftIO $ do
        shutdown $ vtyObj c
        putStrLn s
        putStrLn "A state dump is located at $HOME/CRASH-DUMP ."

        case r of
             Right _  -> return ()
             Left err -> putStrLn $ "\nAdditionally, the exception handler crashed with this message:\n"
                                 ++ show err

        exitFailure


-- | Dumps the editor state and config to a given file, with a given prefix
--   added as the first few lines.
dumpState :: FilePath -> String -> WSEdit ()
dumpState f pref = do
    c  <- ask
    st <- get

    liftIO
        $ writeFile f
        $ pref
            ++ "\n\nEditor configuration:\n"
            ++ indent (ppShow $ prettyEdConfig c)
            ++ "\n\nEditor state:\n"
            ++ indent ( ppShow
                      $ mapPast (\hs -> hs { dict = empty })
                      $ fromJustNote (fqn "dumpState")
                      $ chopHist 10
                      $ Just st
                      )
    where
        indent :: String -> String
        indent = unlinesPlus . map ("    " ++) . linesPlus


-- | Similar to 'bail', but does not generate a state dump.
quitComplain :: String -> WSEdit ()
quitComplain s = do
    v <- vtyObj <$> ask

    drawExitFrame

    liftIO $ do
        shutdown v
        putStrLn s
        exitFailure


-- | Checks for unsaved changes, then either complains via 'setStatus' or calls
--   'forceQuit'.
quit :: WSEdit ()
quit = do
    b <- changed <$> get
    if b
       then setStatus "Unsaved changes: Ctrl-S to save, Ctrl-Meta-Q to ignore."
       else forceQuit


-- | Tells the main loop to exit gracefully.
forceQuit :: WSEdit ()
forceQuit = do
    b1 <- purgeOnClose <$> ask
    when b1 $ liftIO $ do
        h <- getHomeDirectory
        let cpath = h ++ "/.wsedit-clipboard"

        b2 <- doesFileExist cpath
        when b2 $ removeFile cpath

    modify (\s -> s { continue = False })



-- | Returns whether or not the current file is writable.
canWriteFile :: WSEdit Bool
canWriteFile = do
    f <- fname <$> get

    liftIO $ do
        b <- doesFileExist f

        if b
           then writable <$> getPermissions f
           else try (do
                        withFile f AppendMode $ const $ return ()
                        removeFile f
                    ) >>= \case
                        Right _ -> return True
                        Left  e -> const (return False) (e :: SomeException)

    -- I am aware of the fact that this code is pretty awful, but it has yet to
    -- fail me and/or break anything.



-- | Saves the text buffer to the file name in the editor state.
save :: WSEdit ()
save = refuseOnReadOnly $ do
    standby "Saving..."

    w <- canWriteFile
    if not w
       then setStatus "File not writeable."

       else do
            c <- ask

            when (not $ preserveWsp c) cleanse

            s <- get

            let
                targetFName = if atomicSaves c
                                 then fname s ++ ".atomic"
                                 else fname s

            liftIO $ writeF targetFName (encoding c) (newlineMode c)
                   $ unlinesPlus
                   $ map snd
                   $ B.toList
                   $ edLines s

            b <- if atomicSaves c && wriCheck c
                    then doWriCheck
                    else return True

            when (atomicSaves c && b) $ do
                liftIO $ do
                    real <- liftIO $ fmap getCanonicalPath $ canonicalPath Nothing $ fname s
                    doesFileExist real
                        >>= flip when ( copyPermissions real
                                      $ fname s ++ ".atomic"
                                      )

                    renameFile (fname s ++ ".atomic") real

            when (not (atomicSaves c) || b) $ do
                modify $ \s' -> s' { changed = False }

                setStatus $ "Saved "
                             ++ show (B.length (edLines s))
                             ++ " lines of "
                             ++ fromMaybe "native" (encoding c)
                             ++ " text."

    dictAddRec

    where
        writeF :: FilePath -> Maybe String -> NewlineMode -> String -> IO ()
        writeF path mayEnc nl cont = withFile path WriteMode $ \h -> do
            case mayEnc of
                 Nothing  -> return ()
                 Just enc -> do
                    e <- mkTextEncoding enc
                    hSetEncoding h e

            hSetNewlineMode h nl
            hPutStr h cont

        doWriCheck :: WSEdit Bool
        doWriCheck = fmap wriCheck ask >>= \case
            False -> return True
            True  -> do
                s <- get
                put $ s { fname   = fname s ++ ".atomic" }
                _ <- local (\c -> c { readEnc = maybe ReadEncDef ReadEncSet $ encoding c })
                   $ load False
                s' <- get
                put s
                if (on (==) (map snd . B.toList) (edLines s) (edLines s'))
                   then return True
                   else do
                        c <- ask
                        liftIO $ runWSEdit ( c { encoding    = Nothing
                                               , newlineMode = universalNewlineMode
                                               }
                                           , s
                                           )
                               $ emergencySave

                        let m = "The Write-Read identity check failed.\n\n"
                             ++ "Your saved file would have been corrupted and "
                             ++ "got reset to the last save, your changes have "
                             ++ "been dumped to $HOME/CRASH-RESCUE using your "
                             ++ "system's native encoding.\n\n"
                             ++ "This isssue is probably due to the use of a "
                             ++ "non-standard text encoding. Encoding "
                             ++ "irregularities are a known issue, please try "
                             ++ "using a different setting for the time being."

                        modify (\s'' -> s'' { continue = False
                                            , exitMsg  = Just m
                                            }
                               )

                        liftIO $ removeFile (fname s ++ ".atomic")
                        return False



-- | Tries to load the text buffer from the file name in the editor state.
--   Pass 'True' to make it display a loading screen (pun not entirely
--   unintended) and rebuild the dictionary or 'False' to make it a raw load.
--   `load` returns `False` when the loading process was aborted. This will
--   never occur for a raw load.
load :: Bool -> WSEdit Bool
load lS = alterState $ do
    when lS $ standby "Loading..."

    p <- fname <$> get
    when (p == "") $ quitComplain "Will not load an empty filename."

    b <- liftIO $ doesFileExist p
    w <- canWriteFile
    p' <- liftIO $ makeRelativeToCurrentDirectory p

    s <- get
    c <- ask

    (mEnc, txt) <- if b
                      then liftIO $ doFile (readEnc c) p'
                      else return (Just undefined, "")

    let
        l = linesPlus txt
        nChrs = length txt
        nLns  = length l
        nLine = maximum $ map length l



    doLoad <- if | not lS           -> return True
                 | nLns  > 10000    ->
                       askConfirm
                           ( "The file you're about to load is very long ("
                          ++ show nLns
                          ++ " lines). WSEdit is not built for handling huge "
                          ++ "files, loading might take up to a few minutes "
                          ++ "and editing will be slow. Continue anyways?"
                           )

                 | nLine > 1000     ->
                       askConfirm
                           ( "The file you're about to load contains very long "
                          ++ "lines ("
                          ++ show nLine
                          ++ " characters). WSEdit is not built for handling "
                          ++ "these, loading might take up to a few minutes "
                          ++ "and editing will be slow. Continue anyways?"
                           )

                 | nChrs > 10000000 ->
                       askConfirm
                           ( "The file you're about to load is very large ("
                          ++ show nChrs
                          ++ " characters). WSEdit is not built for handling "
                          ++ "huge files, loading might take up to a few "
                          ++ "minutes and editing will be slow. Continue "
                          ++ "anyways?"
                           )

                 | otherwise        -> return True

    if doLoad
       then do
            when lS $ standby "Rebuilding hashes..."

            l' <- liftIO
                $ evaluate
                $ force
                $ B.toFirst
                $ fromMaybe (B.singleton (False, ""))
                $ B.fromList
                $ map (withFst (`elem` initJMarks c))
                $ zip [1..] l

            put $ s
                { edLines     = l'
                , fname       = p'
                , cursorPos   = 1
                , readOnly    = not (isJust mEnc && w && not (readOnly s))
                , replaceTabs = if detectTabs s
                                   then '\t' `notElem` txt
                                   else replaceTabs s
                }

            when lS $ setStatus
                    $ case (b    , w    , mEnc   ) of
                           (True , True , Just e ) -> "Loaded "
                                                   ++ show (nLns)
                                                   ++ " lines of "
                                                   ++ e
                                                   ++ " text."

                           (True , False, Just e ) -> "Warning: "
                                                   ++ e
                                                   ++ " file not writable, "
                                                   ++ "opening in read-only "
                                                   ++ "mode ..."

                           (True , _    , Nothing) -> "Warning: unknown "
                                                   ++ "character encoding, "
                                                   ++ "opening raw..."

                           (False, True , _      ) -> "Warning: file "
                                                   ++ p'
                                                   ++ " not found, creating on "
                                                   ++ "save ..."

                           (False, False, _      ) -> "Warning: cannot create "
                                                   ++ "file "
                                                   ++ p'
                                                   ++ " , check permissions "
                                                   ++ "and disk state."

            -- Move the cursor to where it should be placed.
            uncurry moveCursor $ withPair dec dec $ loadPos s
            when (loadPos s /= (1, 1)) $ do
                rs     <- fst <$> getViewportDimensions
                actpos <- fst <$> getCursor
                setOffset (actpos - 1 - rs `div` 3, 0)
                validateCursor

            when lS $ dictAddRec

            return True

       else return False

    where
        dec :: Int -> Int
        dec n = n - 1

        doFile :: ReadEnc -> FilePath -> IO (Maybe String, String)
        doFile ReadEncAuto f = readEncFile f
        doFile re          f = withFile f ReadMode $ \h -> do
            hSetNewlineMode h universalNewlineMode
            case re of
                 ReadEncSet e -> mkTextEncoding e >>= hSetEncoding h
                 _            -> return ()
            s <- hGetContents h
            let etxt = case re of
                            ReadEncSet e -> Just e
                            ReadEncDef   -> Just "native"
                            _            -> Nothing
            return $!! (etxt, s)



-- | Toggle the replacement of tabs with spaces.
toggleTabRepl :: WSEdit ()
toggleTabRepl = do
    s <- get
    put $ s { replaceTabs = not $ replaceTabs s }



-- | Toggle insert / overwrite mode
toggleInsOvr :: WSEdit ()
toggleInsOvr = modify (\s -> s { overwrite = not $ overwrite s })



-- | Toggle read-only mode.
toggleReadOnly :: WSEdit ()
toggleReadOnly = alterState $ do
    s <- get
    if readOnly s
       then do
            canWriteFile >>= flip when (setStatus "Warning: no write permissions on file.")

            put $ s { readOnly = False }
            fetchCursor

       else put $ s { readOnly  = True
                    , cursorPos = 1
                    , markPos   = Nothing
                    , edLines   = B.toFirst $ edLines s
                    }

            -- This puts the cursor to (1, 1), where it gets hidden by the
            -- output functions.



-- | Undo the last action as logged by 'alterBuffer'.
undo :: WSEdit ()
undo = refuseOnReadOnly
     $ alterState
     $ popHist >> validateCursor



-- | Pipe all text through an external command.
pipeThrough :: String -> WSEdit ()
pipeThrough cmd = alterBuffer $ do
    bold       <- gets edLines
    (old, sel) <- getSelection >>= \case
        Just b  -> return (b, True)
        Nothing -> return (unlinesPlus $ map snd $ B.toList bold, False)

    (ex, out, err) <- liftIO
        $ readCreateProcessWithExitCode
            ( CreateProcess
                { cmdspec            = ShellCommand cmd
                , cwd                = Nothing
                , env                = Nothing
                , std_in             = undefined -- These get
                , std_out            = undefined -- filled out
                , std_err            = undefined -- by readCreateProcessWithExitCode
                , close_fds          = True
                , create_group       = False
                , delegate_ctlc      = True
                , detach_console     = False
                , create_new_console = False
                , new_session        = False
                , child_group        = Nothing
                , child_user         = Nothing
                , use_process_jobs   = False
                }
            )
          old

    setStatus $ show ex

    case ex of
         ExitFailure _ -> do
            standby err
            c <- ask
            void $ liftIO $ nextEvent $ vtyObj c

         ExitSuccess -> do
            if sel
               then delSelection >> insertText out
               else do
                        b <- liftIO
                           $ evaluate
                           $ force
                           $ B.moveTo (B.currPos bold)
                           $ fromMaybe (B.singleton (False, ""))
                           $ B.fromList
                           $ zip (repeat False)
                           $ linesPlus out

                        modify $ (\s -> s { edLines = b })

            validateCursor
            dictAddRec
