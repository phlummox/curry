% -*- LaTeX -*-
% $Id: Goals.lhs 3044 2011-09-25 13:58:36Z wlux $
%
% Copyright (c) 1999-2011, Wolfgang Lux
% See LICENSE for the full license.
%
\nwfilename{Goals.lhs}
\section{Goals}\label{sec:goals}
This module controls the compilation of goals.
\begin{verbatim}

> module Goals(compileGoal,typeGoal) where
> import CaseCheck
> import Combined
> import Common
> import Curry
> import CurryParser
> import CurryUtils
> import Error
> import Interfaces
> import IO
> import KindCheck
> import List
> import Options
> import OverlapCheck
> import Position
> import PrecCheck
> import PrecInfo
> import PredefIdent
> import PredefTypes
> import Pretty
> import Qual
> import Renaming
> import ShadowCheck
> import SyntaxCheck
> import Types
> import TypeCheck
> import TypeInfo
> import TypeSyntaxCheck
> import TypeTrans
> import Typing
> import UnusedCheck
> import Utils
> import ValueInfo

\end{verbatim}
A goal is compiled with respect to the interfaces of the modules
specified on the command line. The Curry Prelude is implicitly added
to this set. The entities exported from these modules are in scope
with their qualified and unqualified names.
\begin{verbatim}

> data Task = EvalGoal | TypeGoal

> compileGoal :: Options -> Maybe String -> [FilePath] -> ErrorT IO ()
> compileGoal opts g fns =
>   do
>     (tcEnv,tyEnv,g') <- loadGoal EvalGoal paths dbg cm ws m g fns
>     let (vs,m',tyEnv') = goalModule dbg tyEnv m mainId g'
>     let (tcEnv',tyEnv'',trEnv,m'',dumps) = transModule dbg tr tcEnv tyEnv' m'
>     liftErr $ mapM_ (doDump opts) dumps
>     let (il,dumps) = ilTransModule dbg tcEnv' tyEnv'' trEnv (Just mainId) m''
>     liftErr $ mapM_ (doDump opts) dumps
>     let (ccode,dumps) = genCodeGoal tcEnv' (qualifyWith m mainId) vs il
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
>       loadGoal TypeGoal paths False cm ws (mkMIdent []) (Just g) fns
>     liftErr $ maybe putStr writeFile (output opts)
>             $ showLn (ppType tcEnv (typeOf e))
>   where paths = importPath opts
>         cm = caseMode opts
>         ws = warn opts

> loadGoal :: Task -> [FilePath] -> Bool -> CaseMode -> [Warn]
>          -> ModuleIdent -> Maybe String -> [FilePath]
>          -> ErrorT IO (TCEnv,ValueEnv,Goal Type)
> loadGoal task paths debug caseMode warn m g fns =
>   do
>     (mEnv,m',ds) <- loadGoalModules paths debug fns
>     g' <-
>       okM $ maybe (return (mainGoal m')) parseGoal g >>=
>             checkGoalSyntax mEnv ds
>     liftErr $ mapM_ putErrLn $ warnGoalSyntax caseMode warn mEnv ds m g'
>     (tcEnv,tyEnv,g'') <- okM $ checkGoal task mEnv m ds g'
>     liftErr $ mapM_ putErrLn $ warnGoal warn tyEnv g''
>     return (tcEnv,tyEnv,g'')
>   where mainGoal m = Goal (first "") (Variable () (qualifyWith m mainId)) []

> loadGoalModules :: [FilePath] -> Bool -> [FilePath]
>                 -> ErrorT IO (ModuleEnv,ModuleIdent,[ImportDecl])
> loadGoalModules paths debug fns =
>   do
>     (mEnv,ms') <- loadGoalInterfaces paths ms fns
>     let ms'' = preludeMIdent : ms'
>         ds' = [importDecl p m True [] | m <- ms'']
>         ds'' = [importDecl p m False xs | (m,xs) <- intfImports mEnv ms'']
>     return (mEnv,last ms'',ds' ++ ds'')
>   where p = first ""
>         ms = map (P p) (preludeMIdent : [debugPreludeMIdent | debug])
>         importDecl p m q xs = ImportDecl p m q Nothing (hideUnqual q xs)
>         hideUnqual True _ = Nothing
>         hideUnqual False xs = Just (Hiding p xs)

> checkGoalSyntax :: ModuleEnv -> [ImportDecl] -> Goal a -> Error (Goal a)
> checkGoalSyntax mEnv ds g =
>   typeSyntaxCheckGoal tEnv g >>= syntaxCheckGoal vEnv
>   where (tEnv,vEnv) = importModuleIdents mEnv ds

> checkGoal :: Task -> ModuleEnv -> ModuleIdent -> [ImportDecl] -> Goal a
>           -> Error (TCEnv,ValueEnv,Goal Type)
> checkGoal task mEnv m ds g =
>   do
>     g' <- precCheckGoal m pEnv (renameGoal g)
>     g'' <- kindCheckGoal tcEnv g' >> typeCheckGoal m tcEnv tyEnv g'
>     return (qualifyGoal task mEnv m pEnv tcEnv tyEnv g'')
>   where (pEnv,tcEnv,tyEnv) = importModules mEnv ds

> qualifyGoal :: Task -> ModuleEnv -> ModuleIdent -> PEnv -> TCEnv -> ValueEnv
>             -> Goal a -> (TCEnv,ValueEnv,Goal a)
> qualifyGoal EvalGoal mEnv m pEnv tcEnv tyEnv g = (tcEnv',tyEnv',qual tyEnv g)
>   where (_,tcEnv',tyEnv') = qualifyEnv mEnv m pEnv tcEnv tyEnv
> qualifyGoal TypeGoal _ _ _ tcEnv tyEnv g = (tcEnv,tyEnv,g)

> warnGoalSyntax :: CaseMode -> [Warn] -> ModuleEnv -> [ImportDecl]
>                -> ModuleIdent -> Goal a -> [String]
> warnGoalSyntax caseMode warn mEnv ds m g =
>   caseCheckGoal caseMode g ++ unusedCheckGoal warn m g ++
>   shadowCheckGoal warn mEnv ds g

> warnGoal :: [Warn] -> ValueEnv -> Goal a -> [String]
> warnGoal warn tyEnv g = overlapCheckGoal warn tyEnv g

\end{verbatim}
When compiling a goal the entities of all modules specified on the
command line are brought into scope with their qualified and
unqualified names. Entities exported from the main module, which by
convention is the last module specified on the command line, are
treated specially in that they shadow entities exported from other
modules. This is achieved by adding appropriate hiding specifications
to the implicit import declarations for all modules except the main
module in \texttt{intfImport}, which hide all names that will be
brought into scope by the main module.
\begin{verbatim}

> intfImports :: ModuleEnv -> [ModuleIdent] -> [(ModuleIdent,[Import])]
> intfImports mEnv ms = zip ms (replicate (length ms - 1) xs ++ [[]])
>   where xs = imports (moduleInterface (last ms) mEnv)
>         imports (Interface _ _ ds) = concatMap intfImport ds

> intfImport :: IDecl -> [Import]
> intfImport (IInfixDecl _ _ _ _) = []
> intfImport (HidingDataDecl _ _ _) = []
> intfImport (IDataDecl _ tc _ cs xs) =
>   [ImportTypeWith (unqualify tc)
>                   (filter (`notElem` xs) (nub (concatMap ents cs)))]
>   where ents (ConstrDecl _ _ c _) = [c]
>         ents (ConOpDecl _ _ _ op _) = [op]
>         ents (RecordDecl _ _ c fs) = c : [l | FieldDecl _ ls _ <- fs, l <- ls]
> intfImport (INewtypeDecl _ tc _ nc xs) =
>   [ImportTypeWith (unqualify tc) (filter (`notElem` xs) (ents nc))]
>   where ents (NewConstrDecl _ c _) = [c]
>         ents (NewRecordDecl _ c l _) = [c,l]
> intfImport (ITypeDecl _ tc _ _) = [ImportTypeWith (unqualify tc) []]
> intfImport (IFunctionDecl _ f _ _) = [Import (unqualify f)]

\end{verbatim}
When syntax and type checking succeed goals are compiled by converting
them into a module containing just a single function declaration.
Goals with type \texttt{IO \_} are executed directly by the runtime
system. All other goals are evaluated under control of an interactive
top-level, which displays the solutions of the goal and in particular
the bindings of its free variables. For this reason, the free
variables declared in the \texttt{where} clause of a goal are
translated into free variables of the goal. In addition, the goal is
transformed into a first order expression by performing a unification
with another variable. Thus, a goal
\begin{quote}
 \emph{expr}
 \texttt{where} $v_1$,\dots,$v_n$ \texttt{free}; \emph{decls}
\end{quote}
where no free variable declarations occur in \emph{decls} is
translated into the function
\begin{quote}
  \emph{f} $v_1$ \dots{} $v_n$ $v_{n+1}$ \texttt{=}
    $v_{n+1}$ \texttt{=:=} \emph{expr}
    \texttt{where} \emph{decls}
\end{quote}
where $v_{n+1}$ is a fresh variable. No variables are lifted at
present when generating code for the declarative debugger, since the
debugger evaluates the goal within an encapsulated search and we
cannot pass functions with arbitrary arity to the encapsulated search
primitive. In addition, the debugger currently lacks support for
showing the bindings of the goal's free variables.
\begin{verbatim}

> goalModule :: Bool -> ValueEnv -> ModuleIdent -> Ident -> Goal Type
>            -> (Maybe [Ident],Module Type,ValueEnv)
> goalModule debug tyEnv m g (Goal p e ds)
>   | isIO ty =
>       (Nothing,
>        mkModule m p ty g [] (mkLet ds e),
>        bindFun m g 0 (polyType ty) tyEnv)
>   | otherwise =
>       (if debug then Nothing else Just [v | FreeVar _ v <- vs],
>        mkModule m p ty' g vs' (apply (prelUnif ty) [mkVar ty v,e']),
>        bindFun m g n (polyType ty') tyEnv)
>   where ty = typeOf e
>         v = anonId
>         (vs,e') = liftGoalVars debug (mkLet ds e)
>         vs' = vs ++ [FreeVar ty v]
>         ty' = foldr TypeArrow successType [ty | FreeVar ty _ <- vs']
>         n = length vs'
>         isIO (TypeConstructor tc [_]) = tc == qIOId
>         isIO _ = False

> mkModule :: ModuleIdent -> Position -> a -> Ident -> [FreeVar a]
>          -> Expression a -> Module a
> mkModule m p ty g vs e = Module m (Just es) [] ds
>    where es = Exporting p [Export (qualifyWith m g)]
>          ds = [BlockDecl (funDecl p ty g (map varPattern vs) e)]
>          varPattern (FreeVar ty v) = VariablePattern ty v

> liftGoalVars :: Bool -> Expression a -> ([FreeVar a],Expression a)
> liftGoalVars debug (Let ds e)
>   | not debug = (concat [vs | FreeDecl _ vs <- vds],mkLet ds' e)
>   where (vds,ds') = partition isFreeDecl ds
> liftGoalVars _ e = ([],e)

> prelUnif :: Type -> Expression Type
> prelUnif ty =
>   Variable (foldr TypeArrow successType [ty,ty])
>            (qualifyWith preludeMIdent (mkIdent "=:="))

\end{verbatim}
Auxiliary functions. Unfortunately, hbc's \texttt{IO} module lacks a
definition of \texttt{hPutStrLn}.
\begin{verbatim}

> putErr :: String -> IO ()
> putErr = hPutStr stderr

> putErrLn :: String -> IO ()
> putErrLn s = putErr (unlines [s])

\end{verbatim}
