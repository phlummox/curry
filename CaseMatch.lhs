% -*- LaTeX -*-
% $Id: CaseMatch.lhs 3206 2016-06-07 07:17:22Z wlux $
%
% Copyright (c) 2001-2016, Wolfgang Lux
% See LICENSE for the full license.
%
\nwfilename{CaseMatch.lhs}
\section{Flattening Patterns}\label{sec:flatcase}
After desugaring source code, the compiler makes pattern matching in
equations, lambda abstractions, and $($f$)$case expressions fully
explicit by restricting pattern matching to $($f$)$case expressions
with only flat patterns. This means that the compiler transforms the
code in such way that all functions have only a single equation,
equations and lambda abstractions have only variable arguments, and
all patterns in $($f$)$case expressions are of the form $l$, $v$,
$C\,v_1\dots v_n$, or $v\texttt{@}(C\,v_1\dots v_n)$ where $l$ is a
literal, $v$ and $v_1, \dots, v_n$ are variables, and $C$ is a data
constructor.\footnote{Recall that all newtype constructors have been
  removed previously.} During this transformation, the compiler also
replaces guards by if-then-else cascades, changes if-then-else
expressions into equivalent case expressions, and transforms function
patterns into equivalent right hand side constraints.
\begin{verbatim}

> module CaseMatch(caseMatch) where
> import Base
> import Combined
> import Curry
> import CurryUtils
> import List
> import Maybe
> import Monad
> import PredefIdent
> import PredefTypes
> import Types
> import TypeInfo
> import Typing
> import Utils
> import ValueInfo

\end{verbatim}
The case flattening phase is applied recursively to all declarations
and expressions of the desugared source code. Recall that pattern
declarations have been transformed already into normalized form, where
the left hand side is either a variable or a tuple pattern, and hence
only the right hand sides of such declarations need to be transformed.
\begin{verbatim}

> type CaseMatchState a = ReaderT TCEnv (StateT Int Id) a

> caseMatch :: TCEnv -> Module Type -> Module Type
> caseMatch tcEnv (Module m es is ds) =
>   Module m es is (runSt (callRt (mapM (match m noPos) ds) tcEnv) 1)
>   where noPos = internalError "caseMatch: no position"

> class CaseMatch a where
>   match :: ModuleIdent -> Position -> a Type -> CaseMatchState (a Type)

> instance CaseMatch TopDecl where
>   match _ _ (DataDecl p tc tvs cs) = return (DataDecl p tc tvs cs)
>   match _ _ (NewtypeDecl p tc tvs nc) = return (NewtypeDecl p tc tvs nc)
>   match _ _ (TypeDecl p tc tvs ty) = return (TypeDecl p tc tvs ty)
>   match m p (BlockDecl d) = liftM BlockDecl (match m p d)

> instance CaseMatch Decl where
>   match m _ (FunctionDecl p ty f eqs) =
>     do
>       (vs,e) <-
>         matchFlex m p [(p,ts,rhs) | Equation p (FunLhs _ ts) rhs <- eqs]
>       return (funDecl p ty f (map (uncurry VariablePattern) vs) e)
>   match _ _ (ForeignDecl p fi ty f ty') = return (ForeignDecl p fi ty f ty')
>   match m _ (PatternDecl p t rhs) = liftM (PatternDecl p t) (match m p rhs)
>   match _ _ (FreeDecl p vs) = return (FreeDecl p vs)

\end{verbatim}
A list of guarded equations or alternatives is expanded into the
equivalent of a nested if-then-else expression.
\begin{verbatim}

> instance CaseMatch Rhs where
>   match m p rhs = liftM (mkRhs p) (matchRhs m p rhs Nothing)

> matchRhs :: ModuleIdent -> Position -> Rhs Type
>          -> Maybe (CaseMatchState (Expression Type))
>          -> CaseMatchState (Expression Type)
> matchRhs m _ (SimpleRhs p e ds) _ = match m p (mkLet ds e)
> matchRhs m p (GuardedRhs es ds) e0 =
>   liftM2 mkLet (mapM (match m p) ds) (expandRhs m p es e0)

> expandRhs :: ModuleIdent -> Position -> [CondExpr Type]
>           -> Maybe (CaseMatchState (Expression Type))
>           -> CaseMatchState (Expression Type)
> expandRhs m p es e0 = liftM2 expandGuards (mapM (match m p) es) (liftMaybe e0)
>   where liftMaybe (Just e0) = liftM Just e0
>         liftMaybe Nothing = return Nothing

> expandGuards :: [CondExpr Type] -> Maybe (Expression Type) -> Expression Type
> expandGuards [] (Just e0) = e0
> expandGuards (CondExpr p g e1:es) e0 =
>   Case g (caseAlt p truePattern e1 :
>           map (caseAlt p falsePattern) (expand es e0))
>   where expand es e0
>           | null es = maybeToList e0
>           | otherwise = [expandGuards es e0]

> instance CaseMatch CondExpr where
>   match m _ (CondExpr p g e) = liftM2 (CondExpr p) (match m p g) (match m p e)

> instance CaseMatch Expression where
>   match _ _ (Literal ty l) = return (Literal ty l)
>   match _ _ (Variable ty v) = return (Variable ty v)
>   match _ _ (Constructor ty c) = return (Constructor ty c)
>   match _ _ (Tuple vs) = return (Tuple vs)
>   match m p (Apply e1 e2) = liftM2 Apply (match m p e1) (match m p e2)
>   match m _ (Lambda p ts e) =
>     do
>       (vs,e') <- matchFlex m p [(p,ts,mkRhs p e)]
>       return (Lambda p (map (uncurry VariablePattern) vs) e')
>   match m p (Let ds e) = liftM2 Let (mapM (match m p) ds) (match m p e)
>   match m p (Case e as) =
>     do
>       e' <- match m p e
>       ([v],e'') <- matchRigid m [(p,[t],rhs) | Alt p t rhs <- as]
>       return (mkCase m p v e' e'')
>   match m p (Fcase e as) =
>     do
>       e' <- match m p e
>       ([v],e'') <- matchFlex m p [(p,[t],rhs) | Alt p t rhs <- as]
>       return (mkCase m p v e' e'')

\end{verbatim}
Before flattening case patterns, the compiler eliminates all function
patterns. In a first step, we transform every pattern $t$ that
contains one or more function patterns into a pattern $t'$ containing
no function patterns and a list of pairs of the form $(x_i,t_i)$,
where $t_i$ is an outermost function pattern in $t$ and $x_i$ is the
variable that replaces $t_i$ in $t'$. In a second step the pairs
$(x_i,t_i)$ are converted into constraints of the form \texttt{$t_i$
  =:<= $x_i$} that are injected into the right hand side of their
respective function equation or $($f$)$case alternative together with
declarations that define the variables occurring in $t_i$. Note that
each of those variables is bound to \texttt{Prelude.unknown} instead
of using a free variable declaration. This is necessary because the
compiler attempts to avoid redundant evaluation of expressions which
are known to be in head normal form already. These include literals
and data constructor applications, but also logical variables, which
-- apart from on the left hand side of \texttt{(=:<=)} -- can only be
bound to a (head) normal form.

\ToDo{Use a primitive function instead of \texttt{Prelude.unknown}
  once the simplifier starts performing inline expansion of (imported)
  functions.}
\begin{verbatim}

> type Match a = (Position,[ConstrTerm a],Rhs a)
> type Match' a =
>   (Position,[ConstrTerm a] -> [ConstrTerm a],[ConstrTerm a],Rhs a)

> matchFlex :: ModuleIdent -> Position -> [Match Type]
>           -> CaseMatchState ([(Type,Ident)],Expression Type)
> matchFlex m p as =
>   do
>     as' <- mapM elimFP as
>     vs <- matchVars (map snd3 as')
>     e <- flexMatch m p vs as'
>     return (vs,e)
>   where elimFP (p,ts,rhs) =
>           do
>             (ts',fpss) <- mapAndUnzipM liftFP ts
>             return (p,ts',inject p unify (concat fpss) rhs)

> matchRigid :: ModuleIdent -> [Match Type]
>            -> CaseMatchState ([(Type,Ident)],Expression Type)
> matchRigid m as =
>   do
>     as' <- mapM elimFP as
>     vs <- matchVars [ts | (_,_,ts,_) <- as']
>     e <- rigidMatch m id vs as'
>     return (vs,e)
>   where elimFP (p,ts,rhs) =
>           do
>             (ts',fpss) <- mapAndUnzipM liftFP ts
>             return (p,id,ts',inject p unifyRigid (concat fpss) rhs)

\end{verbatim}
When the additional constraints are injected into a guarded equation
or alternative, the additional constraints are inserted into the first
guard such that they are evaluated before the existing guard is
checked. Effectively, a guarded right hand side of the form
\texttt{|} $g_1\;\texttt{=}\;e_1$ $\dots$ \texttt{|}
$g_n\;\texttt{=}\;e_n$ is transformed into the equivalent of
\begin{quote}
  \texttt{|} $c\:\texttt{\&>}\:g_1\;\texttt{=}\;e_1$ $\dots$
  \texttt{|} $g_n\;\texttt{=}\;e_n$
\end{quote}
where $c$ are the additional function pattern constraints. In
particular, this transformation ensures that for a case alternative
with boolean guards the remaining alternatives of the case expression
are tested if all guards reduce to \verb|False|. E.g.,
\begin{verbatim}
  case [-1] of
    xs ++ [x] | x > 0 -> x
    _ -> 0
\end{verbatim}
reduces to 0.
\begin{verbatim}

> liftFP :: ConstrTerm Type
>        -> CaseMatchState (ConstrTerm Type,[((Type,Ident),ConstrTerm Type)])
> liftFP t@(LiteralPattern _ _) = return (t,[])
> liftFP t@(VariablePattern _ _) = return (t,[])
> liftFP (ConstructorPattern ty c ts) =
>   do
>     (ts',fpss) <- mapAndUnzipM liftFP ts
>     return (ConstructorPattern ty c ts',concat fpss)
> liftFP t@(FunctionPattern ty _ _) =
>   do
>     v <- freshVar "_#fpat" ty
>     return (uncurry VariablePattern v,[(v,t)])
> liftFP (AsPattern v t) =
>   do
>     (t',fps) <- liftFP t
>     return (AsPattern v t',fps)

> inject :: Position -> (Type -> Expression Type)
>        -> [((Type,Ident),ConstrTerm Type)] -> Rhs Type -> Rhs Type
> inject p unify fps
>   | null fps = id
>   | otherwise = injectRhs (foldr1 (Apply . Apply prelConj) cs) ds
>   where cs = [apply (unify ty) [toExpr t,mkVar ty v] | ((ty,v),t) <- fps]
>         ds = concatMap (decls p . snd) fps

> injectRhs :: Expression Type -> [Decl Type] -> Rhs Type -> Rhs Type
> injectRhs c ds (SimpleRhs p e ds') =
>   GuardedRhs [CondExpr p c e] (ds ++ ds')
> injectRhs c ds (GuardedRhs (CondExpr p g e : es) ds') =
>   GuardedRhs (CondExpr p g' e : es) (ds ++ ds')
>   where g' = expandGuards [CondExpr p c g] Nothing

> toExpr :: ConstrTerm Type -> Expression Type
> toExpr (LiteralPattern ty l) = Literal ty l
> toExpr (VariablePattern ty v) = mkVar ty v
> toExpr (ConstructorPattern ty c ts) =
>   apply (Constructor (foldr (TypeArrow . typeOf) ty ts) c) (map toExpr ts)
> toExpr (FunctionPattern ty f ts) =
>   apply (Variable (foldr (TypeArrow . typeOf) ty ts) f) (map toExpr ts)
> toExpr (AsPattern v t) = mkVar (typeOf t) v

> decls :: Position -> ConstrTerm Type -> [Decl Type]
> decls _ (LiteralPattern _ _) = []
> decls p (VariablePattern ty v) = [varDecl p ty v (prelUnknown ty)]
> decls p (ConstructorPattern _ _ ts) = concatMap (decls p) ts
> decls p (FunctionPattern _ _ ts) = concatMap (decls p) ts
> decls p (AsPattern v t) = varDecl p (typeOf t) v (toExpr t) : decls p t

\end{verbatim}
Our pattern matching algorithm is based on the notions of demanded and
inductive positions defined in Sect.~D.5 of the Curry
report~\cite{Hanus:Report}. Given a list of terms, a demanded position
is a position where a constructor rooted term occurs in at least one
of the terms. An inductive position is a position where a constructor
rooted term occurs in each of the terms. Obviously, every inductive
position is also a demanded position. For the purpose of pattern
matching we treat literal terms as constructor rooted terms.

The algorithm looks for the leftmost outermost inductive argument
position in the left hand sides of all rules defining an equation. If
such a position is found, a fcase expression is generated for the
argument at that position. The matching algorithm is then applied
recursively to each of the alternatives at that position. If no
inductive position is found, the algorithm looks for the leftmost
outermost demanded argument position. If such a position is found, a
choice expression with two alternatives is generated, one for rules
with a variable at the demanded position, and one for the rules with a
constructor rooted term at that position. If there is no demanded
position either, pattern matching is complete and the compiler
translates the right hand sides of the remaining rules, eventually
combining them into a non-deterministic choice.

In fact, the algorithm combines the search for inductive and demanded
positions. The function \texttt{flexMatch} scans the argument lists for
the leftmost demanded position. If this turns out to be also an
inductive position, the function \texttt{matchInductive} is called in
order to generate a \texttt{fcase} expression. Otherwise, the function
\texttt{optMatch} is called that looks for an inductive position among
the remaining arguments. If one is found, \texttt{matchInductive} is
called for that position, otherwise the function \texttt{optMatch}
uses the demanded argument position found by \texttt{flexMatch}.

Since our Curry representation does not include non-deterministic
choice expressions, we encode them as flexible case expressions
matching an auxiliary free variable~\cite{AntoyHanus06:Overlapping}.
For instance, an expression equivalent to $e_1$~\texttt{?}~$e_2$ is
represented as
\begin{quote}\tt
  fcase (let x free in x) of \lb{} 1 -> $e_1$; 2 -> $e_2$ \rb{}
\end{quote}

Note that the function \texttt{matchVars} attempts to avoid
introducing fresh variables for variable patterns already present in
the source code when there is only a single alternative in order to
make the result of the transformation easier to check and more
comprehensible.
\begin{verbatim}

> pattern :: ConstrTerm a -> ConstrTerm ()
> pattern (LiteralPattern _ l) = LiteralPattern () l
> pattern (VariablePattern _ _) = VariablePattern () anonId
> pattern (ConstructorPattern _ c ts) =
>   ConstructorPattern () c (map (const (VariablePattern () anonId)) ts)
> pattern (AsPattern _ t) = pattern t

> arguments :: ConstrTerm a -> [ConstrTerm a]
> arguments (LiteralPattern _ _) = []
> arguments (VariablePattern _ _) = []
> arguments (ConstructorPattern _ _ ts) = ts
> arguments (AsPattern _ t) = arguments t

> bindVars :: Position -> Ident -> ConstrTerm Type -> Rhs Type -> Rhs Type
> bindVars _ _ (LiteralPattern _ _) = id
> bindVars p v' (VariablePattern ty v) = bindVar p ty v v'
> bindVars _ _ (ConstructorPattern _ _ _) = id
> bindVars p v' (AsPattern v t) = bindVar p (typeOf t) v v' . bindVars p v' t

> bindVar :: Position -> a -> Ident -> Ident -> Rhs a -> Rhs a
> bindVar p ty v v'
>   | v /= v' = addDecl (varDecl p ty v (mkVar ty v'))
>   | otherwise = id

> flexMatch :: ModuleIdent -> Position -> [(Type,Ident)] -> [Match Type]
>           -> CaseMatchState (Expression Type)
> flexMatch m p []     as = mapM (match m p . thd3) as >>= matchChoice p
> flexMatch m p (v:vs) as
>   | null vars = e1
>   | null nonVars = e2
>   | otherwise =
>       optMatch m (join (liftM2 (matchOr p) e1 e2)) (v:) vs (map shiftArg as)
>   where (vars,nonVars) = partition (isVarPattern . fst) (map tagAlt as)
>         e1 = matchInductive m id v vs nonVars
>         e2 = flexMatch m p vs (map (matchVar (snd v) . snd) vars)
>         tagAlt (p,t:ts,rhs) = (pattern t,(p,id,t:ts,rhs))
>         shiftArg (p,t:ts,rhs) = (p,(t:),ts,rhs)
>         matchVar v (p,_,t:ts,rhs) = (p,ts,bindVars p v t rhs)

> optMatch :: ModuleIdent -> CaseMatchState (Expression Type)
>          -> ([(Type,Ident)] -> [(Type,Ident)]) -> [(Type,Ident)]
>          -> [Match' Type] -> CaseMatchState (Expression Type)
> optMatch _ e _      []     _ = e
> optMatch m e prefix (v:vs) as
>   | null vars = matchInductive m prefix v vs nonVars
>   | null nonVars = optMatch m e prefix vs (map (matchVar (snd v)) as)
>   | otherwise = optMatch m e (prefix . (v:)) vs (map shiftArg as)
>   where (vars,nonVars) = partition (isVarPattern . fst) (map tagAlt as)
>         tagAlt (p,prefix,t:ts,rhs) = (pattern t,(p,prefix,t:ts,rhs))
>         shiftArg (p,prefix,t:ts,rhs) = (p,prefix . (t:),ts,rhs)
>         matchVar v (p,prefix,t:ts,rhs) = (p,prefix,ts,bindVars p v t rhs)

> matchInductive :: ModuleIdent -> ([(Type,Ident)] -> [(Type,Ident)])
>                -> (Type,Ident) -> [(Type,Ident)]
>                -> [(ConstrTerm (),Match' Type)]
>                -> CaseMatchState (Expression Type)
> matchInductive m prefix v vs as =
>   liftM (Fcase (uncurry mkVar v)) (matchAlts m prefix v vs as)

> matchChoice :: Position -> [Rhs Type] -> CaseMatchState (Expression Type)
> matchChoice p (rhs:rhss)
>   | null rhss = return (expr rhs)
>   | otherwise =
>       do
>         v <- freshVar "_#choice" (typeOf (head ts))
>         return (Fcase (freeVar p v) (zipWith (Alt p) ts (rhs:rhss)))
>   where ts = map (LiteralPattern intType . Int) [0..]
>         freeVar p (ty,v) = Let [FreeDecl p [FreeVar ty v]] (mkVar ty v)
>         expr (SimpleRhs _ e _) = e

> matchOr :: Position -> Expression Type -> Expression Type
>         -> CaseMatchState (Expression Type)
> matchOr p e1 e2 = matchChoice p [mkRhs p e1,mkRhs p e2]

> matchAlts :: ModuleIdent -> ([(Type,Ident)] -> [(Type,Ident)]) -> (Type,Ident)
>           -> [(Type,Ident)] -> [(ConstrTerm (),Match' Type)]
>           -> CaseMatchState [Alt Type]
> matchAlts _ _      _ _  [] = return []
> matchAlts m prefix v vs ((t,a):as) =
>   do
>     a' <- matchAlt m prefix v vs (a : map snd same) 
>     as' <- matchAlts m prefix v vs others
>     return (a' : as')
>   where (same,others) = partition ((t ==) . fst) as

> matchAlt :: ModuleIdent -> ([(Type,Ident)] -> [(Type,Ident)]) -> (Type,Ident)
>          -> [(Type,Ident)] -> [Match' Type] -> CaseMatchState (Alt Type)
> matchAlt m prefix v vs as@((p,_,t:_,_) : _) =
>   do
>     vs' <- matchVars [arguments t | (_,_,t:_,_) <- as]
>     e' <- flexMatch m p (prefix (vs' ++ vs)) (map expandArg as)
>     return (caseAlt p (renameArgs (snd v) vs' t) e')
>   where expandArg (p,prefix,t:ts,rhs) =
>           (p,prefix (arguments t ++ ts),bindVars p (snd v) t rhs)

> matchVars :: [[ConstrTerm Type]] -> CaseMatchState [(Type,Ident)]
> matchVars tss = mapM argName (transpose tss)
>   where argName [VariablePattern ty v] = return (ty,v)
>         argName [AsPattern v t] = return (typeOf t,v)
>         argName (t:_) = freshVar "_#case" (typeOf t)

> renameArgs :: Ident -> [(a,Ident)] -> ConstrTerm a -> ConstrTerm a
> renameArgs v _ (LiteralPattern ty l) = AsPattern v (LiteralPattern ty l)
> renameArgs v _ (VariablePattern ty _) = VariablePattern ty v
> renameArgs v vs (ConstructorPattern ty c _) =
>   AsPattern v (ConstructorPattern ty c (map (uncurry VariablePattern) vs))
> renameArgs v vs (AsPattern _ t) = renameArgs v vs t

\end{verbatim}
The algorithm used for rigid case expressions is a variant of the
algorithm used above for transforming pattern matching of function
heads and flexible case expressions. In contrast to the algorithm
presented in Sect.~5 of~\cite{PeytonJones87:Book}, the code generated
by our algorithm will not perform redundant matches. Furthermore, we
do not need a special pattern match failure primitive and fatbar
expressions in order to catch such failures. On the other hand, our
algorithm can cause code duplication. We do not care about that
because most pattern matching in Curry programs occurs in function
heads and not in case expressions.

The essential difference between pattern matching in rigid case
expressions on one hand and function heads and flexible fcase
expressions on the other hand is that in case expressions,
alternatives are matched from top to bottom and patterns are matched
from left to right in each alternative. Evaluation commits to the
first alternative with a matching pattern. If an alternative uses
guards and all guards of that alternative fail, pattern matching
continues with the next alternative as if the pattern did not match.

Our algorithm scans the arguments of the first alternative from left
to right until finding a literal or a constructor application. If such
a position is found, the alternatives are partitioned into groups such
that all alternatives in one group have a term with the same root or a
variable pattern at the selected position and the groups are defined
by mutually distinct roots. If no such position is found, the first
alternative is selected and the remaining alternatives are used in
order to define a default (case) expression when the selected
alternative is defined with a list of guarded expressions.

Including alternatives with a variable pattern at the selected
position causes the aforementioned code duplication. The variable
patterns themselves are replaced by fresh instances of the pattern
defining the respective group. Note that the algorithm carefully
preserves the order of alternatives, which means that the first
alternatives of a group matching a literal or constructor rooted term
may have a variable pattern at the selected position.

In addition to the matching alternatives, the compiler must also
include non-matching alternatives with a non-variable pattern left of
the selected position in each group. This is necessary to obey the
top-down, left to right matching semantics for case expressions. For
instance, in the following, contrived case expression\footnote{This
  example is derived from similar code in
  \cite{KarachaliasSchrijversVytiniotisPeytonJones2015:GADTs}.}
\begin{verbatim}
  case (x,y) of
    (_,False) -> 1
    (True,False) -> 2
    (_,True) -> 3
\end{verbatim}
the second alternative must be included in the alternatives for
\verb|y| matching \verb|True| because according to the semantics, when
the first alternative does not match (\verb|y| reduces to \verb|True|
rather than \verb|False|) the second alternative is tried next and
this first evaluates \verb|x| to a ground term. When we include a
non-matching alternative in a group, we must replace all arguments to
the right of the selected position by variable patterns to prevent
further evaluation after the non-matching pattern and change the right
hand side into an expression that always fails. We use a guarded right
hand side with no alternatives for this purpose here.

The algorithm also removes redundant default alternatives in case
expressions. As a simple example, consider the expression
\begin{verbatim}
  case x of
    Left y -> y
    Right z -> z
    _ -> undefined
\end{verbatim}
In this expression, the last alternative is never selected because the
first two alternatives already match all terms of type
\texttt{Either}. Since alternatives are partitioned according to the
roots of the terms at the selected position, we only need to compare
the number of groups of alternatives with the number of constructors
of the matched expression's type in order to check whether the default
pattern is redundant. This works also for characters and numbers, as
there are no constructors associated with the corresponding types and,
therefore, default alternatives are never considered redundant when
matching against literals.

Note that the default case may no longer be redundant if there are
guarded alternatives, e.g.
\begin{verbatim}
  case x of
    Left y | y > 0 -> y
    Right z | z > 0 -> z
    _ -> 0
\end{verbatim}
Nevertheless, we do not need to treat such case expressions
differently with respect to the completeness test because the default
case is duplicated into the \texttt{Left} and \texttt{Right}
alternatives. Thus, the example is effectively transformed into
\begin{verbatim}
  case x of
    Left y -> if y > 0 then y else 0
    Right z -> if z > 0 then z else 0
    _ -> 0
\end{verbatim}
where the default alternative is redundant.
\begin{verbatim}

> rigidMatch :: ModuleIdent -> ([(Type,Ident)] -> [(Type,Ident)])
>            -> [(Type,Ident)] -> [Match' Type]
>            -> CaseMatchState (Expression Type)
> rigidMatch m prefix [] (a:as) = matchAlt vs a (matchFail vs as)
>   where vs = prefix []
>         resetArgs (p,prefix,ts,rhs) = (p,id,prefix ts,rhs)
>         matchAlt vs (p,prefix,_,rhs) =
>           matchRhs m p (foldr2 (bindVars p . snd) rhs vs (prefix []))
>         matchFail vs as
>           | null as = Nothing
>           | otherwise = Just (rigidMatch m id vs (map resetArgs as))
> rigidMatch m prefix (v:vs) as
>   | isVarPattern (fst (head as')) =
>       if all (isVarPattern . fst) (tail as') then
>         rigidMatch m prefix vs (map (matchVar (snd v)) as)
>       else
>         rigidMatch m (prefix . (v:)) vs (map shiftArg as)
>   | otherwise =
>       do
>         tcEnv <- envRt
>         liftM (Case (uncurry mkVar v))
>               (mapM (matchCaseAlt m prefix v vs as')
>                     (if allCases tcEnv v ts then ts else ts ++ ts'))
>   where as' = map tagAlt as
>         (ts',ts) = partition isVarPattern (nub (map fst as'))
>         tagAlt (p,prefix,t:ts,rhs) = (pattern t,(p,prefix,t:ts,rhs))
>         shiftArg (p,prefix,t:ts,rhs) = (p,prefix . (t:),ts,rhs)
>         matchVar v (p,prefix,t:ts,rhs) = (p,prefix,ts,bindVars p v t rhs)
>         allCases tcEnv (ty,_) ts = length cs == length ts
>           where cs = constructors (fixType ty) tcEnv
>                 fixType (TypeConstructor tc _) = tc
>                 fixType (TypeConstrained (ty:_) _) = fixType ty

> matchCaseAlt :: ModuleIdent -> ([(Type,Ident)] -> [(Type,Ident)])
>              -> (Type,Ident) -> [(Type,Ident)]
>              -> [(ConstrTerm (),Match' Type)] -> ConstrTerm ()
>              -> CaseMatchState (Alt Type)
> matchCaseAlt m prefix v vs as t =
>   do
>     vs' <- matchVars (map arguments ts)
>     let ts' = map (uncurry VariablePattern) vs'
>     e' <- rigidMatch m id (prefix (vs' ++ vs)) (map (expandArg ts') as')
>     return (caseAlt (pos (head as')) (renameArgs (snd v) vs' t') e')
>   where t'
>           | isVarPattern t = uncurry VariablePattern v
>           | otherwise = head (filter (not . isVarPattern) ts)
>         ts = [t | (_,_,t:_,_) <- as']
>         as' = concatMap (select t) as
>         pos (p,_,_,_) = p
>         expandArg ts' (p,prefix,t:ts,rhs) =
>           (p,id,prefix (arguments' ts' t ++ ts),bindVars p (snd v) t rhs)
>         arguments' ts' t = if isVarPattern t then ts' else arguments t
>         select t (t',a)
>           | t' == t || isVarPattern t' = [a]
>           | not (all isVarPattern (prefix [])) = [(p,prefix,ts',rhs')]
>           | otherwise = []
>           where (p,prefix,_,_) = a
>                 ts' = map (uncurry VariablePattern) (v:vs)
>                 rhs' = GuardedRhs [] []

\end{verbatim}
Generation of fresh names
\begin{verbatim}

> freshVar :: String -> Type -> CaseMatchState (Type,Ident)
> freshVar prefix ty =
>   do
>     v <- liftM (mkName prefix) (liftRt (updateSt (1 +)))
>     return (ty,v)
>   where mkName pre n = renameIdent (mkIdent (pre ++ show n)) n

\end{verbatim}
Prelude entities
\begin{verbatim}

> prelConj :: Expression Type
> prelConj = preludeFun [boolType,boolType] boolType "&"

> unify, unifyRigid, prelUnknown :: Type -> Expression Type
> unify ty = preludeFun [ty,ty] boolType "=:<="
> unifyRigid ty = preludeFun [ty,ty] boolType "==<="
> prelUnknown ty = preludeFun [] ty "unknown"

> preludeFun :: [Type] -> Type -> String -> Expression Type
> preludeFun tys ty f =
>   Variable (foldr TypeArrow ty tys) (qualifyWith preludeMIdent (mkIdent f))

> truePattern, falsePattern :: ConstrTerm Type
> truePattern = ConstructorPattern boolType qTrueId []
> falsePattern = ConstructorPattern boolType qFalseId []

\end{verbatim}
Auxiliary definitions
\begin{verbatim}

> mkRhs :: Position -> Expression a -> Rhs a
> mkRhs p e = SimpleRhs p e []

> mkCase :: ModuleIdent -> Position -> (a,Ident) -> Expression a -> Expression a
>        -> Expression a
> mkCase m _ (_,v) e (Case (Variable _ v') as)
>   | qualify v == v' && v `notElem` qfv m as = Case e as
> mkCase m _ (_,v) e (Fcase (Variable _ v') as)
>   | qualify v == v' && v `notElem` qfv m as = Fcase e as
> mkCase _ p (ty,v) e e' = Let [varDecl p ty v e] e'

> addDecl :: Decl a -> Rhs a -> Rhs a
> addDecl d (SimpleRhs p e ds) = SimpleRhs p e (d : ds)
> addDecl d (GuardedRhs es ds) = GuardedRhs es (d : ds)

\end{verbatim}
