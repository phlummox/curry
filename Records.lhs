% -*- LaTeX -*-
% $Id: Records.lhs 3176 2015-09-03 16:35:33Z wlux $
%
% Copyright (c) 2001-2015, Wolfgang Lux
% See LICENSE for the full license.
%
\nwfilename{Records.lhs}
\section{Records and Field Labels}
As an extension to the Curry language the compiler supports Haskell's
record syntax, which introduces field labels for data and renaming
types. Field labels can be used in constructor declarations, patterns,
and expressions. For further convenience, an implicit selector
function is introduced for each field label. The code in this module
transforms the record notation into plain Curry code. Note that we
assume that most other syntactic sugar has been transformed already.
\begin{verbatim}

> module Records(unlabel) where
> import Combined
> import Curry
> import CurryUtils
> import List
> import Monad
> import PredefIdent
> import Types
> import TypeInfo
> import Typing
> import ValueInfo

\end{verbatim}
New identifiers are introduced for omitted fields in record patterns
and for the arguments of the implicit selector functions. We use
nested monad transformers for generating unique names and for passing
through the type constructor and value type environments. The former
is used to look up the valid constructors of an expression's type, the
latter to look up the types of record constructors and their field
labels.
\begin{verbatim}

> type UnlabelState a = ReaderT ValueEnv (ReaderT TCEnv (StateT Int Id)) a

> unlabel :: TCEnv -> ValueEnv -> Module Type -> Module Type
> unlabel tcEnv tyEnv (Module m es is ds) =
>   Module m es is (concat (run (mapM (unlabelTopDecl m tyEnv) ds) tcEnv tyEnv))

> run :: UnlabelState a -> TCEnv -> ValueEnv -> a
> run m tcEnv tyEnv = runSt (callRt (callRt m tyEnv) tcEnv) 1

\end{verbatim}
At the top-level of a module, we change record constructor
declarations into normal declarations and introduce the implicit
selector function for each field label.
\begin{verbatim}

> unlabelTopDecl :: ModuleIdent -> ValueEnv -> TopDecl Type
>                -> UnlabelState [TopDecl Type]
> unlabelTopDecl m tyEnv (DataDecl p tc tvs cs) =
>   do
>     ds' <-
>       mapM (selectorDecl tyEnv p (map (qualifyWith m . constr) cs))
>            (nub (concatMap labels cs))
>     return (DataDecl p tc tvs (map unlabelConstrDecl cs) : ds')
>   where unlabelConstrDecl (ConstrDecl p evs c tys) = ConstrDecl p evs c tys
>         unlabelConstrDecl (RecordDecl p evs c fs) =
>           ConstrDecl p evs c [ty | FieldDecl _ ls ty <- fs, _ <- ls]
> unlabelTopDecl m tyEnv (NewtypeDecl p tc tvs nc) =
>   do
>     ds' <-
>       mapM (selectorDecl tyEnv p [qualifyWith m (nconstr nc)]) (nlabel nc)
>     return (NewtypeDecl p tc tvs (unlabelNewConstrDecl nc) : ds')
>   where unlabelNewConstrDecl (NewConstrDecl p c ty) = NewConstrDecl p c ty
>         unlabelNewConstrDecl (NewRecordDecl p c _ ty) = NewConstrDecl p c ty
> unlabelTopDecl _ _ (TypeDecl p tc tvs ty) = return [TypeDecl p tc tvs ty]
> unlabelTopDecl _ _ (BlockDecl d) = liftM (return . BlockDecl) (unlabelDecl d)

> selectorDecl :: ValueEnv -> Position -> [QualIdent] -> Ident
>              -> UnlabelState (TopDecl Type)
> selectorDecl tyEnv p cs l =
>   liftM (BlockDecl . matchDecl p (rawType (varType l tyEnv)) l . concat)
>         (mapM (selectorEqn tyEnv l) cs)
>   where matchDecl p ty f eqs =
>           FunctionDecl p ty f [funEqn p f [t] e | (t,e) <- eqs]

> selectorEqn :: ValueEnv -> Ident -> QualIdent
>             -> UnlabelState [(ConstrTerm Type,Expression Type)]
> selectorEqn tyEnv l c =
>   case elemIndex l ls of
>     Just n ->
>       do
>         vs <- mapM (freshVar "_#rec") tys
>         return [(constrPattern ty0 c vs,uncurry mkVar (vs!!n))]
>     Nothing -> return []
>   where (ls,ty) = conType c tyEnv
>         (tys,ty0) = arrowUnapply (instType ty)

\end{verbatim}
Within block level declarations, the compiler replaces record patterns
and expressions.
\begin{verbatim}

> unlabelDecl :: Decl Type -> UnlabelState (Decl Type)
> unlabelDecl (FunctionDecl p ty f eqs) =
>   liftM (FunctionDecl p ty f) (mapM unlabelEquation eqs)
> unlabelDecl (ForeignDecl p fi ty f ty') = return (ForeignDecl p fi ty f ty')
> unlabelDecl (PatternDecl p t rhs) =
>   liftM2 (PatternDecl p) (unlabelTerm t) (unlabelRhs rhs)
> unlabelDecl (FreeDecl p vs) = return (FreeDecl p vs)

> unlabelEquation :: Equation Type -> UnlabelState (Equation Type)
> unlabelEquation (Equation p lhs rhs) =
>   liftM2 (Equation p) (unlabelLhs lhs) (unlabelRhs rhs)

\end{verbatim}
Record patterns are transformed into normal constructor patterns by
rearranging fields in the order of the record's declaration, adding
fresh variables in place of omitted fields, and discarding the field
labels.

Note: By rearranging fields here we loose the ability to comply
strictly with the Haskell 98 pattern matching semantics, which matches
fields of a record pattern in the order of their occurrence in the
pattern. However, keep in mind that Haskell matches alternatives from
top to bottom and arguments within an equation or alternative from
left to right, which is not the case in Curry except for rigid case
expressions.
\begin{verbatim}

> unlabelLhs :: Lhs Type -> UnlabelState (Lhs Type)
> unlabelLhs (FunLhs f ts) = liftM (FunLhs f) (mapM unlabelTerm ts)

> unlabelTerm :: ConstrTerm Type -> UnlabelState (ConstrTerm Type)
> unlabelTerm (LiteralPattern ty l) = return (LiteralPattern ty l)
> unlabelTerm (VariablePattern ty v) = return (VariablePattern ty v)
> unlabelTerm (ConstructorPattern ty c ts) =
>   liftM (ConstructorPattern ty c) (mapM unlabelTerm ts)
> unlabelTerm (FunctionPattern ty f ts) =
>   liftM (FunctionPattern ty f) (mapM unlabelTerm ts)
> unlabelTerm (RecordPattern ty c fs) =
>   do
>     tcEnv <- liftRt envRt
>     (ls,tys) <- liftM (argumentTypes tcEnv ty c) envRt
>     ts <- zipWithM argument tys (orderFields fs ls)
>     unlabelTerm (ConstructorPattern ty c ts)
>   where argument ty = maybe (fresh ty) return
>         fresh ty = liftM (uncurry VariablePattern) (freshVar "_#rec" ty)
> unlabelTerm (AsPattern v t) = liftM (AsPattern v) (unlabelTerm t)
> unlabelTerm (LazyPattern t) = liftM LazyPattern (unlabelTerm t)

\end{verbatim}
Record construction expressions are transformed into normal
constructor applications by rearranging fields in the order of the
record's declaration, passing \texttt{Prelude.undefined} in place of
omitted fields, and discarding the field labels. The transformation of
record update expressions is a bit more involved as we must match the
updated expression with all valid constructors of the expression's
type. As stipulated by the Haskell 98 Report, a record update
expression \texttt{$e$\char`\{\ $l_1$=$e_1$, $\dots$, $l_k$=$e_k$
  \char`\}} succeeds only if $e$ reduces to a value
$C\;e'_1\dots\;e'_n$ such that $C$'s declaration contains \emph{all}
field labels $l_1,\dots,l_k$. In contrast to Haskell we do not report
an error if this is not the case but rather fail only the current
solution.

\ToDo{Reconsider failing with a runtime error.}
\begin{verbatim}

> unlabelRhs :: Rhs Type -> UnlabelState (Rhs Type)
> unlabelRhs (SimpleRhs p e ds) =
>   do
>     ds' <- mapM unlabelDecl ds
>     e' <- unlabelExpr p e
>     return (SimpleRhs p e' ds')
> unlabelRhs (GuardedRhs es ds) =
>   do
>     ds' <- mapM unlabelDecl ds
>     es' <- mapM unlabelCondExpr es
>     return (GuardedRhs es' ds')

> unlabelCondExpr :: CondExpr Type -> UnlabelState (CondExpr Type)
> unlabelCondExpr (CondExpr p g e) =
>   liftM2 (CondExpr p) (unlabelExpr p g) (unlabelExpr p e)

> unlabelExpr :: Position -> Expression Type -> UnlabelState (Expression Type)
> unlabelExpr _ (Literal ty l) = return (Literal ty l)
> unlabelExpr _ (Variable ty v) = return (Variable ty v)
> unlabelExpr _ (Constructor ty c) = return (Constructor ty c)
> unlabelExpr p (Record ty c fs) =
>   do
>     tcEnv <- liftRt envRt
>     (ls,tys) <- liftM (argumentTypes tcEnv ty c) envRt
>     es <- zipWithM argument tys (orderFields fs ls)
>     unlabelExpr p (applyConstr ty c tys es)
>   where argument ty = maybe (fresh ty) return
>         fresh ty =
>           do
>             v <- freshVar "_#rec" ty
>             return (Let [FreeDecl p [uncurry FreeVar v]] (uncurry mkVar v))
> unlabelExpr p (RecordUpdate e fs) =
>   do
>     tyEnv <- envRt
>     tcEnv <- liftRt envRt
>     as <-
>       mapM (updateAlt tcEnv tyEnv . qualifyLike tc) (constructors tc tcEnv)
>     unlabelExpr p (Fcase e (map (uncurry (caseAlt p)) (concat as)))
>   where ty = typeOf e
>         TypeConstructor tc _ = arrowBase ty
>         ls = [unqualify l | Field l _ <- fs]
>         updateAlt tcEnv tyEnv c
>           | all (`elem` ls') ls =
>               do
>                 vs <- mapM (freshVar "_#rec") tys
>                 let es = zipWith argument vs (orderFields fs ls')
>                 return [(constrPattern ty c vs,applyConstr ty c tys es)]
>           | otherwise = return []
>           where (ls',tys) = argumentTypes tcEnv ty c tyEnv
>         argument v = maybe (uncurry mkVar v) id
> unlabelExpr p (Apply e1 e2) =
>   liftM2 Apply (unlabelExpr p e1) (unlabelExpr p e2)
> unlabelExpr _ (Lambda p ts e) =
>   liftM2 (Lambda p) (mapM unlabelTerm ts) (unlabelExpr p e)
> unlabelExpr p (Let ds e) = liftM2 Let (mapM unlabelDecl ds) (unlabelExpr p e)
> unlabelExpr p (Case e as) = liftM2 Case (unlabelExpr p e) (mapM unlabelAlt as)
> unlabelExpr p (Fcase e as) =
>   liftM2 Fcase (unlabelExpr p e) (mapM unlabelAlt as)

> unlabelAlt :: Alt Type -> UnlabelState (Alt Type)
> unlabelAlt (Alt p t rhs) = liftM2 (Alt p) (unlabelTerm t) (unlabelRhs rhs)

\end{verbatim}
The function \texttt{instType} instantiates the universally quantified
type variables of a type scheme with fresh type variables. Since this
function is used only to instantiate the closed types of record
constructors\footnote{Recall that no existentially quantified type
  variables are allowed for records}, the compiler can reuse the same
monomorphic type variables for every instantiated type.
\begin{verbatim}

> instType :: TypeScheme -> Type
> instType (ForAll _ ty) = inst ty
>   where inst (TypeConstructor tc tys) = TypeConstructor tc (map inst tys)
>         inst (TypeVariable tv) = TypeVariable (-1 - tv)
>         inst (TypeArrow ty1 ty2) = TypeArrow (inst ty1) (inst ty2)

\end{verbatim}
Generation of fresh names.
\begin{verbatim}

> freshVar :: String -> Type -> UnlabelState (Type,Ident)
> freshVar prefix ty =
>   do
>     v <- liftM (mkName prefix) (liftRt (liftRt (updateSt (1 +))))
>     return (ty,v)
>   where mkName pre n = renameIdent (mkIdent (pre ++ show n)) n

\end{verbatim}
Auxiliary definitions.
\begin{verbatim}

> constrPattern :: a -> QualIdent -> [(a,Ident)] -> ConstrTerm a
> constrPattern ty c vs =
>   ConstructorPattern ty c (map (uncurry VariablePattern) vs)

> applyConstr :: Type -> QualIdent -> [Type] -> [Expression Type]
>             -> Expression Type
> applyConstr ty c tys = apply (Constructor (foldr TypeArrow ty tys) c)

\end{verbatim}
