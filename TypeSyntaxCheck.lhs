% -*- LaTeX -*-
% $Id: TypeSyntaxCheck.lhs 2893 2009-08-10 15:28:04Z wlux $
%
% Copyright (c) 1999-2009, Wolfgang Lux
% See LICENSE for the full license.
%
\nwfilename{TypeSyntaxCheck.lhs}
\section{Checking Type Definitions}
After the source file has been parsed and all modules have been
imported, the compiler first checks all type definitions and
signatures. In particular, this module disambiguates nullary
constructors and type variables, which -- in contrast to many other
declarative languages -- cannot be done in the parser due to the lack
of a capitalization convention.
\begin{verbatim}

> module TypeSyntaxCheck(typeSyntaxCheck,typeSyntaxCheckGoal) where
> import Base
> import Curry
> import CurryPP
> import CurryUtils
> import Error
> import IdentInfo
> import List
> import Position
> import Pretty
> import TopEnv

\end{verbatim}
In order to check type constructor applications, the compiler
maintains an environment that records all known type constructors. The
functions \texttt{typeSyntaxCheck} and \texttt{typeSyntaxCheckGoal}
expect a type constructor environment that is already initialized with
the imported type constructors. All locally defined type constructors
are added to this environment and then the declarations are checked
within this environment. The environment is returned in order to be
used later for checking the optional export list of the current
module.
\begin{verbatim}

> typeSyntaxCheck :: ModuleIdent -> TypeEnv -> [TopDecl a]
>                 -> Error (TypeEnv,[TopDecl a])
> typeSyntaxCheck m env ds =
>   do
>     reportDuplicates duplicateType repeatedType (map tconstr tds)
>     ds' <- mapE (checkTopDecl env') ds
>     return (env',ds')
>   where tds = filter isTypeDecl ds
>         env' = foldr (bindType m) env tds

> typeSyntaxCheckGoal :: TypeEnv -> Goal a -> Error (Goal a)
> typeSyntaxCheckGoal env (Goal p e ds) =
>   liftE2 (Goal p) (checkExpr env p e) (mapE (checkDecl env) ds)

> bindType :: ModuleIdent -> TopDecl a -> TypeEnv -> TypeEnv
> bindType m (DataDecl _ tc _ cs) =
>   globalBindTopEnv m tc (Data (qualifyWith m tc) xs)
>   where xs = map constr cs ++ nub (concatMap labels cs)
> bindType m (NewtypeDecl _ tc _ nc) =
>   globalBindTopEnv m tc (Data (qualifyWith m tc) (nconstr nc : nlabel nc))
> bindType m (TypeDecl _ tc _ _) =
>   globalBindTopEnv m tc (Alias (qualifyWith m tc))
> bindType _ (BlockDecl _) = id
> bindType _ (SplitAnnot _) = id

\end{verbatim}
The compiler allows anonymous type variables on the left hand side of
type declarations, but not on their right hand side. Function and
pattern declarations are traversed in order to check local type
signatures.
\begin{verbatim}

> checkTopDecl :: TypeEnv -> TopDecl a -> Error (TopDecl a)
> checkTopDecl env (DataDecl p tc tvs cs) =
>   checkTypeLhs p tvs &&>
>   liftE (DataDecl p tc tvs) (mapE (checkConstrDecl env tvs) cs)
> checkTopDecl env (NewtypeDecl p tc tvs nc) =
>   checkTypeLhs p tvs &&>
>   liftE (NewtypeDecl p tc tvs) (checkNewConstrDecl env tvs nc)
> checkTopDecl env (TypeDecl p tc tvs ty) =
>   checkTypeLhs p tvs &&>
>   liftE (TypeDecl p tc tvs) (checkClosedType env p tvs ty)
> checkTopDecl env (BlockDecl d) = liftE BlockDecl (checkDecl env d)
> checkTopDecl _ (SplitAnnot p) = return (SplitAnnot p)

> checkDecl :: TypeEnv -> Decl a -> Error (Decl a)
> checkDecl _ (InfixDecl p fix pr ops) = return (InfixDecl p fix pr ops)
> checkDecl env (TypeSig p vs ty) =
>   liftE (TypeSig p vs) (checkType env p [] ty)
> checkDecl env (FunctionDecl p f eqs) =
>   liftE (FunctionDecl p f) (mapE (checkEquation env) eqs)
> checkDecl env (PatternDecl p t rhs) =
>   liftE (PatternDecl p t) (checkRhs env rhs)
> checkDecl env (ForeignDecl p cc s ie f ty) =
>   liftE (ForeignDecl p cc s ie f) (checkType env p [] ty)
> checkDecl _ (FreeDecl p vs) = return (FreeDecl p vs)
> checkDecl _ (TrustAnnot p tr fs) = return (TrustAnnot p tr fs)

> checkTypeLhs :: Position -> [Ident] -> Error ()
> checkTypeLhs p tvs =
>   mapE_ (errorAt p . nonLinear . fst) (duplicates (filter (anonId /=) tvs))

> checkConstrDecl :: TypeEnv -> [Ident] -> ConstrDecl -> Error ConstrDecl
> checkConstrDecl env tvs (ConstrDecl p evs c tys) =
>   checkTypeLhs p evs &&>
>   liftE (ConstrDecl p evs c) (mapE (checkClosedType env p tvs') tys)
>   where tvs' = evs ++ tvs
> checkConstrDecl env tvs (ConOpDecl p evs ty1 op ty2) =
>   checkTypeLhs p evs &&>
>   liftE2 (flip (ConOpDecl p evs) op)
>          (checkClosedType env p tvs' ty1)
>          (checkClosedType env p tvs' ty2)
>   where tvs' = evs ++ tvs
> checkConstrDecl env tvs (RecordDecl p evs c fs) =
>   checkTypeLhs p evs &&>
>   liftE (RecordDecl p evs c) (mapE (checkFieldDecl env tvs') fs)
>   where tvs' = evs ++ tvs

> checkFieldDecl :: TypeEnv -> [Ident] -> FieldDecl -> Error FieldDecl
> checkFieldDecl env tvs (FieldDecl p ls ty) =
>   liftE (FieldDecl p ls) (checkClosedType env p tvs ty)

> checkNewConstrDecl :: TypeEnv -> [Ident] -> NewConstrDecl
>                    -> Error NewConstrDecl
> checkNewConstrDecl env tvs (NewConstrDecl p c ty) =
>   liftE (NewConstrDecl p c) (checkClosedType env p tvs ty)
> checkNewConstrDecl env tvs (NewRecordDecl p c l ty) =
>   liftE (NewRecordDecl p c l) (checkClosedType env p tvs ty)

\end{verbatim}
Checking expressions is rather straightforward. The compiler must only
traverse the structure of expressions in order to find local
declaration groups.
\begin{verbatim}

> checkEquation :: TypeEnv -> Equation a -> Error (Equation a)
> checkEquation env (Equation p lhs rhs) =
>   liftE (Equation p lhs) (checkRhs env rhs)

> checkRhs :: TypeEnv -> Rhs a -> Error (Rhs a)
> checkRhs env (SimpleRhs p e ds) =
>   liftE2 (SimpleRhs p) (checkExpr env p e) (mapE (checkDecl env) ds)
> checkRhs env (GuardedRhs es ds) =
>   liftE2 GuardedRhs (mapE (checkCondExpr env) es) (mapE (checkDecl env) ds)

> checkCondExpr :: TypeEnv -> CondExpr a -> Error (CondExpr a)
> checkCondExpr env (CondExpr p g e) =
>   liftE2 (CondExpr p) (checkExpr env p g) (checkExpr env p e)

> checkExpr :: TypeEnv -> Position -> Expression a -> Error (Expression a)
> checkExpr _ _ (Literal a l) = return (Literal a l)
> checkExpr _ _ (Variable a v) = return (Variable a v)
> checkExpr _ _ (Constructor a c) = return (Constructor a c)
> checkExpr env p (Paren e) = liftE Paren (checkExpr env p e)
> checkExpr env p (Typed e ty) =
>   liftE2 Typed (checkExpr env p e) (checkType env p [] ty)
> checkExpr env p (Record a c fs) =
>   liftE (Record a c) (mapE (checkField env p) fs)
> checkExpr env p (RecordUpdate e fs) =
>   liftE2 RecordUpdate (checkExpr env p e) (mapE (checkField env p) fs)
> checkExpr env p (Tuple es) = liftE Tuple (mapE (checkExpr env p) es)
> checkExpr env p (List a es) = liftE (List a) (mapE (checkExpr env p) es)
> checkExpr env p (ListCompr e qs) =
>   liftE2 ListCompr (checkExpr env p e) (mapE (checkStmt env p) qs)
> checkExpr env p (EnumFrom e) = liftE EnumFrom (checkExpr env p e)
> checkExpr env p (EnumFromThen e1 e2) =
>   liftE2 EnumFromThen (checkExpr env p e1) (checkExpr env p e2)
> checkExpr env p (EnumFromTo e1 e2) =
>   liftE2 EnumFromTo (checkExpr env p e1) (checkExpr env p e2)
> checkExpr env p (EnumFromThenTo e1 e2 e3) =
>   liftE3 EnumFromThenTo
>          (checkExpr env p e1)
>          (checkExpr env p e2)
>          (checkExpr env p e3)
> checkExpr env p (UnaryMinus op e) = liftE (UnaryMinus op) (checkExpr env p e)
> checkExpr env p (Apply e1 e2) =
>   liftE2 Apply (checkExpr env p e1) (checkExpr env p e2)
> checkExpr env p (InfixApply e1 op e2) =
>   liftE2 (flip InfixApply op) (checkExpr env p e1) (checkExpr env p e2)
> checkExpr env p (LeftSection e op) =
>   liftE (flip LeftSection op) (checkExpr env p e)
> checkExpr env p (RightSection op e) =
>   liftE (RightSection op) (checkExpr env p e)
> checkExpr env _ (Lambda p ts e) = liftE (Lambda p ts) (checkExpr env p e)
> checkExpr env p (Let ds e) =
>   liftE2 Let (mapE (checkDecl env) ds) (checkExpr env p e)
> checkExpr env p (Do sts e) =
>   liftE2 Do (mapE (checkStmt env p) sts) (checkExpr env p e)
> checkExpr env p (IfThenElse e1 e2 e3) =
>   liftE3 IfThenElse
>          (checkExpr env p e1)
>          (checkExpr env p e2)
>          (checkExpr env p e3)
> checkExpr env p (Case e alts) =
>   liftE2 Case (checkExpr env p e) (mapE (checkAlt env) alts)
> checkExpr env p (Fcase e alts) =
>   liftE2 Fcase (checkExpr env p e) (mapE (checkAlt env) alts)

> checkStmt :: TypeEnv -> Position -> Statement a -> Error (Statement a)
> checkStmt env p (StmtExpr e) = liftE StmtExpr (checkExpr env p e)
> checkStmt env _ (StmtBind p t e) = liftE (StmtBind p t) (checkExpr env p e)
> checkStmt env _ (StmtDecl ds) = liftE StmtDecl (mapE (checkDecl env) ds)

> checkAlt :: TypeEnv -> Alt a -> Error (Alt a)
> checkAlt env (Alt p t rhs) = liftE (Alt p t) (checkRhs env rhs)

> checkField :: TypeEnv -> Position -> Field (Expression a)
>            -> Error (Field (Expression a))
> checkField env p (Field l e) = liftE (Field l) (checkExpr env p e)

\end{verbatim}
The parser cannot distinguish unqualified nullary type constructors
and type variables. Therefore, if the compiler finds an unbound
identifier in a position where a type variable is admissible, it will
interpret the identifier as such. In type declarations, type variables
on the left hand side of a declaration can shadow type constructors
with the same name.
\begin{verbatim}

> checkClosedType :: TypeEnv -> Position -> [Ident] -> TypeExpr
>                 -> Error TypeExpr
> checkClosedType env p tvs ty =
>   do
>     ty' <- checkType env p tvs ty
>     mapE_ (errorAt p . unboundVariable)
>           (nub (filter (\tv -> tv == anonId || tv `notElem` tvs) (fv ty')))
>     return ty'

> checkType :: TypeEnv -> Position -> [Ident] -> TypeExpr -> Error TypeExpr
> checkType env p tvs (ConstructorType tc tys) =
>   liftE2 ($)
>          (checkTypeConstr env p tvs tc (null tys))
>          (mapE (checkType env p tvs) tys)
> checkType env p tvs (VariableType tv)
>   | tv `elem` anonId:tvs = return (VariableType tv)
>   | otherwise = checkType env p tvs (ConstructorType (qualify tv) [])
> checkType env p tvs (TupleType tys) =
>   liftE TupleType (mapE (checkType env p tvs) tys)
> checkType env p tvs (ListType ty) =
>   liftE ListType (checkType env p tvs ty)
> checkType env p tvs (ArrowType ty1 ty2) =
>   liftE2 ArrowType (checkType env p tvs ty1) (checkType env p tvs ty2)

> checkTypeConstr :: TypeEnv -> Position -> [Ident] -> QualIdent -> Bool
>                 -> Error ([TypeExpr] -> TypeExpr)
> checkTypeConstr env p tvs tc atom
>   | tc `elem` map qualify tvs = checkTypeVar p tc atom
>   | otherwise =
>       case qualLookupTopEnv tc env of
>         []
>           | not (isQualified tc) -> checkTypeVar p tc atom
>           | otherwise -> errorAt p (undefinedType tc)
>         [_] -> return (ConstructorType tc)
>         rs -> errorAt p (ambiguousType rs tc)

> checkTypeVar :: Position -> QualIdent -> Bool
>              -> Error ([TypeExpr] -> TypeExpr)
> checkTypeVar p tv atom
>   | atom = return (const (VariableType (unqualify tv)))
>   | otherwise = errorAt p (undefinedType tv)

\end{verbatim}
Auxiliary definitions.
\begin{verbatim}

> tconstr :: TopDecl a -> P Ident
> tconstr (DataDecl p tc _ _) = P p tc
> tconstr (NewtypeDecl p tc _ _) = P p tc
> tconstr (TypeDecl p tc _ _) = P p tc
> tconstr (BlockDecl _) = internalError "tconstr"
> tconstr (SplitAnnot _) = internalError "tconstr"

\end{verbatim}
Error messages.
\begin{verbatim}

> reportDuplicates :: Eq a => (a -> String) -> (a -> String) -> [P a]
>                  -> Error ()
> reportDuplicates f1 f2 xs =
>   mapE_ (\(x,xs) -> zipWithE_ report (f1 : repeat f2) (x:xs)) (duplicates xs)
>   where report f (P p x) = errorAt p (f x)

> undefinedType :: QualIdent -> String
> undefinedType tc = "Undefined type " ++ qualName tc

> ambiguousType :: [TypeKind] -> QualIdent -> String
> ambiguousType rs tc = show $
>   text "Ambiguous type" <+> ppQIdent tc $$
>   fsep (text "Could refer to:" :
>               punctuate comma (map (ppQIdent . origName) rs))

> duplicateType :: Ident -> String
> duplicateType tc = "Type " ++ name tc ++ " defined more than once"

> repeatedType :: Ident -> String
> repeatedType tc = "Redefinition of type " ++ name tc

> nonLinear :: Ident -> String
> nonLinear tv =
>   "Type variable " ++ name tv ++
>   " occurs more than once in left hand side of type declaration"

> unboundVariable :: Ident -> String
> unboundVariable tv = "Undefined type variable " ++ name tv

\end{verbatim}
