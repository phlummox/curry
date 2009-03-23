% -*- LaTeX -*-
% $Id: Modules.lhs 2764 2009-03-23 11:14:15Z wlux $
%
% Copyright (c) 1999-2009, Wolfgang Lux
% See LICENSE for the full license.
%
\nwfilename{Modules.lhs}
\section{Modules}
This module controls the compilation of modules.
\begin{verbatim}

> module Modules(compileModule,compileGoal,typeGoal) where
> import Unlit(unlit)
> import CurryParser(parseSource,parseInterface,parseGoal)
> import ImportSyntaxCheck(checkImports)
> import TypeSyntaxCheck(typeSyntaxCheck,typeSyntaxCheckGoal)
> import SyntaxCheck(syntaxCheck,syntaxCheckGoal)
> import ExportSyntaxCheck(checkExports)
> import Renaming(rename,renameGoal)
> import PrecCheck(precCheck,precCheckGoal)
> import KindCheck(kindCheck,kindCheckGoal)
> import TypeCheck(typeCheck,typeCheckGoal)
> import CaseCheck(caseCheck,caseCheckGoal)
> import UnusedCheck(unusedCheck,unusedCheckGoal)
> import ShadowCheck(shadowCheck,shadowCheckGoal)
> import OverlapCheck(overlapCheck,overlapCheckGoal)
> import IntfSyntaxCheck(intfSyntaxCheck)
> import IntfQual(qualIntf,unqualIntf)
> import IntfCheck(intfCheck)
> import IntfEquiv(fixInterface,intfEquiv)
> import Imports(importIdents,importInterface,importInterfaceIntf,
>                importUnifyData)
> import Exports(exportInterface)
> import Trust(trustEnv)
> import Qual(Qual(..))
> import Desugar(desugar,goalModule)
> import CaseMatch(caseMatch)
> import Simplify(simplify)
> import Unlambda(unlambda)
> import Lift(lift)
> import qualified IL
> import ILTrans(ilTrans)
> import ILLift(liftProg)
> import DTransform(dTransform,dAddMain)
> import ILCompile(camCompile,con,fun)
> import qualified Cam
> import qualified CamPP(ppModule)
> import CGen(genMain,genModule)
> import CCode(CFile,mergeCFile)
> import CPretty(ppCFile)
> import CurryPP(ppModule,ppInterface,ppIdent)
> import qualified ILPP(ppModule)
> import Options(Options(..),CaseMode(..),Warn(..),Dump(..))
> import Base
> import Curry
> import CurryUtils
> import Env
> import TopEnv
> import Combined
> import Error
> import IdentInfo
> import Interfaces
> import IO
> import List
> import Maybe
> import Monad
> import PathUtils
> import Position
> import PrecInfo
> import PredefIdent
> import Pretty
> import TrustInfo
> import Types
> import TypeInfo
> import TypeTrans
> import Typing
> import Utils
> import ValueInfo

\end{verbatim}
The function \texttt{compileModule} is the main entry point of this
module for compiling a Curry source module. It applies syntax and type
checking to the module and translates the code into one or more C code
files. The module's interface is updated when necessary.

The compiler automatically loads the Prelude when compiling a module
-- except for the Prelude itself -- by adding an appropriate import
declaration to the module.
\begin{verbatim}

> compileModule :: Options -> FilePath -> ErrorT IO ()
> compileModule opts fn =
>   do
>     (pEnv,tcEnv,tyEnv,m) <- loadModule paths dbg cm ws auto fn
>     let (tyEnv',trEnv,m',dumps) = transModule dbg tr tcEnv tyEnv m
>     liftErr $ mapM_ (doDump opts) dumps
>     let intf = exportInterface m pEnv tcEnv tyEnv'
>     liftErr $ unless (noInterface opts) (updateInterface fn intf)
>     let (il,dumps) = ilTransModule id dbg tyEnv' trEnv m'
>     liftErr $ mapM_ (doDump opts) dumps
>     let (ccode,dumps) = genCodeModule split tcEnv il
>     liftErr $ mapM_ (doDump opts) dumps >>
>               writeCode (output opts) fn ccode
>   where paths = importPath opts
>         split = splitCode opts
>         auto = autoSplit opts
>         dbg = debug opts
>         tr = if trusted opts then Trust else Suspect
>         cm = caseMode opts
>         ws = warn opts

> loadModule :: [FilePath] -> Bool -> CaseMode -> [Warn] -> Bool -> FilePath
>            -> ErrorT IO (PEnv,TCEnv,ValueEnv,Module Type)
> loadModule paths debug caseMode warn autoSplit fn =
>   do
>     Module m es is ds <- liftErr (readFile fn) >>= okM . parseModule fn
>     let is' = importPrelude debug fn m is
>     mEnv <- loadInterfaces paths emptyEnv m (modules is')
>     okM $ checkInterfaces mEnv
>     let mEnv' = sanitizeInterfaces m mEnv
>     m' <- okM $ checkModuleSyntax mEnv' (Module m es is' ds)
>     liftErr $ mapM_ putErrLn $ warnModuleSyntax caseMode warn m'
>     (pEnv,tcEnv,tyEnv,m'') <-
>       okM $ checkModule mEnv' (autoSplitModule autoSplit m')
>     liftErr $ mapM_ putErrLn $ warnModule warn tyEnv m''
>     return (pEnv,tcEnv,tyEnv,m'')
>   where modules is = [P p m | ImportDecl p m _ _ _ <- is]

> parseModule :: FilePath -> String -> Error (Module ())
> parseModule fn s = unlitLiterate fn s >>= parseSource fn

> checkModuleSyntax :: ModuleEnv -> Module a -> Error (Module a)
> checkModuleSyntax mEnv (Module m es is ds) =
>   do
>     is' <- importSyntaxCheck mEnv is
>     let (tEnv,vEnv) = importModuleIdents mEnv is'
>     (tEnv',ds') <- typeSyntaxCheck m tEnv ds
>     (vEnv',ds'') <- syntaxCheck m vEnv ds'
>     es' <- checkExports m is' tEnv' vEnv' es
>     return (Module m (Just es') is' ds'')

> checkModule :: ModuleEnv -> Module a
>             -> Error (PEnv,TCEnv,ValueEnv,Module Type)
> checkModule mEnv (Module m es is ds) =
>   do
>     let (pEnv,tcEnv,tyEnv) = importModules mEnv is
>     (pEnv',ds') <- precCheck m pEnv $ rename ds
>     tcEnv' <- kindCheck m tcEnv ds'
>     (tyEnv',ds'') <- typeCheck m tcEnv' tyEnv ds'
>     let (pEnv'',tcEnv'',tyEnv'') = qualifyEnv mEnv m pEnv' tcEnv' tyEnv'
>     return (pEnv'',tcEnv'',tyEnv'',Module m es is (qual tyEnv' ds''))

> warnModuleSyntax :: CaseMode -> [Warn] -> Module a -> [String]
> warnModuleSyntax caseMode warn m =
>   caseCheck caseMode m ++ unusedCheck warn m ++ shadowCheck warn m

> warnModule :: [Warn] -> ValueEnv -> Module a -> [String]
> warnModule warn tyEnv m = overlapCheck warn tyEnv m

> autoSplitModule :: Bool -> Module a -> Module a
> autoSplitModule True (Module m es is ds) =
>   Module m es is (foldr addSplitAnnot [] ds)
>   where addSplitAnnot d ds = SplitAnnot (pos d) : d : ds
> autoSplitModule False m = m

> transModule :: Bool -> Trust -> TCEnv -> ValueEnv -> Module Type
>             -> (ValueEnv,TrustEnv,Module Type,[(Dump,Doc)])
> transModule debug tr tcEnv tyEnv m = (tyEnv'''',trEnv,nolambda,dumps)
>   where trEnv = if debug then trustEnv tr m else emptyEnv
>         (desugared,tyEnv') = desugar tcEnv tyEnv m
>         (flatCase,tyEnv'') = caseMatch tcEnv tyEnv' desugared
>         (simplified,tyEnv''') = simplify tyEnv'' trEnv flatCase
>         (nolambda,tyEnv'''') = unlambda tyEnv''' simplified
>         dumps =
>           [(DumpRenamed,ppModule m),
>            (DumpTypes,ppTypes tcEnv (localBindings tyEnv)),
>            (DumpDesugared,ppModule desugared),
>            (DumpFlatCase,ppModule flatCase),
>            (DumpSimplified,ppModule simplified),
>            (DumpUnlambda,ppModule nolambda)]

> ilTransModule :: (IL.Module -> IL.Module) -> Bool -> ValueEnv -> TrustEnv
>               -> Module Type -> (IL.Module,[(Dump,Doc)])
> ilTransModule debugAddMain debug tyEnv trEnv m = (ilDbg,dumps)
>   where (lifted,tyEnv',trEnv') = lift tyEnv trEnv m
>         il = ilTrans tyEnv' lifted
>         ilDbg
>           | debug = debugAddMain (dTransform (trustedFun trEnv') il)
>           | otherwise = il
>         dumps =
>           [(DumpLifted,ppModule lifted),
>            (DumpIL,ILPP.ppModule il)] ++
>           [(DumpTransformed,ILPP.ppModule ilDbg) | debug]

> genCodeModule :: Bool -> TCEnv -> IL.Module
>               -> (Either CFile [CFile],[(Dump,Doc)])
> genCodeModule False tcEnv il = (Left ccode,dumps)
>   where (ccode,dumps) = genCode (dataTypes tcEnv) il
> genCodeModule True tcEnv il = (Right ccode,concat (transpose dumps))
>   where (ccode,dumps) =
>           unzip $ map (genCode (dataTypes tcEnv)) (splitModule il)

> genCode :: [(Cam.Name,[Cam.Name])] -> IL.Module -> (CFile,[(Dump,Doc)])
> genCode ts il = (ccode,dumps)
>   where ilNormal = liftProg il
>         cam = camCompile ilNormal
>         ccode = genModule ts cam
>         dumps =
>           [(DumpNormalized,ILPP.ppModule ilNormal),
>            (DumpCam,CamPP.ppModule cam)]

> qualifyEnv :: ModuleEnv -> ModuleIdent -> PEnv -> TCEnv -> ValueEnv
>            -> (PEnv,TCEnv,ValueEnv)
> qualifyEnv mEnv m pEnv tcEnv tyEnv =
>   (foldr (uncurry (globalBindTopEnv m)) pEnv' (localBindings pEnv),
>    foldr (uncurry (globalBindTopEnv m)) tcEnv' (localBindings tcEnv),
>    foldr (uncurry (bindTopEnv m)) tyEnv' (localBindings tyEnv))
>   where (ms,is) = unzip (envToList mEnv)
>         (pEnv',tcEnv',tyEnv') = foldl (importInterfaceIntf ms) initEnvs is

> splitModule :: IL.Module -> [IL.Module]
> splitModule (IL.Module m is ds) =
>   map (IL.Module m is)
>       (filter (any isCodeDecl) (wordsBy (IL.SplitAnnot ==) ds))
>   where isCodeDecl (IL.DataDecl _ _ cs) = not (null cs)
>         isCodeDecl (IL.TypeDecl _ _ _) = True
>         isCodeDecl (IL.FunctionDecl _ _ _ _) = True
>         isCodeDecl (IL.ForeignDecl _ _ _ _) = True

> trustedFun :: TrustEnv -> QualIdent -> Bool
> trustedFun trEnv f = maybe True (Trust ==) (lookupEnv (unqualify f) trEnv)

> dataTypes :: TCEnv -> [(Cam.Name,[Cam.Name])]
> dataTypes tcEnv = [dataType tc cs | DataType tc _ cs <- allEntities tcEnv]
>   where dataType tc cs = (con tc,map (con . qualifyLike tc) cs)

> writeCode :: Maybe FilePath -> FilePath -> Either CFile [CFile] -> IO ()
> writeCode tfn sfn (Left cfile) = writeCCode ofn cfile
>   where ofn = fromMaybe (rootname sfn ++ cExt) tfn
> writeCode tfn sfn (Right cfiles) = zipWithM_ (writeCCode . mkFn) [1..] cfiles
>   where prefix = fromMaybe (rootname sfn) tfn
>         mkFn i = prefix ++ show i ++ cExt

> writeGoalCode :: Maybe FilePath -> CFile -> IO ()
> writeGoalCode tfn = writeCCode ofn
>   where ofn = fromMaybe (internalError "No filename for startup code") tfn

> writeCCode :: FilePath -> CFile -> IO ()
> writeCCode fn = writeFile fn . showln . ppCFile

> showln :: Show a => a -> String
> showln x = shows x "\n"

\end{verbatim}
A goal is compiled with respect to the interface of a given module. If
no module is specified, the Curry Prelude is used. All entities
exported from the main module and the Prelude are in scope with their
unqualified names. In addition, the entities exported from all loaded
interfaces are in scope with their qualified names.
\begin{verbatim}

> data Task = Eval | Type

> compileGoal :: Options -> Maybe String -> [FilePath] -> ErrorT IO ()
> compileGoal opts g fns =
>   do
>     (tcEnv,tyEnv,g') <- loadGoal Eval paths dbg cm ws m g fns
>     let (vs,m',tyEnv') = goalModule dbg tyEnv m mainId g'
>     let (tyEnv'',trEnv,m'',dumps) = transModule dbg tr tcEnv tyEnv' m'
>     liftErr $ mapM_ (doDump opts) dumps
>     let (il,dumps) = ilTransModule (dAddMain mainId) dbg tyEnv'' trEnv m''
>     liftErr $ mapM_ (doDump opts) dumps
>     let (ccode,dumps) = genCodeGoal tcEnv (qualifyWith m mainId) vs il
>     liftErr $ mapM_ (doDump opts) dumps >>
>               writeGoalCode (output opts) ccode
>   where m = mkMIdent []
>         paths = importPath opts
>         dbg = debug opts
>         tr = if trusted opts then Trust else Suspect
>         cm = caseMode opts
>         ws = warn opts

> typeGoal :: Options -> String -> [FilePath] -> ErrorT IO ()
> typeGoal opts g fns =
>   do
>     (tcEnv,_,Goal _ e _) <-
>       loadGoal Type paths False cm ws (mkMIdent []) (Just g) fns
>     liftErr $ maybe putStr writeFile (output opts)
>             $ showln (ppType tcEnv (typeOf e))
>   where paths = importPath opts
>         cm = caseMode opts
>         ws = warn opts

> loadGoal :: Task -> [FilePath] -> Bool -> CaseMode -> [Warn]
>          -> ModuleIdent -> Maybe String -> [FilePath]
>          -> ErrorT IO (TCEnv,ValueEnv,Goal Type)
> loadGoal task paths debug caseMode warn m g fns =
>   do
>     (mEnv,m') <- loadGoalModules paths debug fns
>     let ms = nub [m',preludeMIdent]
>     g' <-
>       okM $ maybe (return (mainGoal m')) parseGoal g >>=
>             checkGoalSyntax mEnv ms
>     liftErr $ mapM_ putErrLn $ warnGoalSyntax caseMode warn m g'
>     (tcEnv,tyEnv,g'') <- okM $ checkGoal task mEnv m ms g'
>     liftErr $ mapM_ putErrLn $ warnGoal warn tyEnv m g''
>     return (tcEnv,tyEnv,g'')
>   where mainGoal m = Goal (first "") (Variable () (qualifyWith m mainId)) []

> loadGoalModules :: [FilePath] -> Bool -> [FilePath]
>                 -> ErrorT IO (ModuleEnv,ModuleIdent)
> loadGoalModules paths debug fns =
>   do
>     mEnv <- foldM (loadInterface paths) emptyEnv ms
>     (mEnv',ms') <- mapAccumM (loadGoalInterface paths) mEnv fns
>     okM $ checkInterfaces mEnv'
>     return (mEnv',last (preludeMIdent:ms'))
>   where ms = map (P (first "")) (preludeMIdent : [debugPreludeMIdent | debug])

> loadGoalInterface :: [FilePath] -> ModuleEnv -> FilePath
>                   -> ErrorT IO (ModuleEnv,ModuleIdent)
> loadGoalInterface paths mEnv fn
>   | extension fn `elem` [srcExt,litExt,intfExt] || pathSep `elem` fn =
>       do
>         (m,i) <- compileInterface (interfaceName fn)
>         return (bindModule i mEnv,m)
>   | otherwise =
>       do
>         mEnv' <- loadInterface paths mEnv (P (first "") m)
>         return (mEnv',m)
>   where m = mkMIdent (components ('.':fn))
>         components [] = []
>         components (_:cs) =
>           case break ('.' ==) cs of
>             (cs',cs'') -> cs' : components cs''

> checkGoalSyntax :: ModuleEnv -> [ModuleIdent] -> Goal a -> Error (Goal a)
> checkGoalSyntax mEnv ms g =
>   typeSyntaxCheckGoal tEnv g >>= syntaxCheckGoal vEnv
>   where (tEnv,vEnv) = importInterfaceIdents mEnv ms

> checkGoal :: Task -> ModuleEnv -> ModuleIdent -> [ModuleIdent] -> Goal a
>           -> Error (TCEnv,ValueEnv,Goal Type)
> checkGoal task mEnv m ms g =
>   do
>     g' <- precCheckGoal m pEnv (renameGoal g)
>     (tyEnv',g'') <- kindCheckGoal tcEnv g' >> typeCheckGoal m tcEnv tyEnv g'
>     return (qualifyGoal task mEnv m pEnv tcEnv tyEnv' g'')
>   where (pEnv,tcEnv,tyEnv) = importInterfaces mEnv ms

> qualifyGoal :: Task -> ModuleEnv -> ModuleIdent -> PEnv -> TCEnv -> ValueEnv
>             -> Goal a -> (TCEnv,ValueEnv,Goal a)
> qualifyGoal Eval mEnv m pEnv tcEnv tyEnv g = (tcEnv',tyEnv',qual tyEnv g)
>   where (_,tcEnv',tyEnv') = qualifyEnv mEnv m pEnv tcEnv tyEnv
> qualifyGoal Type _ _ _ tcEnv tyEnv g = (tcEnv,tyEnv,g)

> warnGoalSyntax :: CaseMode -> [Warn] -> ModuleIdent -> Goal a -> [String]
> warnGoalSyntax caseMode warn m g =
>   caseCheckGoal caseMode g ++ unusedCheckGoal warn m g ++
>   shadowCheckGoal warn g

> warnGoal :: [Warn] -> ValueEnv -> ModuleIdent -> Goal a -> [String]
> warnGoal warn tyEnv m g = overlapCheckGoal warn tyEnv g

> genCodeGoal :: TCEnv -> QualIdent -> Maybe [Ident] -> IL.Module
>             -> (CFile,[(Dump,Doc)])
> genCodeGoal tcEnv qGoalId vs il = (mergeCFile ccode ccode',dumps)
>   where (ccode,dumps) = genCode (dataTypes tcEnv) il
>         ccode' = genMain (fun qGoalId) (fmap (map name) vs)

\end{verbatim}
The functions \texttt{importModuleIdents} and \texttt{importModules}
bring the declarations of all imported modules into scope in the
current module.
\begin{verbatim}

> importSyntaxCheck :: ModuleEnv -> [ImportDecl] -> Error [ImportDecl]
> importSyntaxCheck mEnv ds = mapE checkImportDecl ds
>   where checkImportDecl (ImportDecl p m q asM is) =
>           liftE (ImportDecl p m q asM)
>                 (checkImports (moduleInterface m mEnv) is)

> importModuleIdents :: ModuleEnv -> [ImportDecl] -> (TypeEnv,FunEnv)
> importModuleIdents mEnv ds = (importUnifyData tEnv,importUnifyData vEnv)
>   where (tEnv,vEnv) = foldl importModule initIdentEnvs ds
>         importModule envs (ImportDecl _ m q asM is) =
>           importIdents (fromMaybe m asM) q is envs (moduleInterface m mEnv)

> importModules :: ModuleEnv -> [ImportDecl] -> (PEnv,TCEnv,ValueEnv)
> importModules mEnv ds = (pEnv,tcEnv,tyEnv)
>   where (pEnv,tcEnv,tyEnv) = foldl importModule initEnvs ds
>         importModule envs (ImportDecl _ m q asM is) =
>           importInterface (fromMaybe m asM) q is envs (moduleInterface m mEnv)

> moduleInterface :: ModuleIdent -> ModuleEnv -> Interface
> moduleInterface m mEnv =
>   fromMaybe (internalError "moduleInterface") (lookupEnv m mEnv)

> initIdentEnvs :: (TypeEnv,FunEnv)
> initIdentEnvs = (initTEnv,initVEnv)

> initEnvs :: (PEnv,TCEnv,ValueEnv)
> initEnvs = (initPEnv,initTCEnv,initDCEnv)

\end{verbatim}
The functions \texttt{importInterfaceIdents} and
\texttt{importInterfaces} bring the declarations of all loaded modules
into scope with their qualified names and in addition bring the
declarations of the specified modules into scope with their
unqualified names, too.
\begin{verbatim}

> importInterfaceIdents :: ModuleEnv -> [ModuleIdent] -> (TypeEnv,FunEnv)
> importInterfaceIdents mEnv ms = (importUnifyData tEnv,importUnifyData vEnv)
>   where (tEnv,vEnv) =
>           foldl (uncurry . importModule) initIdentEnvs (envToList mEnv)
>         importModule envs m = importIdents m (m `notElem` ms) Nothing envs

> importInterfaces :: ModuleEnv -> [ModuleIdent] -> (PEnv,TCEnv,ValueEnv)
> importInterfaces mEnv ms = (pEnv,tcEnv,tyEnv)
>   where (pEnv,tcEnv,tyEnv) =
>           foldl (uncurry . importModule) initEnvs (envToList mEnv)
>         importModule envs m = importInterface m (m `notElem` ms) Nothing envs

\end{verbatim}
When mutually recursive modules are compiled, it may be possible that
the imported interfaces include entities that are supposed to be
defined in the current module. These entities must not be imported
into the current module in any way because they might be in conflict
with the actual definitions in the current module.
\begin{verbatim}

> sanitizeInterfaces :: ModuleIdent -> ModuleEnv -> ModuleEnv
> sanitizeInterfaces m mEnv = fmap (sanitizeInterface m) (unbindModule m mEnv)

> sanitizeInterface :: ModuleIdent -> Interface -> Interface
> sanitizeInterface m (Interface m' is' ds') =
>   Interface m' is' (filter ((Just m /=) . fst . splitQualIdent . entity) ds')

\end{verbatim}
The Prelude is imported implicitly into every module other than the
Prelude. If the module does not import the Prelude explicitly, the
added declaration brings all Prelude entities with qualified and
unqualified names into scope. Otherwise, only the identifiers of the
unit, list, and tuple types are imported. Furthermore, the module
\texttt{DebugPrelude} is imported into every module when it is
compiled for debugging. However, none of its entities are brought into
scope because the debugging transformation is applied to the
intermediate language.
\begin{verbatim}

> importPrelude :: Bool -> FilePath -> ModuleIdent
>               -> [ImportDecl] -> [ImportDecl]
> importPrelude debug fn m is =
>   imp True preludeMIdent (preludeMIdent `notElem` ms) ++
>   imp debug debugPreludeMIdent False ++ is
>   where p = first fn
>         ms = [m | ImportDecl _ m _ _ _ <- is]
>         imp cond m' all = [importDecl p m' all | cond && m /= m']

> importDecl :: Position -> ModuleIdent -> Bool -> ImportDecl
> importDecl p m all =
>   ImportDecl p m False Nothing
>              (if all then Nothing else Just (Importing p []))

\end{verbatim}
The compiler loads the interfaces of all modules imported by the
compiled module or specified on the command line when compiling a
goal. Since interfaces are closed, it is not necessary to load the
interfaces of other modules whose entities are reexported by the
imported modules.
\begin{verbatim}

> loadInterfaces :: [FilePath] -> ModuleEnv -> ModuleIdent -> [P ModuleIdent]
>                -> ErrorT IO ModuleEnv
> loadInterfaces paths mEnv m ms =
>   do
>     okM $ sequenceE_ [errorAt p (cyclicImport m) | P p m' <- ms, m == m']
>     foldM (loadInterface paths) mEnv ms

> loadInterface :: [FilePath] -> ModuleEnv -> P ModuleIdent
>               -> ErrorT IO ModuleEnv
> loadInterface paths mEnv (P p m) =
>   case lookupEnv m mEnv of
>     Just _ -> return mEnv
>     Nothing ->
>       liftErr (lookupInterface paths m) >>=
>       maybe (errorAt p (interfaceNotFound m))
>             (compileModuleInterface mEnv m)

> compileModuleInterface :: ModuleEnv -> ModuleIdent -> FilePath
>                        -> ErrorT IO ModuleEnv
> compileModuleInterface mEnv m fn =
>   do
>     (m',i) <- compileInterface fn
>     unless (m == m') (errorAt (first fn) (wrongInterface m m'))
>     return (bindModule i mEnv)

\end{verbatim}
After parsing an interface, the compiler applies syntax checking to
the interface. This is possible because interface files are
self-contained.
\begin{verbatim}

> compileInterface :: FilePath -> ErrorT IO (ModuleIdent,Interface)
> compileInterface fn =
>   do
>     Interface m is ds <- liftErr (readFile fn) >>= okM . parseInterface fn
>     ds' <- okM $ intfSyntaxCheck ds
>     return (m,Interface m is (qualIntf m ds'))

\end{verbatim}
After all interface files have been loaded, the compiler checks that
reexported definitions in the interfaces are consistent and compatible
with their original definitions where the latter are available.
\begin{verbatim}

> checkInterfaces :: ModuleEnv -> Error ()
> checkInterfaces mEnv = mapE_ checkInterface is
>   where (ms,is) = unzip (envToList mEnv)
>         (pEnv,tcEnv,tyEnv) = foldl (importInterfaceIntf ms) initEnvs is
>         checkInterface (Interface m _ ds) = intfCheck m pEnv tcEnv tyEnv ds

\end{verbatim}
After checking a module successfully, the compiler may need to update
the module's interface file. The file will be updated only if the
interface has been changed or the file did not exist before.

The code below is a little bit tricky because we must make sure that the
interface file is closed before rewriting the interface -- even if it
has not been read completely. On the other hand, we must not apply
\texttt{hClose} too early. Note that there is no need to close the
interface explicitly if the interface check succeeds because the whole
file must have been read in this case. In addition, we do not update
the interface file in this case and therefore it doesn't matter when
the file is closed.
\begin{verbatim}

> updateInterface :: FilePath -> Interface -> IO ()
> updateInterface sfn i =
>   do
>     eq <- catch (matchInterface ifn i) (const (return False))
>     unless eq (writeInterface ifn i)
>   where ifn = interfaceName sfn

> matchInterface :: FilePath -> Interface -> IO Bool
> matchInterface ifn i =
>   do
>     h <- openFile ifn ReadMode
>     s <- hGetContents h
>     case parseInterface ifn s of
>       Ok i' | i `intfEquiv` fixInterface i' -> return True
>       _ -> hClose h >> return False

> writeInterface :: FilePath -> Interface -> IO ()
> writeInterface ifn = writeFile ifn . showln . ppInterface

> interfaceName :: FilePath -> FilePath
> interfaceName fn = rootname fn ++ intfExt

\end{verbatim}
The compiler searches for interface files in the import search path
using the extension \texttt{".icurry"}. Note that the current
directory is always searched first.
\begin{verbatim}

> lookupInterface :: [FilePath] -> ModuleIdent -> IO (Maybe FilePath)
> lookupInterface paths m = lookupFile (ifn : [catPath p ifn | p <- paths])
>   where ifn = foldr1 catPath (moduleQualifiers m) ++ intfExt

\end{verbatim}
Literate source files use the extension \texttt{".lcurry"}.
\begin{verbatim}

> unlitLiterate :: FilePath -> String -> Error String
> unlitLiterate fn s
>   | not (isLiterateSource fn) = return s
>   | null es = return s'
>   | otherwise = fail es
>   where (es,s') = unlit fn s

> isLiterateSource :: FilePath -> Bool
> isLiterateSource fn = litExt `isSuffixOf` fn

\end{verbatim}
The \texttt{doDump} function writes the selected information to the
standard output.
\begin{verbatim}

> doDump :: Options -> (Dump,Doc) -> IO ()
> doDump opts (d,x) =
>   when (d `elem` dump opts)
>        (print (text hd $$ text (replicate (length hd) '=') $$ x))
>   where hd = dumpHeader d

> dumpHeader :: Dump -> String
> dumpHeader DumpRenamed = "Module after renaming"
> dumpHeader DumpTypes = "Types"
> dumpHeader DumpDesugared = "Source code after desugaring"
> dumpHeader DumpFlatCase = "Source code after case flattening"
> dumpHeader DumpSimplified = "Source code after simplification"
> dumpHeader DumpUnlambda = "Source code after naming lambdas"
> dumpHeader DumpLifted = "Source code after lifting"
> dumpHeader DumpIL = "Intermediate code"
> dumpHeader DumpTransformed = "Transformed code" 
> dumpHeader DumpNormalized = "Intermediate code after normalization"
> dumpHeader DumpCam = "Abstract machine code"

\end{verbatim}
The function \texttt{ppTypes} is used for pretty-printing the types
from the type environment.
\begin{verbatim}

> ppTypes :: TCEnv -> [(Ident,ValueInfo)] -> Doc
> ppTypes tcEnv = vcat . map ppInfo
>   where ppInfo (c,DataConstructor _ _ ty) =
>           ppType c ty <+> text "-- data constructor"
>         ppInfo (c,NewtypeConstructor _ _ ty) =
>           ppType c ty <+> text "-- newtype constructor"
>         ppInfo (x,Value _ _ ty) = ppType x ty
>         ppType f ty = ppIdent f <+> text "::" <+> ppTypeScheme tcEnv ty

\end{verbatim}
Various file name extensions.
\begin{verbatim}

> cExt = ".c"
> srcExt = ".curry"
> litExt = ".lcurry"
> intfExt = ".icurry"

\end{verbatim}
Auxiliary functions. Unfortunately, hbc's \texttt{IO} module lacks a
definition of \texttt{hPutStrLn}.
\begin{verbatim}

> putErr :: String -> IO ()
> putErr = hPutStr stderr

> putErrLn :: String -> IO ()
> putErrLn s = putErr (unlines [s])

\end{verbatim}
Error messages.
\begin{verbatim}

> interfaceNotFound :: ModuleIdent -> String
> interfaceNotFound m = "Interface for module " ++ moduleName m ++ " not found"

> cyclicImport :: ModuleIdent -> String
> cyclicImport m = "Module " ++ moduleName m ++ " imports itself"

> wrongInterface :: ModuleIdent -> ModuleIdent -> String
> wrongInterface m m' =
>   "Expected interface for " ++ show m ++ " but found " ++ show m'

\end{verbatim}
