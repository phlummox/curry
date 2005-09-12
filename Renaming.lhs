% -*- LaTeX -*-
% $Id: Renaming.lhs 1760 2005-09-04 15:43:03Z wlux $
%
% Copyright (c) 1999-2005, Wolfgang Lux
% See LICENSE for the full license.
%
\nwfilename{Renaming.lhs}
\section{Renaming}
After checking for syntax errors, the compiler renames all local
variables. This renaming allows the compiler to pass on type
information to later phases in a flat environment, and also makes
lifting of declarations simpler. Renaming is performed by adding a
unique key to each \emph{local} variable. Global variables are not
renamed so that no renamed variables occur in module interfaces.
Since no name conflicts are possible within a declaration group, the
same key can be used for all identifiers declared in that group.
Nevertheless, a fresh key must be generated for each anonymous
variable.

Note that this pass deliberately \emph{does not} qualify the names of
imported functions and constructors. This qualification will be done
after type checking was performed.
\begin{verbatim}

> module Renaming(rename,renameGoal) where
> import Base
> import Combined
> import Env
> import Maybe
> import Monad
> import Utils

\end{verbatim}
Since only local variables are renamed, it is sufficient to use an
environment mapping unqualified identifiers onto their new names.
\begin{verbatim}

> type RenameEnv = Env Ident Ident

> bindVar :: Int -> Ident -> RenameEnv -> RenameEnv
> bindVar k x = bindEnv x (renameIdent x k)

> lookupVar :: Ident -> RenameEnv -> Maybe Ident
> lookupVar = lookupEnv

\end{verbatim}
In order to thread the counter used for generating unique keys, we use
a simple state monad.
\begin{verbatim}

> type RenameState a = StateT Int Id a

> run :: RenameState a -> a
> run m = runSt m (globalKey + 1)

> globalKey :: Int
> globalKey = uniqueId (mkIdent "")

\end{verbatim}
New variable bindings are introduced at the level of declaration
groups and argument lists. We do not care about entering anonymous
identifiers into the environment, since \texttt{renameVar} does not
look them up in the environment.
\begin{verbatim}

> bindVars :: QuantExpr e => RenameEnv -> e -> RenameState RenameEnv
> bindVars env e = liftM (\k -> foldr (bindVar k) env (bv e)) (updateSt (1 +))

\end{verbatim}
The function \texttt{renameVar} renames an identifier. When applied to
an anonymous identifier, a fresh index is used to rename it. For all
other identifiers, \texttt{renameVar} checks whether a binding is
present in the current renaming environment and returns that binding.
Otherwise, the unmodified identifier is returned.

As all qualified identifiers refer to top-level entities (either
defined in the current module or imported from another module),
\texttt{renameQual} applies renaming only to identifiers without a
module qualifier.
\begin{verbatim}

> renameVar :: RenameEnv -> Ident -> RenameState Ident
> renameVar env x
>   | x == anonId = liftM (renameIdent x) (updateSt (1 +))
>   | otherwise = return (fromMaybe x (lookupVar x env))

> renameQual :: RenameEnv -> QualIdent -> RenameState QualIdent
> renameQual env x
>   | isJust m = return x
>   | otherwise = liftM qualify (renameVar env x')
>   where (m,x') = splitQualIdent x

\end{verbatim}
The renaming pass simply descends into the structure of the abstract
syntax tree and renames all expression variables.
\begin{verbatim}

> rename :: [TopDecl] -> [TopDecl]
> rename ds = run (mapM renameTopDecl ds)

> renameGoal :: Goal -> Goal
> renameGoal (Goal p e ds) = run $
>   do
>     env' <- bindVars emptyEnv ds
>     ds' <- mapM (renameDecl env') ds
>     e' <- renameExpr env' e
>     return (Goal p e' ds')

> renameTopDecl :: TopDecl -> RenameState TopDecl
> renameTopDecl (BlockDecl d) = liftM BlockDecl (renameDecl emptyEnv d)
> renameTopDecl d = return d

> renameDecl :: RenameEnv -> Decl -> RenameState Decl
> renameDecl env (InfixDecl p fix pr ops) =
>   liftM (InfixDecl p fix pr) (mapM (renameVar env) ops)
> renameDecl env (TypeSig p fs ty) =
>   liftM (flip (TypeSig p) ty) (mapM (renameVar env) fs)
> renameDecl env (EvalAnnot p fs ev) =
>   liftM (flip (EvalAnnot p) ev) (mapM (renameVar env) fs)
> renameDecl env (FunctionDecl p f eqs) =
>   do
>     f' <- renameVar env f
>     liftM (FunctionDecl p f') (mapM (renameEqn f' env) eqs)
> renameDecl env (ForeignDecl p cc ie f ty) =
>   liftM (flip (ForeignDecl p cc ie) ty) (renameVar env f)
> renameDecl env (PatternDecl p t rhs) =
>   liftM2 (PatternDecl p) (renameConstrTerm env t) (renameRhs env rhs)
> renameDecl env (FreeDecl p vs) =
>   liftM (FreeDecl p) (mapM (renameVar env) vs)

\end{verbatim}
Note that the root of the left hand side term of an equation must be
equal to the name of the function declaration. This means that we must
not rename this identifier in the same environment as its arguments.
\begin{verbatim}

> renameEqn :: Ident -> RenameEnv -> Equation -> RenameState Equation
> renameEqn f env (Equation p lhs rhs) =
>   do
>     env' <- bindVars env lhs
>     liftM2 (Equation p) (renameLhs f env' lhs) (renameRhs env' rhs)

> renameLhs :: Ident -> RenameEnv -> Lhs -> RenameState Lhs
> renameLhs f env (FunLhs _ ts) =
>   liftM (FunLhs f) (mapM (renameConstrTerm env) ts)
> renameLhs f env (OpLhs t1 _ t2) =
>   liftM2 (flip OpLhs f) (renameConstrTerm env t1) (renameConstrTerm env t2)
> renameLhs f env (ApLhs lhs ts) =
>   liftM2 ApLhs (renameLhs f env lhs) (mapM (renameConstrTerm env) ts)

> renameRhs :: RenameEnv -> Rhs -> RenameState Rhs
> renameRhs env (SimpleRhs p e ds) =
>   do
>     env' <- bindVars env ds
>     ds' <- mapM (renameDecl env') ds
>     e' <- renameExpr env' e
>     return (SimpleRhs p e' ds')
> renameRhs env (GuardedRhs es ds) =
>   do
>     env' <- bindVars env ds
>     ds' <- mapM (renameDecl env') ds
>     es' <- mapM (renameCondExpr env') es
>     return (GuardedRhs es' ds')

> renameLiteral :: RenameEnv -> Literal -> RenameState Literal
> renameLiteral _ (Char c) = return (Char c)
> renameLiteral env (Int x i) = liftM (flip Int i) (renameVar env x)
> renameLiteral _ (Float f) = return (Float f)
> renameLiteral _ (String s) = return (String s)

> renameConstrTerm :: RenameEnv -> ConstrTerm -> RenameState ConstrTerm
> renameConstrTerm env (LiteralPattern l) =
>   liftM LiteralPattern (renameLiteral env l)
> renameConstrTerm env (NegativePattern op l) =
>   liftM (NegativePattern op) (renameLiteral env l)
> renameConstrTerm env (VariablePattern x) =
>   liftM VariablePattern (renameVar env x)
> renameConstrTerm env (ConstructorPattern c ts) =
>   liftM (ConstructorPattern c) (mapM (renameConstrTerm env) ts)
> renameConstrTerm env (InfixPattern t1 op t2) =
>   liftM2 (flip InfixPattern op) (renameConstrTerm env t1)
>                                 (renameConstrTerm env t2)
> renameConstrTerm env (ParenPattern t) =
>   liftM ParenPattern (renameConstrTerm env t)
> renameConstrTerm env (TuplePattern ts) =
>   liftM TuplePattern (mapM (renameConstrTerm env) ts)
> renameConstrTerm env (ListPattern ts) =
>   liftM ListPattern (mapM (renameConstrTerm env) ts)
> renameConstrTerm env (AsPattern x t) =
>   liftM2 AsPattern (renameVar env x) (renameConstrTerm env t)
> renameConstrTerm env (LazyPattern t) =
>   liftM LazyPattern (renameConstrTerm env t)

> renameCondExpr :: RenameEnv -> CondExpr -> RenameState CondExpr
> renameCondExpr env (CondExpr p g e) =
>   liftM2 (CondExpr p) (renameExpr env g) (renameExpr env e)

> renameExpr :: RenameEnv -> Expression -> RenameState Expression
> renameExpr env (Literal l) = liftM Literal (renameLiteral env l)
> renameExpr env (Variable x) = liftM Variable (renameQual env x)
> renameExpr _ (Constructor c) = return (Constructor c)
> renameExpr env (Paren e) = liftM Paren (renameExpr env e)
> renameExpr env (Typed e ty) = liftM (flip Typed ty) (renameExpr env e)
> renameExpr env (Tuple es) = liftM Tuple (mapM (renameExpr env) es)
> renameExpr env (List es) = liftM List (mapM (renameExpr env) es)
> renameExpr env (ListCompr e qs) =
>   do
>     (env',qs') <- mapAccumM renameStmt env qs
>     e' <- renameExpr env' e
>     return (ListCompr e' qs')
> renameExpr env (EnumFrom e) = liftM EnumFrom (renameExpr env e)
> renameExpr env (EnumFromThen e1 e2) =
>   liftM2 EnumFromThen (renameExpr env e1) (renameExpr env e2)
> renameExpr env (EnumFromTo e1 e2) =
>   liftM2 EnumFromTo (renameExpr env e1) (renameExpr env e2)
> renameExpr env (EnumFromThenTo e1 e2 e3) =
>   liftM3 EnumFromThenTo (renameExpr env e1)
>                         (renameExpr env e2)
>                         (renameExpr env e3)
> renameExpr env (UnaryMinus op e) = liftM (UnaryMinus op) (renameExpr env e)
> renameExpr env (Apply e1 e2) =
>   liftM2 Apply (renameExpr env e1) (renameExpr env e2)
> renameExpr env (InfixApply e1 op e2) =
>   liftM3 InfixApply (renameExpr env e1) (renameOp env op) (renameExpr env e2)
> renameExpr env (LeftSection e op) =
>   liftM2 LeftSection (renameExpr env e) (renameOp env op)
> renameExpr env (RightSection op e) =
>   liftM2 RightSection (renameOp env op) (renameExpr env e)
> renameExpr env (Lambda ts e) =
>   do
>     env' <- bindVars env ts
>     liftM2 Lambda (mapM (renameConstrTerm env') ts) (renameExpr env' e)
> renameExpr env (Let ds e) =
>   do
>     env' <- bindVars env ds
>     liftM2 Let (mapM (renameDecl env') ds) (renameExpr env' e)
> renameExpr env (Do sts e) =
>   do
>     (env',sts') <- mapAccumM renameStmt env sts
>     e' <- renameExpr env' e
>     return (Do sts' e')
> renameExpr env (IfThenElse e1 e2 e3) =
>   liftM3 IfThenElse (renameExpr env e1)
>                     (renameExpr env e2)
>                     (renameExpr env e3)
> renameExpr env (Case e as) =
>   liftM2 Case (renameExpr env e) (mapM (renameAlt env) as)

> renameOp :: RenameEnv -> InfixOp -> RenameState InfixOp
> renameOp env (InfixOp op) = liftM InfixOp (renameQual env op)
> renameOp _ (InfixConstr op) = return (InfixConstr op)

> renameStmt :: RenameEnv -> Statement -> RenameState (RenameEnv,Statement)
> renameStmt env (StmtExpr e) =
>   do
>     e' <- renameExpr env e
>     return (env,StmtExpr e')
> renameStmt env (StmtDecl ds) =
>   do
>     env' <- bindVars env ds
>     ds' <- mapM (renameDecl env') ds
>     return (env',StmtDecl ds')
> renameStmt env (StmtBind t e) =
>   do
>     e' <- renameExpr env e
>     env' <- bindVars env t
>     t' <- renameConstrTerm env' t
>     return (env',StmtBind t' e')

> renameAlt :: RenameEnv -> Alt -> RenameState Alt
> renameAlt env (Alt p t rhs) =
>   do
>     env' <- bindVars env t
>     liftM2 (Alt p) (renameConstrTerm env' t) (renameRhs env' rhs)

\end{verbatim}