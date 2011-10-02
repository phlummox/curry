% -*- LaTeX -*-
% $Id: CurryUtils.lhs 3048 2011-10-02 14:14:03Z wlux $
%
% Copyright (c) 1999-2011, Wolfgang Lux
% See LICENSE for the full license.
%
\nwfilename{CurryUtils.lhs}
\section{Utilities for the Syntax Tree}
The module \texttt{CurryUtils} provides definitions that are useful
for analyzing and constructing abstract syntax trees of Curry modules
and goals.
\begin{verbatim}

> module CurryUtils where
> import Curry
> import List

\end{verbatim}
Some compiler phases rearrange (top-level) declarations according to
semantic criteria. The following code allows restoring the textual
order of textual declarations.
\begin{verbatim}

> sortDecls :: [TopDecl a] -> [TopDecl a]
> sortDecls = sortBy (\d1 d2 -> compare (pos d1) (pos d2))

> class Declaration a where
>   pos :: a -> Position

> instance Declaration (TopDecl a) where
>   pos (DataDecl p _ _ _) = p
>   pos (NewtypeDecl p _ _ _) = p
>   pos (TypeDecl p _ _ _) = p
>   pos (BlockDecl d) = pos d

> instance Declaration (Decl a) where
>   pos (InfixDecl p _ _ _) = p
>   pos (TypeSig p _ _) = p
>   pos (FunctionDecl p _ _ _) = p
>   pos (ForeignDecl p _ _ _ _) = p
>   pos (PatternDecl p _ _) = p
>   pos (FreeDecl p _) = p
>   pos (TrustAnnot p _ _) = p

\end{verbatim}
Here is a list of predicates identifying various kinds of
declarations.
\begin{verbatim}

> isTypeDecl, isBlockDecl :: TopDecl a -> Bool
> isTypeDecl (DataDecl _ _ _ _) = True
> isTypeDecl (NewtypeDecl _ _ _ _) = True
> isTypeDecl (TypeDecl _ _ _ _) = True
> isTypeDecl (BlockDecl _) = False
> isBlockDecl (BlockDecl _) = True
> isBlockDecl _ = False

> isInfixDecl, isTypeSig, isFunDecl, isFreeDecl :: Decl a -> Bool
> isTrustAnnot, isValueDecl :: Decl a -> Bool
> isInfixDecl (InfixDecl _ _ _ _) = True
> isInfixDecl _ = False
> isTypeSig (TypeSig _ _ _) = True
> isTypeSig (ForeignDecl _ _ _ _ _) = True
> isTypeSig _ = False
> isFunDecl (FunctionDecl _ _ _ _) = True
> isFunDecl (ForeignDecl _ _ _ _ _) = True
> isFunDecl _ = False
> isFreeDecl (FreeDecl _ _) = True
> isFreeDecl _ = False
> isTrustAnnot (TrustAnnot _ _ _) = True
> isTrustAnnot _ = False
> isValueDecl (FunctionDecl _ _ _ _) = True
> isValueDecl (ForeignDecl _ _ _ _ _) = True
> isValueDecl (PatternDecl _ _ _) = True
> isValueDecl (FreeDecl _ _) = True
> isValueDecl _ = False

\end{verbatim}
The function \texttt{isVarPattern} returns true if its argument is
semantically equivalent to a variable pattern. Note that in particular
this function returns \texttt{True} for lazy patterns.
\begin{verbatim}

> isVarPattern :: ConstrTerm a -> Bool
> isVarPattern (LiteralPattern _ _) = False
> isVarPattern (NegativePattern _ _ _) = False
> isVarPattern (VariablePattern _ _) = True
> isVarPattern (ConstructorPattern _ _ _) = False
> isVarPattern (FunctionPattern _ _ _) = False
> isVarPattern (InfixPattern _ _ _ _) = False
> isVarPattern (ParenPattern t) = isVarPattern t
> isVarPattern (TuplePattern _) = False
> isVarPattern (ListPattern _ _) = False
> isVarPattern (AsPattern _ t) = isVarPattern t
> isVarPattern (LazyPattern _) = True

\end{verbatim}
The functions \texttt{constr} and \texttt{nconstr} return the
constructor name of a data constructor and newtype constructor
declaration, respectively.
\begin{verbatim}

> constr :: ConstrDecl -> Ident
> constr (ConstrDecl _ _ c _) = c
> constr (ConOpDecl _ _ _ op _) = op
> constr (RecordDecl _ _ c _) = c

> nconstr :: NewConstrDecl -> Ident
> nconstr (NewConstrDecl _ c _) = c
> nconstr (NewRecordDecl _ c _ _) = c

\end{verbatim}
The functions \texttt{labels} and \texttt{nlabel} return the field
label identifiers of a data constructor and newtype constructor
declaration, respectively.
\begin{verbatim}

> labels :: ConstrDecl -> [Ident]
> labels (ConstrDecl _ _ _ _) = []
> labels (ConOpDecl _ _ _ _ _) = []
> labels (RecordDecl _ _ _ fs) = [l | FieldDecl _ ls _ <- fs, l <- ls]

> nlabel :: NewConstrDecl -> [Ident]
> nlabel (NewConstrDecl _ _ _) = []
> nlabel (NewRecordDecl _ _ l _) = [l]

\end{verbatim}
The function \texttt{eqnArity} returns the (syntactic) arity of a
function equation and \texttt{flatLhs} returns the function name and
the list of arguments from the left hand side of a function equation.
\begin{verbatim}

> eqnArity :: Equation a -> Int
> eqnArity (Equation _ lhs _) = length (snd (flatLhs lhs))

> flatLhs :: Lhs a -> (Ident,[ConstrTerm a])
> flatLhs lhs = flat lhs []
>   where flat (FunLhs f ts) ts' = (f,ts ++ ts')
>         flat (OpLhs t1 op t2) ts = (op,t1:t2:ts)
>         flat (ApLhs lhs ts) ts' = flat lhs (ts ++ ts')

\end{verbatim}
The function \texttt{infixOp} converts an infix operator into an
expression and the function \texttt{opName} returns the operator's
name.
\begin{verbatim}

> infixOp :: InfixOp a -> Expression a
> infixOp (InfixOp a op) = Variable a op
> infixOp (InfixConstr a op) = Constructor a op

> opName :: InfixOp a -> QualIdent
> opName (InfixOp _ op) = op
> opName (InfixConstr _ c) = c

\end{verbatim}
The function \texttt{orderFields} sorts the arguments of a record
pattern or expression into a fixed order, which usually is the order
in which the labels appear in the record's declaration.
\begin{verbatim}

> orderFields :: [Field a] -> [Ident] -> [Maybe a]
> orderFields fs ls = map (flip lookup [(unqualify l,x) | Field l x <- fs]) ls

\end{verbatim}
The function \texttt{entity} returns the qualified name of the entity
defined by an interface declaration.
\begin{verbatim}

> entity :: IDecl -> QualIdent
> entity (IInfixDecl _ _ _ op) = op
> entity (HidingDataDecl _ tc _) = tc
> entity (IDataDecl _ tc _ _ _) = tc
> entity (INewtypeDecl _ tc _ _ _) = tc
> entity (ITypeDecl _ tc _ _) = tc
> entity (IFunctionDecl _ f _ _) = f

\end{verbatim}
The function \texttt{unhide} makes interface declarations transparent,
i.e., it replaces hidden data type declarations by standard data type
declarations and removes all hiding specifications from interface
declarations.
\begin{verbatim}

> unhide :: IDecl -> IDecl
> unhide (IInfixDecl p fix pr op) = IInfixDecl p fix pr op
> unhide (HidingDataDecl p tc tvs) = IDataDecl p tc tvs [] []
> unhide (IDataDecl p tc tvs cs _) = IDataDecl p tc tvs cs []
> unhide (INewtypeDecl p tc tvs nc _) = INewtypeDecl p tc tvs nc []
> unhide (ITypeDecl p tc tvs ty) = ITypeDecl p tc tvs ty
> unhide (IFunctionDecl p f n ty) = IFunctionDecl p f n ty

\end{verbatim}
Here are a few convenience functions for constructing (elements of)
abstract syntax trees.
\begin{verbatim}

> funDecl :: Position -> a -> Ident -> [ConstrTerm a] -> Expression a -> Decl a
> funDecl p a f ts e = FunctionDecl p a f [funEqn p f ts e]

> funEqn :: Position -> Ident -> [ConstrTerm a] -> Expression a -> Equation a
> funEqn p f ts e = Equation p (FunLhs f ts) (SimpleRhs p e [])

> patDecl :: Position -> ConstrTerm a -> Expression a -> Decl a
> patDecl p t e = PatternDecl p t (SimpleRhs p e [])

> varDecl :: Position -> a -> Ident -> Expression a -> Decl a
> varDecl p ty = patDecl p . VariablePattern ty

> caseAlt :: Position -> ConstrTerm a -> Expression a -> Alt a
> caseAlt p t e = Alt p t (SimpleRhs p e [])

> mkLet :: [Decl a] -> Expression a -> Expression a
> mkLet ds e = if null ds then e else Let ds e

> apply :: Expression a -> [Expression a] -> Expression a
> apply = foldl Apply

> mkVar :: a -> Ident -> Expression a
> mkVar ty = Variable ty . qualify

\end{verbatim}
