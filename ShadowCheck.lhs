% -*- LaTeX -*-
% $Id: ShadowCheck.lhs 1913 2006-05-07 13:44:36Z wlux $
%
% Copyright (c) 2005-2006, Wolfgang Lux
% See LICENSE for the full license.
%
\nwfilename{ShadowCheck.lhs}
\section{Checking for Shadowing Definitions}
Besides unused variables, the compiler can also report local
definitions which shadow a declaration from an outer scope.
\begin{verbatim}

> module ShadowCheck(shadowCheck, shadowCheckGoal) where
> import Base
> import Options
> import Set

> infixl 1 &&&, >>>

> shadowCheck :: [Warn] -> Module -> [String]
> shadowCheck v (Module m _ _ ds) =
>   report v $ shadow noPosition [d | BlockDecl d <- ds] (const []) zeroSet
>   where noPosition = error "noPosition"

> shadowCheckGoal :: [Warn] -> Goal -> [String]
> shadowCheckGoal v (Goal p e ds) =
>   report v $ shadow p (SimpleRhs p e ds) (const []) zeroSet

> report :: [Warn] -> [P Ident] -> [String]
> report ws
>   | WarnShadow `elem` ws = map format
>   | otherwise = const []

> format :: P Ident -> String
> format (P p x) =
>   atP p ("Warning: " ++ name x ++ " shadows non-local definition")

\end{verbatim}
Since shadowing can be checked efficiently only with unrenamed
identifiers, we must be careful about the set of defined variables
that are visible when checking an expression. We implement the check
with a continuation passing style using functions that take a
continuation and a set of defined identifiers as input and return a
list of shadowing definitions. In order to combine continuations, we
introduce two combinators \verb|(>>>)| and \verb|(&&&)| where
$f\,$\verb|>>>|$\,g$ invokes $g$ with the set of variables augmented
by $f$ and $f\,$\verb|&&&|$\,g$ invokes both $f$ and $g$ with the same
set of defined variables.
\begin{verbatim}

> type S = Set Ident -> [P Ident]

> bindVars :: [P Ident] -> S -> S
> bindVars bvs k vs =
>   filter (\(P _ x) -> x `elemSet` vs) bvs' ++
>   k (foldr addToSet vs [x | P _ x <- bvs'])
>   where bvs' = map (fmap unRenameIdent) bvs

> (>>>), (&&&) :: (S -> S) -> (S -> S) -> S -> S
> f1 >>> f2 = \f gvs -> f1 (f2 f) gvs
> f1 &&& f2 = \f gvs -> f1 (const (f2 f gvs)) gvs

\end{verbatim}
Collecting shadowing identifiers is implemented by just another
traversal of the syntax tree.
\begin{verbatim}

> class SyntaxTree a where
>   shadow :: Position -> a -> S -> S
>   shadowGroup :: Position -> [a] -> S -> S
>   shadowGroup p = foldr ((&&&) . shadow p) id

> instance SyntaxTree a => SyntaxTree [a] where
>   shadow p = shadowGroup p

> instance SyntaxTree Decl where
>   shadow _ (FunctionDecl p _ eqs) = shadow p eqs
>   shadow _ (PatternDecl p _ rhs) = shadow p rhs
>   shadow _ _ = id
>
>   shadowGroup p ds =
>     bindVars (concatMap vars ds) >>> foldr ((&&&) . shadow p) id ds

> instance SyntaxTree Equation where
>   shadow _ (Equation p lhs rhs) = shadow p lhs >>> shadow p rhs

> instance SyntaxTree Lhs where
>   shadow p lhs = bindVars (map (P p) (filter (not . isAnonId) (bv lhs)))

> instance SyntaxTree ConstrTerm where
>   shadow p t = bindVars (map (P p) (filter (not . isAnonId) (bv t)))

> instance SyntaxTree Rhs where
>   shadow _ (SimpleRhs p e ds) = shadow p ds >>> shadow p e
>   shadow p (GuardedRhs es ds) = shadow p ds >>> shadow p es

> instance SyntaxTree CondExpr where
>   shadow _ (CondExpr p g e) = shadow p g &&& shadow p e

> instance SyntaxTree Expression where
>   shadow _ (Literal _) = id
>   shadow _ (Variable _) = id
>   shadow _ (Constructor _) = id
>   shadow p (Paren e) = shadow p e
>   shadow p (Typed e _) = shadow p e
>   shadow p (Tuple es) = shadow p es
>   shadow p (List es) = shadow p es
>   shadow p (ListCompr e qs) = shadow p qs >>> shadow p e
>   shadow p (EnumFrom e) = shadow p e
>   shadow p (EnumFromThen e1 e2) = shadow p e1 &&& shadow p e2
>   shadow p (EnumFromTo e1 e2) = shadow p e1 &&& shadow p e2
>   shadow p (EnumFromThenTo e1 e2 e3) =
>     shadow p e1 &&& shadow p e2 &&& shadow p e3
>   shadow p (UnaryMinus _ e) = shadow p e
>   shadow p (Apply e1 e2) = shadow p e1 &&& shadow p e2
>   shadow p (InfixApply e1 _ e2) = shadow p e1 &&& shadow p e2
>   shadow p (LeftSection e _) = shadow p e
>   shadow p (RightSection _ e) = shadow p e
>   shadow p (Lambda ts e) = shadow p ts >>> shadow p e
>   shadow p (Let ds e) = shadow p ds >>> shadow p e
>   shadow p (Do sts e) = shadow p sts >>> shadow p e
>   shadow p (IfThenElse e1 e2 e3) =
>     shadow p e1 &&& shadow p e2 &&& shadow p e3
>   shadow p (Case e as) = shadow p e &&& shadow p as

> instance SyntaxTree Statement where
>   shadow p (StmtExpr e) = shadow p e
>   shadow p (StmtBind t e) = shadow p e &&& shadow p t
>   shadow p (StmtDecl ds) = shadow p ds

>   shadowGroup p = foldr ((>>>) . shadow p) id

> instance SyntaxTree Alt where
>   shadow _ (Alt p t rhs) = shadow p t >>> shadow p rhs

\end{verbatim}
The function \texttt{vars} returns the bound variables of a list of
declarations together with their positions.
\begin{verbatim}

> vars :: Decl -> [P Ident]
> vars (FunctionDecl p f _) = [P p f]
> vars (PatternDecl p t _) = map (P p) (filter (not . isAnonId) (bv t))
> vars (ForeignDecl p _ _ f _) = [P p f]
> vars (FreeDecl p vs) = map (P p) vs
> vars _ = []

\end{verbatim}
Anonymous identifiers in patterns are always ignored.
\begin{verbatim}

> isAnonId :: Ident -> Bool
> isAnonId x = unRenameIdent x == anonId

\end{verbatim}
