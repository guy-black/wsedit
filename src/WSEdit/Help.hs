{-# LANGUAGE LambdaCase #-}

module WSEdit.Help
    ( confHelp
    , keymapHelp
    , usageHelp
    , versionHelp
    ) where


import Data.Char
    ( isAlphaNum
    , toUpper
    )
import Data.List
    ( delete
    , genericLength
    , sortOn
    )
import Data.Maybe
    ( catMaybes
    )
import Graphics.Vty
    ( Button
        ( BLeft
        , BMiddle
        , BRight
        , BScrollUp
        , BScrollDown
        )
    , Event
        ( EvKey
        , EvMouseDown
        )
    , Key
        ( KBackTab
        , KBS
        , KChar
        , KFun
        )
    , Modifier
        ( MCtrl
        , MMeta
        , MShift
        )
    )
import Safe
    ( headDef
    , lastDef
    , maximumNote
    )

import WSEdit.Data
    ( Keymap
    , stability
    , upstream
    , version
    )
import WSEdit.Data.Pretty
    ( prettyKeymap
    )
import WSEdit.Util
    ( chunkWords
    , padRight
    , unlinesPlus
    , withFst
    , withN
    )



fqn :: String -> String
fqn = ("WSEdit.Help." ++)



-- | Aligns the given lines for the given amount of columns.
renderText :: Int -> [String] -> String
renderText nCols = unlinesPlus . map (renderLine nCols)
    where
        -- | Split a string into words plus the amount of spaces preceding it.
        spl :: String -> [(Int, String)]
        spl []       = []
        spl (' ':xs) = case spl xs of
                            (r:rs) -> withFst (+1) r : rs
                            []     -> []

        spl ( x :xs) = case spl xs of
                            (r:rs) | fst r == 0 -> (0,  x : snd r) : rs
                            l                   -> (0, [x]       ) : l


        -- | Given a list of indices, the total number of spaces to insert and
        --   the output of `spl`, keep increasing the preceding number of spaces
        --   in the order given by the list.
        padBy :: [Int] -> Int -> [(Int, String)] -> [(Int, String)]
        padBy (x:xs) n l | n > 0     = padBy xs (n-1) $ withN x (withFst (+1)) l
                         | otherwise = l
        padBy []     _ _             = error "padBy: list too short."


        renderLine :: Int -> String -> String
        renderLine n s | length      s >  n   = "[!!!] " ++ s ++ " [!!!]"
                       | lastDef '.' s == ' ' = "[ ! ] " ++ s ++ " [ ! ]"
                       | otherwise            =
                        let
                            sp     = spl s

                            maxPad = 2

                            -- | indices of spaces egligible for expansion,
                            --   ordered by some preference rating
                            lenPrm = map fst
                                   $ sortOn snd
                                   $ map (\ (i, ((_, s1), (_, s2)))
                                         -> (i, sqrt (genericLength s1)
                                              + sqrt (genericLength s2)
                                                :: Double
                                            )
                                         )
                                   $ filter (\(_, ((_, s1), (l, s2))) -> l == 1
                                                                      && s1 /= ""
                                                                      && (  isAlphaNum (headDef '.' s1)
                                                                         || isAlphaNum (headDef '.' s2)
                                                                         )
                                            )
                                   $ zip [0..]
                                   $ zip ((0, "") : init sp) sp

                            draft  = if null lenPrm
                                        then sp
                                        else padBy (cycle lenPrm) (n - length s) sp

                        in
                            if lastDef '.' s `elem` ".:!?"
                                || n - length s > maxPad * length lenPrm
                               then s
                               else concatMap (\(m, w) -> replicate m ' ' ++ w)
                                        draft





-- | Generates help text describing the given keymap.
keymapHelp :: Keymap -> String
keymapHelp km =
    let
        wdt = 4 + maximumNote (fqn "keymapInfo")
                              ( map (length . showEv. fst)
                              $ catMaybes $ prettyKeymap km
                              )
    in
        renderText 80
      $ [ "Some terminals are a bit weird when it comes to telling Meta-<something> and"
        , "Ctrl-Meta-<something> apart. If one doesn't work, try the other. If none work,"
        , "please open an issue on GitHub and don't forget to add which terminal emulator"
        , "you're using."
        , ""
        , "-*- Keymap -*-"
        , ""
        ]
     ++ ( map (uncurry (++))
        $ concatMap (\case
            Nothing     -> [("",""), ("","")]
            Just (e, s) ->
                zip ( padRight wdt ' ' (showEv e)
                    : repeat (replicate wdt ' ')
                    ) $ chunkWords (80 - wdt) s
                   )
        $ prettyKeymap km
        )

    where
        showEv :: Event -> String
        showEv (EvKey           k ml) = showMods ml ++ showKey k
        showEv (EvMouseDown c r b ml) = showMods ml ++ showBtn b ++ " @ "
                                                                 ++ show (r, c)
        showEv _                      = "<unknown event>"

        showMods :: [Modifier] -> String
        showMods ml | MCtrl  `elem` ml = "Ctrl-"  ++ showMods (delete MCtrl  ml)
                    | MMeta  `elem` ml = "Meta-"  ++ showMods (delete MMeta  ml)
                    | MShift `elem` ml = "Shift-" ++ showMods (delete MShift ml)
                    | otherwise        = ""

        showKey :: Key -> String
        showKey (KChar '@' ) = "Space"
        showKey (KChar '\t') = "Tab"
        showKey (KChar  c  ) = [toUpper c]
        showKey  KBS         = "Backspace"
        showKey  KBackTab    = "Shift-Tab"
        showKey (KFun   n  ) = 'F' : show n
        showKey  k           = drop 1 $ show k

        showBtn :: Button -> String
        showBtn BLeft       = "LMB"
        showBtn BMiddle     = "MMB"
        showBtn BRight      = "RMB"
        showBtn BScrollUp   = "Scroll Up"
        showBtn BScrollDown = "Scroll Down"





--                                                                        margin (87) |

-- | Help string detailing persistent configuration.
confHelp :: String
confHelp = renderText 80
    [ "Persistent Configuration"
    , ""
    , "There are four distinct locations from which you can influence the behaviour of"
    , "wsedit:"
    , ""
    , "  *  The files \"/etc/wsedit/**/*.wsconf\" and"
    , "     \"/usr/local/etc/wsedit/**/*.wsconf\", intended primarily for system-wide"
    , "     language definitions (see \"wsedit -h\" --> Language Options)"
    , ""
    , "  *  The files \"~/.config/wsedit/**/*.wsconf\", intended primarily for user"
    , "     language definitions (see \"wsedit -h\" --> Language Options)"
    , ""
    , "  *  The file \"~/.config/wsedit.wsconf\" (shortcut: \"wsedit -ocg\"), intended for"
    , "     global settings"
    , ""
    , "  *  The files \".local.wsconf\" (shortcut: \"wsedit -ocl\"), intended for folder-"
    , "     specific settings. These are read starting from \"/.local.wsconf\","
    , "     descending all the way to the location of the opened file."
    , ""
    , "  *  The command line parameters"
    , ""
    , "You can place (almost) every command listed by \"wsedit -h\" in each of those"
    , "locations. They will be evaluated in the order defined above, with later"
    , "switches overriding the earlier ones, should they collide."
    , ""
    , "The syntax for configuration files is quite simple:"
    , ""
    , "    # Make tab substitution default for all haskell (.hs) files:"
    , "    *.hs: -ets"
    , ""
    , "    # Keywords with spaces:"
    , "    *.bas: -lk \"End Function\""
    , ""
    , "    # Double quotes and backslashes need to be escaped:"
    , "    *.lua: -lsr \\\" \\\""
    , "    *.cpp: -le \\\\"
    , ""
    , "    # Mark xmobar's config file as a file with haskell-style syntax:"
    , "    /home/boonami/.xmobarrc: -mi somefile.hs"
    , ""
    , "    # Make some bulk adjustments to all .hs files"
    , "    *.hs"
    , "        -ets"
    , "        -ei 4"
    , "    # Note:"
    , "    #     - There is no colon behind the file selector."
    , "    #     - All arguments have to be indented by at least one space/tab."
    , "    #     - One argument per line."
    , "    #     - Don't put empty lines or comments into a block."
    , ""
    , "Use # as the first non-whitespace character in a line to add comments. Despite"
    , "the syntax highlighting suggesting otherwise, placing a # behind a statement"
    , "counts as part of the statement, and not as a comment."
    , ""
    , ""
    , "If no path prefix is given, only the file name portion will be matched against."
    , "Otherwise, the full path is matched. Relative paths are relative to the"
    , "parent folder of the comfig file containing them, or the current working"
    , "directory if given via command-line argument. Examples:"
    , ""
    , "    Data.hs           matches the file Data.hs in any folder."
    , "    *.hs              matches any .hs file in any folder."
    , ""
    , "    ./*.hs            matches any .hs file in this folder and its subfolders."
    , "    ./Data.hs         matches the file Data.hs in this folder and its"
    , "                      subfolders."
    , ""
    , "    /home/foo/*.hs    matches any .hs file in the user's home folder and its"
    , "                      subfolders."
    , "    /home/foo/Data.hs matches the file Data.hs in the user's home folder and"
    , "                      its subfolders."
    ]



--                                                                        margin (87) |

-- | Help text describing all available command line options. Caution, this one
--   is about 250 lines long.
usageHelp :: String
usageHelp = "Usage:\n"
    ++ "  wsedit [<arguments>] <filename> [line-no. [column-no.]] [<arguments>]\n"
    ++ "  wsedit [<arguments>] -ocg [<arguments>]\n"
    ++ "  wsedit [<arguments>] -ocl [<arguments>]\n"
    ++ "\n\n"
    ++ renderText 80
    [ "For information on how to set these options permanently, see \"wsedit -hc\"."
    , ""
    , "Possible arguments (the uppercase options are on by default):"
    , ""
    , ""
    , ""
    , "-*- Autocomplete Dictionary Building Options (-a*) -*-"
    , ""
    , "  -ad <n> <f>     Add all files matching <f> to the dictionary at indentation"
    , "                  depth <n>, use * for <n> to disable the indentation filter."
    , ""
    , "                  The file filter follows the same pattern as that one used in"
    , "                  the config files minus the terminating colon, see"
    , "                  \"wsedit -hc\" for more information."
    , ""
    , "  -as <n>         Add the opened file at indentation depth <n> to the"
    , "                  dictionary, use * for <n> to disable the indentation filter."
    , ""
    , "  -A              Disable dictionary building."
    , ""
    , "                  With dictionary building enabled, wsedit will scan all files"
    , "                  and directories under the current working directory, except"
    , "                  hidden ones (file name starting with a period). Every"
    , "                  matching file will be read, and a dictionary will be built"
    , "                  from all words from lines at depth n (either n tabs or"
    , "                  n*tabWidth spaces). This dictionary will then be used to feed"
    , "                  the autocomplete function. The scan will take place everytime"
    , "                  you save or load."
    , "                  SETTING THIS IN THE GLOBAL CONFIG WILL MAKE YOUR EDITOR TAKE"
    , "                  AGES TO START UP, E.G. WHEN RUNNING FROM THE HOME DIRECTORY!"
    , ""
    , ""
    , ""
    , "-*- Display Options (-d*) -*-"
    , ""
    , "  -db             Fill the background with black dots. Relies on your"
    , "                  default background being similar, but distinct from colour 0"
    , "                  (usually black). Slows down the editor noticably and may make"
    , "                  the cursor invisible at the end of each line, depending on"
    , "                  how your terminal renders the cursor on black foreground and"
    , "                  default background."
    , ""
    , "  -dB             Draw a single blue dot terminating each line."
    , ""
    , ""
    , ""
    , ""
    , ""
    , "  -ds <s>         Draw a shitty badge that says <s> over the top right corner."
    , "  -dS             Disable the badge."
    , ""
    , ""
    , "  -dt <s>         Load a custom theme file from the file at <s>"
    , "  -dT             Disable custom theme"
    , ""
    , ""
    , "  -dx             Use colour 7 (white) for background drawing."
    , "  -dX             Use colour 0 (black) for background drawing."
    , ""
    , ""
    , ""
    , "-*- Editor Options (-e*) -*-"
    , ""
    , "  -ei <n>         Set indentation width to <n> (default = -i4)."
    , ""
    , ""
    , ""
    , "  -ej <n>         Initialize a jump mark at line <n>."
    , "  -eJ <n>         Remove the jump mark at line <n>."
    , ""
    , "                  See \"wsed -hk\" --> \"Ctrl-N\"."
    , ""
    , ""
    , ""
    , "  -el             Enable elastic tabstops."
    , "  -eL             Disable elastic tabstops."
    , ""
    , ""
    , ""
    , "  -ep             Preserve whitespace exactly on save."
    , "  -eP             Remove trailing whitespace and ensure the file ends with a"
    , "                  newline on save."
    , ""
    , ""
    , ""
    , "  -ets            Insert the appropriate amount of spaces instead of tabs."
    , "  -ett            Insert a tab character when pressing tab."
    , ""
    , "  -eT             Automagically detect the opened file's indentation pattern,"
    , "                  assume spaces for new files."
    , ""
    , "                  See also \"wsed -hk\" --> \"Ctrl-Meta-T\"."
    , ""
    , ""
    , ""
    , "-*- File Format Options (-f*) -*-"
    , ""
    , "  -fa             Disable atomic saves."
    , "  -fA             Enable atomic saves."
    , ""
    , "                  Atomic saves ensure that your file is always saved correctly"
    , "                  by first writing the new contents to a new file and then"
    , "                  renaming it over the old one after some additional checks."
    , "                  This process does not play nice with some file system types,"
    , "                  like the /proc and /sys virtual file systems as well as some"
    , "                  network mounts, but it is a recommended safety feature"
    , "                  wherever available."
    , ""
    , ""
    , ""
    , "  -fe <str>       Use <str> as file output encoding."
    , "  -fE             Use the locale's encoding setting."
    , ""
    , "  -fr <str>       Read the file using encoding <str>."
    , "  -fra            Read the file using an auto-detected encoding."
    , "  -fR             Read the file using the locale's default encoding."
    , ""
    , "                  Available encodings as well as their naming convention depend"
    , "                  on your OS. Haskell guarantees the following to be available:"
    , ""
    , "                     Name      Width  BOM?  Byte order"
    , "                   - UTF-8     1      no    n/a"
    , "                   - UTF-16    2      yes   unspecified"
    , "                   - UTF-16BE  2      no    big-endian"
    , "                   - UTF-16LE  2      no    little-endian"
    , "                   - UTF-32    4      yes   unspecified"
    , "                   - UTF-32BE  4      no    big-endian"
    , "                   - UTF-32LE  4      no    little-endian"
    , ""
    , "                  `-fr auto` has issues dealing with non-BOM multibyte UTF,"
    , "                  specify the encoding explicitly if you have trouble loading"
    , "                  the file correctly."
    , ""
    , ""
    , ""
    , "  -flu            Use UNIX line endings (LF) for output."
    , "  -flw            Use Windows line endings (CR + LF) for output."
    , "  -fL             Use the system's native line endings."
    , ""
    , ""
    , ""
    , "-*- General Options (-g*) -*-"
    , ""
    , "  -gh <s>         Search for <s> and highlight every occurence in bright red."
    , "  -gH <s>         Remove <s> from the search terms list."
    , ""
    , "                  See also \"wsed -hk\" --> \"Ctrl-F\"."
    , ""
    , ""
    , ""
    , "  -gr             Open file in read-only mode (default for files without write"
    , "                  permissions)."
    , "  -gR             Open file in read-write mode."
    , ""
    , "                  See also \"wsed -hk\" --> \"Ctrl-Meta-R\"."
    , ""
    , ""
    , ""
    , "-*- Help Options (-h*) -*-"
    , ""
    , "  -h              Show this help."
    , "  -hc             Show config help."
    , "  -hk             Show current keybinds."
    , ""
    , ""
    , ""
    , "  -hv              Displays the current version number."
    , ""
    , ""
    , ""
    , "-*- Language Options (-l*) -*-"
    , ""
    , "                  Pre-built language definitions are available in the \"lang/\""
    , "                  subdirectory of the source repository. If your distribution"
    , "                  does not ship them with wsedit, grab them from"
    , ""
    , "                      " ++ upstream
    , ""
    , "                  and put them into \"~/.config/wsedit/\". See \"wsedit -hc\" for"
    , "                  more information on persistent configuration."
    , ""
    , ""
    , ""
    , "  -lb <s1> <s2>   Enable bracket highlighting for <s1> ... <s2>."
    , "  -lB <s1> <s2>   Remove <s1> ... <s2> from the brackets list."
    , ""
    , ""
    , ""
    , "  -lcb <s1> <s2>  Add <s1>, <s2> as block comment delimiters."
    , "  -lcB <s1> <s2>  Remove <s1>, <s2> from the block comment delimiters list."
    , ""
    , ""
    , ""
    , "  -lcl <s>        Mark everything from <s> to the end of the line as a comment."
    , "  -lcL <s>        Remove <s> from the line comment delimiters list."
    , ""
    , ""
    , ""
    , "  -leo <s>        Add <s> as an escape modifier outside strings."
    , "  -leO <s>        Remove <s> from the list of escape modifiers."
    , ""
    , "  -les <s>        Add <s> as an escape modifier inside strings."
    , "  -leS <s>        Remove <s> from the list of escape modifiers."
    , ""
    , ""
    , ""
    , "  -li <c>         Add <c> to the list of characters allowed in identifiers."
    , "  -lI <c>         Remove <c> from the list of characters allowed in identifiers."
    , ""
    , ""
    , ""
    , "  -lk <s>         Mark <s> as a keyword."
    , "  -lK <s>         Remove <s> from the keywords list."
    , ""
    , "  -lkp <s>        Mark <s> as a keyword prefix."
    , "  -lkP <s>        Remove <s> from the keyword prefixes list."
    , ""
    , ""
    , ""
    , "  -lsc <s1> <s2>  Add <s1>, <s2> as character string delimiters."
    , "  -lsC <s1> <s2>  Remove <s1>, <s2> from the character string delimiters list."
    , ""
    , "                  Character strings contain exactly one character or an"
    , "                  escape plus exactly one character, all other occurences of"
    , "                  their delimiters are silently ignored."
    , ""
    , ""
    , ""
    , "  -lsm <s1> <s2>  Add <s1>, <s2> as multiline string delimiters."
    , "  -lsM <s1> <s2>  Remove <s1>, <s2> from the multiline string delimiters list."
    , ""
    , ""
    , ""
    , "  -lsr <s1> <s2>   Mark everything from <s1> to <s2> as a regular string."
    , "  -lsR <s1> <s2>   Remove <s1>, <s2> from the string delimiters list."
    , ""
    , ""
    , ""
    , "-*- Meta Options (-m*) -*-"
    , ""
    , "  -mf             Enables failsafe mode. When this option is present, invalid"
    , "                  switches will be ignored. Use this if the editor refuses to"
    , "                  start due to invalid config parameters."
    , ""
    , ""
    , ""
    , "  -ms             (Command line parameter only) Resume state from crash file"
    , "                  instead of opening it. If present, this must be the first"
    , "                  argument passed. There is no way to restore the keymap from"
    , "                  the dump, it will be replaced by the local default. Since"
    , "                  at this point, you'd have to make a custom build to change"
    , "                  your keymap, this should be *fine*."
    , ""
    , ""
    , ""
    , "  -mi <str>       Also include all options that would apply to file <str>."
    , ""
    , "                  E.g. \"-mi file.sh\" also activates all rules for"
    , "                  file.sh."
    , ""
    , ""
    , ""
    , "-*- Other Options (-o*) -*-"
    , ""
    , "  -ocg            Open global configuration file (~/.config/wsedit.wsconf)."
    , "  -ocl            Open local configuration file (./.local.wsconf)."
    , ""
    , "                  See \"wsed -hc\"."
    , ""
    , ""
    , ""
    , "  -op             Purge the clipboard file everytime the editor is closed."
    , "  -oP             Do not purge the clipboard file."
    , ""
    , "                  wsedit normally uses external facilities to provide copy/paste"
    , "                  functionality, but defaults to ~/.wsedit-clipboard if those"
    , "                  are unavailable. When left alone, this file may sit around"
    , "                  indefinitely, but you can tell wsedit to purge it everytime it"
    , "                  exits if you are concerned about your privacy."
    , ""
    , ""
    , ""
    , "-*- Development and Debugging Options (-y*) -*-"
    , ""
    , "  -yc             This will append-dump all active config options to the file"
    , "                  ${HOME}/wsedit-arg-dump on startup. Keep this in mind or it"
    , "                  might grow quite large over time."
    , ""
    , ""
    , ""
    , "  -ye             Enable event dumping."
    , "  -yE             Disable event dumping."
    , ""
    , "                  Event dumping will show every event in the status bar."
    , ""
    , ""
    , ""
    , "  -yi             Disable the write-read identity check."
    , "  -yI             Enable the write-read identity check."
    , ""
    , "                  This is a safety feature designed to protect your data from"
    , "                  corruption on save. Keeping it enabled at all times is highly"
    , "                  recommended."
    , ""
    , ""
    , ""
    , "  -ys <level>     Set accepted release stability. Every build has a stability"
    , "                  confidence rating, builds below \"Release\" will require your"
    , "                  explicit consent to start."
    , ""
    , "                      Release    Ready for production use (default setting)."
    , "                      RC         Feature-complete, but still missing some QA."
    , "                      WIP        Seems to work, but still incomplete / buggy."
    , "                      Prototype  It barely compiles, all bets are off."
    ]



--                                                                        margin (87) |

-- | Version and disclaimer help text.
versionHelp :: String
versionHelp = "Wyvernscale Source Code Editor (wsedit) Version " ++ version ++ " (" ++ show stability ++ ")\n\n"
    ++ "Licensed under the 3-Clause BSD License.\n\n"
    ++ "Upsteam URL: " ++ upstream ++ "\n\n"
    ++ renderText 80
    [ "This software is provided by the copyright holders and contributors \"as is\" and"
    , "any express or implied warranties, including, but not limited to, the implied"
    , "warranties of merchantability and fitness for a particular purpose are"
    , "disclaimed. In no event shall the copyright holder or contributors be liable for"
    , "any direct, indirect, incidental, special, exemplary, or consequential damages"
    , "(including, but not limited to, procurement of substitute goods or services;"
    , "loss of use, data, or profits; or business interruption) however caused and on"
    , "any theory of liability, whether in contract, strict liability, or tort"
    , "(including negligence or otherwise) arising in any way out of the use of this"
    , "software, even if advised of the possibility of such damage."
    ]
