% -*- LaTeX -*-
% $Id: OverlapCheck.lhs 3014 2010-11-16 21:09:29Z wlux $
%
% Copyright (c) 2006-2010, Wolfgang Lux
% See LICENSE for the full license.
%
\nwfilename{OverlapCheck.lhs}
\section{Checking for Rules with Overlapping Patterns}
The compiler can report warnings for functions with overlapping left
hand sides and flexible case expressions with overlapping patterns,
which both may cause unintended non-deterministic evaluation.
\begin{verbatim}

> module OverlapCheck(overlapCheck, overlapCheckGoal) where
> import Curry
> import CurryUtils
> import List
> import Options
> import Position
> import PredefIdent
> import Utils
> import ValueInfo

> overlapCheck :: [Warn] -> ValueEnv -> Module a -> [String]
> overlapCheck v tyEnv (Module m _ _ ds) =
>   report v $ overlap tyEnv noPosition [d | BlockDecl d <- ds] []
>   where noPosition = error "noPosition"

> overlapCheckGoal :: [Warn] -> ValueEnv -> Goal a -> [String]
> overlapCheckGoal v tyEnv (Goal p e ds) =
>   report v $ overlap tyEnv p (SimpleRhs p e ds) []

> report :: [Warn] -> [P (Maybe Ident)] -> [String]
> report ws
>   | WarnOverlap `elem` ws = map format
>   | otherwise = const []

> format :: P (Maybe Ident) -> String
> format (P p (Just x)) =
>   atP p ("Warning: " ++ name x ++ " has overlapping rules")
> format (P p Nothing) =
>   atP p ("Warning: overlapping patterns in fcase expression")

\end{verbatim}
The names and the source locations of functions with overlapping left
hand side patterns as well as the source locations of flexible case
expressions with overlapping patterns are collected with a simple
traversal of the syntax tree.
\begin{verbatim}

> class Syntax a where
>   overlap :: ValueEnv -> Position -> a -> [P (Maybe Ident)]
>           -> [P (Maybe Ident)]

> instance Syntax a => Syntax [a] where
>   overlap tyEnv p xs ys = foldr (overlap tyEnv p) ys xs

> instance Syntax (Decl a) where
>   overlap tyEnv _ (FunctionDecl p _ f eqs) =
>     ([P p (Just f) | isNonDet tyEnv tss] ++) . overlap tyEnv p eqs
>     where tss = [snd (flatLhs lhs) | (Equation _ lhs _) <- eqs]
>   overlap tyEnv _ (PatternDecl p _ rhs) = overlap tyEnv p rhs
>   overlap _ _ _ = id

> instance Syntax (Equation a) where
>   overlap tyEnv _ (Equation p _ rhs) = overlap tyEnv p rhs

> instance Syntax (Rhs a) where
>   overlap tyEnv _ (SimpleRhs p e ds) = overlap tyEnv p ds . overlap tyEnv p e
>   overlap tyEnv p (GuardedRhs es ds) = overlap tyEnv p ds . overlap tyEnv p es

> instance Syntax (CondExpr a) where
>   overlap tyEnv _ (CondExpr p g e) = overlap tyEnv p g . overlap tyEnv p e

> instance Syntax (Expression a) where
>   overlap _ _ (Literal _ _) = id
>   overlap _ _ (Variable _ _) = id
>   overlap _ _ (Constructor _ _) = id
>   overlap tyEnv p (Paren e) = overlap tyEnv p e
>   overlap tyEnv p (Typed e _) = overlap tyEnv p e
>   overlap tyEnv p (Record _ _ fs) = overlap tyEnv p fs
>   overlap tyEnv p (RecordUpdate e fs) = overlap tyEnv p e . overlap tyEnv p fs
>   overlap tyEnv p (Tuple es) = overlap tyEnv p es
>   overlap tyEnv p (List _ es) = overlap tyEnv p es
>   overlap tyEnv p (ListCompr e qs) = overlap tyEnv p qs . overlap tyEnv p e
>   overlap tyEnv p (EnumFrom e) = overlap tyEnv p e
>   overlap tyEnv p (EnumFromThen e1 e2) =
>     overlap tyEnv p e1 . overlap tyEnv p e2
>   overlap tyEnv p (EnumFromTo e1 e2) = overlap tyEnv p e1 . overlap tyEnv p e2
>   overlap tyEnv p (EnumFromThenTo e1 e2 e3) =
>     overlap tyEnv p e1 . overlap tyEnv p e2 . overlap tyEnv p e3
>   overlap tyEnv p (UnaryMinus _ e) = overlap tyEnv p e
>   overlap tyEnv p (Apply e1 e2) = overlap tyEnv p e1 . overlap tyEnv p e2
>   overlap tyEnv p (InfixApply e1 _ e2) =
>     overlap tyEnv p e1 . overlap tyEnv p e2
>   overlap tyEnv p (LeftSection e _) = overlap tyEnv p e
>   overlap tyEnv p (RightSection _ e) = overlap tyEnv p e
>   overlap tyEnv _ (Lambda p _ e) = overlap tyEnv p e
>   overlap tyEnv p (Let ds e) = overlap tyEnv p ds . overlap tyEnv p e
>   overlap tyEnv p (Do sts e) = overlap tyEnv p sts . overlap tyEnv p e
>   overlap tyEnv p (IfThenElse e1 e2 e3) =
>     overlap tyEnv p e1 . overlap tyEnv p e2 . overlap tyEnv p e3
>   overlap tyEnv p (Case e as) = overlap tyEnv p e . overlap tyEnv p as
>   overlap tyEnv p (Fcase e as) =
>     overlap tyEnv p e .
>     ([P p' Nothing | isNonDet tyEnv tss] ++) . overlap tyEnv p as
>     where p' = head [p | Alt p _ _ <- as]
>           tss = [[t] | (Alt _ t _) <- as]

> instance Syntax (Statement a) where
>   overlap tyEnv p (StmtExpr e) = overlap tyEnv p e
>   overlap tyEnv _ (StmtBind p _ e) = overlap tyEnv p e
>   overlap tyEnv p (StmtDecl ds) = overlap tyEnv p ds

> instance Syntax (Alt a) where
>   overlap tyEnv _ (Alt p _ rhs) = overlap tyEnv p rhs

> instance Syntax a => Syntax (Field a) where
>   overlap tyEnv p (Field l x) = overlap tyEnv p x

\end{verbatim}
The code checking whether the equations of a function and the
alternatives of a flexible case expression, respectively, have
overlapping patterns is essentially a simplified version of the
pattern matching algorithm implemented in module \texttt{ILTrans} (see
Sect.~\ref{sec:flatcase}).

\ToDo{Implement a similar check to report completely overlapped
  patterns, and thus unreachable alternatives, in rigid case
  expressions.}
\begin{verbatim}

> isNonDet :: ValueEnv -> [[ConstrTerm a]] -> Bool
> isNonDet tyEnv tss = isOverlap (map (map (desugar tyEnv)) tss)

> isOverlap :: [[ConstrTerm ()]] -> Bool
> isOverlap (ts:tss) =
>   not (null tss) &&
>   case matchInductive (ts:tss) of
>      [] -> True
>      tss:_ -> any isOverlap tss

> matchInductive :: [[ConstrTerm ()]] -> [[[[ConstrTerm ()]]]]
> matchInductive =
>   map groupRules . filter isInductive . transpose . map (matches id)
>   where isInductive = all (not . isVarPattern . fst)

> groupRules :: [(ConstrTerm (),a)] -> [[a]]
> groupRules [] = []
> groupRules ((t,ts):tss) = (ts:map snd same) : groupRules tss
>   where (same,other) = partition ((t ==) . fst) tss

> matches :: ([ConstrTerm a] -> [ConstrTerm a]) -> [ConstrTerm a]
>         -> [(ConstrTerm a,[ConstrTerm a])]
> matches _ [] = []
> matches f (t:ts) = (t',f (ts' ++ ts)) : matches (f . (t:)) ts
>   where (t',ts') = match t
>         match (ConstructorPattern a c ts) = (ConstructorPattern a c [],ts)
>         match (LiteralPattern a l) = (LiteralPattern a l,[])
>         match (VariablePattern a v) = (VariablePattern a v,[])

\end{verbatim}
Unfortunately, the code has not been desugared yet.
\begin{verbatim}

> desugar :: ValueEnv -> ConstrTerm a -> ConstrTerm ()
> desugar tyEnv (LiteralPattern a l) =
>   case l of
>     String cs ->
>       desugar tyEnv (ListPattern a (map (LiteralPattern a . Char) cs))
>     _ -> LiteralPattern () l
> desugar tyEnv (NegativePattern a _ l) =
>   desugar tyEnv (LiteralPattern a (negateLit l))
>   where negateLit (Int i) = Int (-i)
>         negateLit (Float f) = Float (-f)
> desugar _ (VariablePattern _ v) = VariablePattern () anonId
> desugar tyEnv (ConstructorPattern _ c ts) =
>   ConstructorPattern () c (map (desugar tyEnv) ts)
> desugar _ (FunctionPattern _ _ _) = VariablePattern () anonId
> desugar tyEnv (InfixPattern a t1 op t2) =
>   desugar tyEnv (desugarOp a op [t1,t2])
>   where desugarOp a (InfixConstr _ op) = ConstructorPattern a op
>         desugarOp a (InfixOp _ op) = FunctionPattern a op
> desugar tyEnv (ParenPattern t) = desugar tyEnv t
> desugar tyEnv (RecordPattern a c fs) =
>   ConstructorPattern () c (map (argument tyEnv) (orderFields fs ls))
>   where ls = fst (conType c tyEnv)
>         argument tyEnv = maybe (VariablePattern () anonId) (desugar tyEnv)
> desugar tyEnv (TuplePattern ts) =
>   ConstructorPattern () c (map (desugar tyEnv) ts)
>   where c = qTupleId (length ts)
> desugar tyEnv (ListPattern a ts) = desugar tyEnv (foldr cons nil ts)
>   where nil = ConstructorPattern a qNilId []
>         cons t1 t2 = ConstructorPattern a qConsId [t1,t2]
> desugar tyEnv (AsPattern _ t) = desugar tyEnv t
> desugar _ (LazyPattern _) = VariablePattern () anonId

\end{verbatim}
