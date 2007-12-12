% -*- LaTeX -*-
% $Id: DTransform.lhs 2557 2007-12-12 18:46:29Z wlux $
%
% Copyright (c) 2001-2002, Rafael Caballero
% Copyright (c) 2003-2007, Wolfgang Lux
%
% 2002/04/10 19:00:00 Added emptyNode as constructor in type cTree
\nwfilename{DTransform.lhs}

\section{Transforming Intermediate Representation for Debugging}\label{sec:dtrans}

The purpose of this module is to convert the intermediate representation of 
a program $P$, of type {\tt Module} into the intermediate representation of a 
transformed program $P'$. 
$P'$ corresponds to the transformation of $P$ for debugging purposes. Each 
function in $P'$ computes the same values as its corresponding function in $P$,
but in addition it also returns a suitable {\em Computation Tree} representing
the computation.

\begin{verbatim}

> module DTransform(dTransform, dAddMain) where
> import IL
> import List
> import Maybe
> import PredefIdent

\end{verbatim}

All the new and auxiliary names in the transformed module will have 
{\tt debugPrefix}
prefix to avoid conflicts with user-names. Auxiliary data types and functions
will be imported from the debug prelude, whose name is defined below, and that
will be imported by all the transformed modules.

\begin{verbatim}

> debugPrefix,debugFunctionName,debugIOFunctionName :: String
> debugPrefix         = "_debug#"
> debugFunctionName   =  "startDebugging"
> debugIOFunctionName =  "startIODebugging"


\end{verbatim}

Next is the principal  function of the module. The argument function
\texttt{trusted} returns \texttt{True} for all functions of the module
that must be trusted. These functions will return empty nodes as
computation trees, but still can include some useful trees as
children.

\begin{verbatim}

> dTransform :: (QualIdent -> Bool) -> Module -> Module
> dTransform trusted (Module m is ds) =
>   Module m (debugPreludeMIdent:is) (debugDecls m trusted ds)

\end{verbatim}

The debugging transformation is applied independently to each
declaration in the module. Type declarations are not changed by the
transformation except for the types of higher order arguments of data
constructors, which are transformed in order to ensure a type correct
transformed program. In addition, auxiliary functions are introduced
to handle partial applications of the data constructors. Function
declarations are changed by the program transformation and auxiliary
functions are introduced for their partial applications, too. Finally,
foreign function declarations cannot be transformed at all, but a
wrapper function pairing the result of the foreign function with a
suitable computation tree is introduced for each foreign function.
Auxiliary functions for partial applications of the foreign functions
are provided as well.

A special case handles the selector functions introduced by the
pattern binding update strategy (see p.~\pageref{pattern-binding} in
Sect.~\ref{pattern-binding}). These functions are not transformed at
all.

\begin{verbatim}

> data SymbolType = IsFunction | IsConstructor deriving (Eq,Show)

> debugDecls :: ModuleIdent -> (QualIdent -> Bool) -> [Decl] -> [Decl]
> debugDecls m trusted ds = 
>   concatMap (generateAuxFuncs m) (nub (typesPredefined ds)) ++
>   concatMap (debugDecl m trusted) ds

> debugDecl :: ModuleIdent -> (QualIdent -> Bool) -> Decl -> [Decl]
> debugDecl m _ (DataDecl tc n cs) = DataDecl tc n cs' : concat ds'
>   where (cs',ds') = unzip (map (debugConstrDecl m ty0) cs)
>         ty0 = TypeConstructor tc (map TypeVariable [0..n-1])
> debugDecl m _ (TypeDecl tc n ty) = [TypeDecl tc n (transformType' ty)]
> debugDecl m trusted (FunctionDecl f vs ty e)
>   | isQSelectorId f = [FunctionDecl f vs ty e]
>   | otherwise =
>       generateAuxFuncs m (f,IsFunction,length vs,ty) ++
>       [debugFunction m trusted f vs ty e]
> debugDecl m _ (ForeignDecl f cc s ty) =
>   generateAuxFuncs m (f,IsFunction,n',ty) ++
>   generateForeign m f cc s n' ty
>   where n = typeArity ty
>         n' = if isIOType (resultType ty) then n + 1 else n

> debugConstrDecl :: ModuleIdent -> Type -> ConstrDecl -> (ConstrDecl,[Decl])
> debugConstrDecl m ty0 (ConstrDecl c tys) =
>   (ConstrDecl c (map transformType' tys),
>    generateAuxFuncs m (c,IsConstructor,length tys,ty))
>   where ty = normalizeType (foldr TypeArrow ty0 tys)

> normalizeType :: Type -> Type
> normalizeType ty = rename (nub (tvars ty)) ty
>   where rename tvs (TypeConstructor c tys) =
>           TypeConstructor c (map (rename tvs) tys)
>         rename tvs (TypeVariable tv) =
>           TypeVariable (fromJust (elemIndex tv tvs))
>         rename tvs (TypeArrow ty1 ty2) =
>           TypeArrow (rename tvs ty1) (rename tvs ty2)
>         tvars (TypeConstructor _ tys) = concatMap tvars tys
>         tvars (TypeVariable tv) = [tv]
>         tvars (TypeArrow ty1 ty2) = tvars ty1 ++ tvars ty2

\end{verbatim}


Some auxiliary functions widely used throughout the module.

%Function that builds a qualified name from the name of the module and a string 
%standing for the name we are going to represent.
\begin{verbatim}

> newIdName :: Int -> String -> Ident
> newIdName n name = mkIdent (debugPrefix++name++show n)

> debugQualPreludeName :: String -> QualIdent
> debugQualPreludeName name = qualifyWith debugPreludeMIdent (mkIdent name)

> debugFunctionqId :: QualIdent
> debugFunctionqId = debugQualPreludeName debugFunctionName

> debugIOFunctionqId :: QualIdent
> debugIOFunctionqId = debugQualPreludeName debugIOFunctionName

> debugRenameId :: String -> Ident -> Ident
> debugRenameId suffix ident =
>   renameIdent (mkIdent (debugPrefix ++ name ident ++ suffix)) (uniqueId ident)

> debugRenameqId :: String -> ModuleIdent -> QualIdent -> QualIdent
> debugRenameqId suffix mIdent qIdent =
>   qualifyWith (maybe mIdent id mIdent') (debugRenameId suffix ident')
>   where (mIdent',ident') = splitQualIdent qIdent

\end{verbatim}

Qualified data types representing some useful types in the transformed program:
{\tt [a], (a,b), Char, [Char], CTree} and {\tt [Ctree]}. Also function for
constructing expressions of the form (a,b) and the name of function 
{\tt clean}.

\begin{verbatim}

> typeCons :: Type
> typeCons = TypeArrow (TypeVariable 0) 
>               (TypeArrow (debugTypeList (TypeVariable 0))  
>                          (debugTypeList (TypeVariable 0)))

> typeTuple :: Int -> Type
> typeTuple n = foldr TypeArrow (debugTypeTuple ts) ts
>   where ts = [TypeVariable i | i <- [0 .. n - 1]]

> debugTypeList :: Type -> Type
> debugTypeList t = TypeConstructor qListId [t]

> debugTypePair :: Type -> Type -> Type
> debugTypePair a b = TypeConstructor qPairId [a,b]

> debugTypeTuple :: [Type] -> Type
> debugTypeTuple ts = TypeConstructor (qTupleId (length ts)) ts

> debugTypeChar,debugTypeString:: Type
> debugTypeChar   = TypeConstructor qCharId []
> debugTypeString = debugTypeList debugTypeChar


> debugTypeCTree,debugTypeLCTree,debugTypeCleanTree,debugTypeLCleanTree:: Type
> debugTypeCTree   = TypeConstructor (debugQualPreludeName "CTree") []
> debugTypeLCTree  = debugTypeList debugTypeCTree
> debugTypeCleanTree = debugTypePair debugTypeString debugTypeCTree
> debugTypeLCleanTree = debugTypeList debugTypeCleanTree

> debugTypeMainAux :: Type
> debugTypeMainAux = TypeArrow (debugTypePair (TypeVariable 0) debugTypeCTree)
>                              (TypeConstructor qSuccessId [])



> qPairId :: QualIdent
> qPairId = qTupleId 2

> debugNil :: Expression
> debugNil = Constructor qNilId 0

> debugBuildPairExp :: Expression -> Expression -> Expression
> debugBuildPairExp e1 e2 = Apply (Apply (Constructor qPairId 2) e1) e2


> debugClean :: QualIdent 
> debugClean  = debugQualPreludeName "clean"


> dEvalApply :: Expression -> Expression
> dEvalApply = Apply (Function (debugQualPreludeName "dEval") 1)


> void :: Expression
> void = Constructor (debugQualPreludeName "CTreeVoid") 0

> emptyNode :: Expression -> Expression
> emptyNode children =
>   createApply (Constructor (debugQualPreludeName "EmptyCTreeNode") 1)
>               [children]


> debugBuildList :: [Expression] -> Expression
> debugBuildList l = foldr Apply debugNil (map (Apply cons) l)
>   where cons = Constructor qConsId 2


> node :: Expression -> Expression -> Expression -> Expression -> Expression
>      -> Expression
> node name args result number children =
>   createApply (Constructor (debugQualPreludeName "CTreeNode") 5)
>               [name, args, result, number, children]

\end{verbatim}

The newMain is only added if we are in the module main. 
It will start the debugging process.

Its definition depends on the goal's type. If the goal's type is
\texttt{IO}~$t$, the new main function simply executes the transformed
goal under control of the debugger.

\begin{verbatim}


main.main = DebugPrelude.startIODebugging main._debug#main

\end{verbatim}

Otherwise, the goal must be solved using encapsulated search and
navigation then allows picking a wrong solution. In order to make this
work, the transformed goal function must be converted into a form that
is suitable as argument to the encapsulated search primitive
\texttt{try}. Therefore, we use the following definition for the new
main function.

\begin{verbatim}


main.main = DebugPrelude.startDebugging 
                (\(x,ct)-> let (r,ct') = main._debug#main in x=:=r &> ct=:=ct')

\end{verbatim}

We have to introduce an auxiliary function for the lambda in the intermediate code.

\begin{verbatim}

> dAddMain :: Ident -> Module -> Module
> dAddMain goalId (Module m is ds) = Module m is (fMain ++ ds)
>   where (arity,ty) = head [(length lVars,ty) | FunctionDecl f lVars ty _ <- ds, f == debugOldMainId]
>         fMain = if isIO
>                 then newMainIO m goalId arity
>                 else newMain m goalId arity
>         debugOldMainId = qualifyWith m (debugRenameId "" goalId)
>         debugResultType (TypeConstructor _ [ty,_]) = ty
>         isIO =
>           case arity of
>             0 -> isIOType (debugResultType ty)
>             1 -> isIOType ty
>             _ -> False

> newMainIO :: ModuleIdent -> Ident -> Int -> [Decl]
> newMainIO m f n = [fMain]
>       where 
>       fMain = FunctionDecl fId [] fType fBody
>       fId   = qualifyWith m f
>       fType = TypeConstructor qIOId [TypeConstructor qUnitId []]
>       fApp  = if n==0
>               then Function debugOldMainId n
>               else debugBuildPairExp (Function debugOldMainId n) void
>       fBody = Apply (Function debugIOFunctionqId 2) fApp
>       debugOldMainId = qualifyWith m (debugRenameId "" f)

> newMain :: ModuleIdent -> Ident -> Int -> [Decl]
> newMain m f n = [fMain,auxMain]
>       where 
>       fMain = FunctionDecl fId [] fType fBody
>       fId   = qualifyWith m f
>       fType = TypeConstructor qIOId [TypeConstructor qUnitId []]
>       fBody = Apply (Function debugFunctionqId 1) (Function debugAuxMainId 1)
>       fType' = debugTypeMainAux
>       r   = mkIdent "r"
>       ct' = mkIdent "ct'"
>       x   = mkIdent "x"
>       ct   = mkIdent "ct"
>       param  = mkIdent "x_ct"
>       eq1 = createApply equalFunc  [Variable x, Variable r]
>       eq2 = createApply equalFunc  [Variable ct, Variable ct']        
>       equalFunc = Function (qualifyWith preludeMIdent (mkIdent "=:=")) 2
>       seqAndFunc = Function (qualifyWith preludeMIdent (mkIdent "&>")) 2
>       expression =  createApply seqAndFunc [eq1,eq2]
>       alt'     = Alt (ConstructorPattern qPairId [x,ct]) expression
>       caseExpr = Case Flex (Variable param) [alt']
>       alt      = Alt (ConstructorPattern qPairId [r,ct']) caseExpr
>       fApp     = if n == 0
>                  then Function debugOldMainId n
>                  else debugBuildPairExp (Function debugOldMainId n) void
>       fBody'   = Case Rigid  fApp [alt]
>       auxMain = FunctionDecl debugAuxMainId [param] fType' fBody'
>       debugOldMainId = qualifyWith m (debugRenameId "" f)
>       debugAuxMainId = qualifyWith m (debugRenameId "#Aux" f)


\end{verbatim}
The implementation of foreign functions is not known and must be
trusted. For first order foreign functions this means that the
transformed function simply should pair the result of the foreign
function with a void computation tree. Therefore, given a foreign
function $f :: \tau_1 \rightarrow \dots \rightarrow \tau_n \rightarrow
\tau$, the debugging transformation just adds an auxiliary function
$f' \, x_1 \dots x_n = (f \, x_1 \dots x_n, \texttt{Void})$ to the
program. First order foreign functions in the \texttt{IO} monad are
handled similarly, except that the computation tree is lifted into the
\texttt{IO} monad. Thus, given a foreign function $f :: \tau_1
\rightarrow \dots \rightarrow \tau_n \rightarrow \texttt{IO}\,\tau$,
the transformation defines an auxiliary function $f' \, x_1 \dots x_n
= f \, x_1 \dots x_n \;\texttt{>>=} \; \texttt{return'}$ where the
auxiliary function \texttt{return' x = (x, Void)} is defined in module
\texttt{DebugPrelude}. As a minor optimization, using the monad law
$\texttt{return}\,x \; \texttt{>>=} \; k \equiv k\,x$, we transform
the \texttt{return} primitive directly into \texttt{return'}.

Higher order foreign functions like the encapsulated search primitive
\texttt{try} or the monadic bind operator \texttt{(>>=)} cannot be
handled in that way since they can invoke arbitrary computations. In
order to integrate such functions into the program transformation
approach, suitable wrapper functions, which collect the computation
trees of the subcomputations performed by the foreign function and
return them along with the function's result, must be defined in
module \texttt{DebugPrelude}. These wrappers are then used in the
transformed program instead of the original function. Fortunately,
there is only a small number of such primitives making this approach
feasible.

\textbf{Note}: The code below assumes that the wrapper functions for
higher order primitives defined in \texttt{DebugPrelude} indeed have
the same arity as the original primitives.
\begin{verbatim}

> generateForeign :: ModuleIdent -> QualIdent -> CallConv -> String -> Int
>                 -> Type -> [Decl]
> generateForeign m f cc s n ty = FunctionDecl f' vs ty' e : ds
>   where f' = changeFunctionqId m f
>         vs = map (mkIdent . ("_"++) . show) [0..n-1]
>         ty' = transformType n ty
>         (e,ds) = debugForeign f cc s n (map Variable vs) ty

> debugForeign :: QualIdent -> CallConv -> String -> Int -> [Expression] -> Type
>              -> (Expression,[Decl])
> debugForeign f cc s n vs ty =
>   case foreignWrapper cc s of
>     Just f' -> (createApply (Function (debugQualPreludeName f') n) vs,[])
>     Nothing -> (debugForeign1 s ty (Function f n) vs,[ForeignDecl f cc s ty])

> debugForeign1 :: String -> Type -> Expression -> [Expression] -> Expression
> debugForeign1 s ty f vs
>   | any isFunctType (argumentTypes ty) =
>       error ("debugForeign: unknown higher order primitive " ++ s)
>   | isIOType (resultType ty) =
>       createApply preludeBind [createApply f (init vs),debugReturn,last vs]
>   | otherwise = debugBuildPairExp (createApply f vs) void
>   where preludeBind = Function (qualifyWith preludeMIdent (mkIdent ">>=")) 3
>         debugReturn = Function (debugQualPreludeName "return'") 2
>         isFunctType ty = isArrowType ty || isIOType ty

> foreignWrapper :: CallConv -> String -> Maybe String
> foreignWrapper Primitive s
>   | s=="try"             = Just "try'"
>   | s=="return"          = Just "return'"
>   | s==">>="             = Just "bind'"
>   | s==">>"              = Just "bind_'"
>   | s=="catch"           = Just "catch'"
>   | s=="fixIO"           = Just "fixIO'"
>   | s=="encapsulate"     = Just "encapsulate'"
>   | s=="unsafePerformIO" = Just "unsafePerformIO'"
>   | otherwise            = Nothing
> foreignWrapper CCall   _ = Nothing
> foreignWrapper RawCall _ = Nothing

\end{verbatim}

Auxiliary functions are introduced to deal with higher order parameter
applications. In particular, the transformation introduces $n-1$
auxiliary functions $f'_0, \dots, f'_{n-2}$ for a (foreign) function
$f$ with arity $n$. These functions are necessary in order to make the
transformed program type correct and are defined by equations $f'_i\,x
= (f'_{i+1}\,x, \texttt{Void})$, where $f'$ is used instead of
$f'_{n-1}$. For the same reason, the transformation introduces $n$
auxiliary functions $c'_0, \dots, c'_{n-1}$ for each data constructor
$c$ with arity $n$. Their definitions are similar to those of the
auxiliary functions for transformed functions except for using $c$ in
place of $c'_n$.

The next function gets the current module identifier, a qualified
identifier, a value indicating whether the identifier denotes a
function or a constructor, its arity \texttt{n}, and its type, and
generates the new auxiliary functions.

\begin{verbatim}

> generateAuxFuncs :: ModuleIdent -> (QualIdent,SymbolType,Int,Type) -> [Decl]
> generateAuxFuncs m (f,IsFunction,n,ty) =
>   map (generateAuxFunc m f ty (Function f n)) [0..n-2]
> generateAuxFuncs m (c,IsConstructor,n,ty) =
>   map (generateAuxFunc m c ty (Constructor c n)) [0..n-1]

> generateAuxFunc :: ModuleIdent -> QualIdent -> Type -> Expression -> Int
>                 -> Decl
> generateAuxFunc m f ty e i = FunctionDecl f' vs ty' e'
>   where f' = qidAuxiliaryFunction m f i
>         vs = map (mkIdent . ("_"++) . show) [0..i]
>         ty' = transformType (i+1) ty
>         app = debugFirstPhase m (createApply e (map Variable vs))
>         e' = debugBuildPairExp app void

> qidAuxiliaryFunction :: ModuleIdent -> QualIdent -> Int -> QualIdent
> qidAuxiliaryFunction m f n = debugRenameqId ('#':show n) m f

> extractApply :: Expression -> [Expression] -> (Expression,[Expression])
> extractApply (Apply e1 e2) l = extractApply e1 (e2:l)
> extractApply e1 l = (e1,l)

> createApply :: Expression -> [Expression] -> Expression
> createApply exp lExp = foldl Apply exp lExp

\end{verbatim}

The function \texttt{transformType} transforms the type
$\tau_1 \rightarrow \dots \rightarrow \tau_n \rightarrow \tau$
of a function with arity $n$ into
$\tau'_1 \rightarrow \dots \rightarrow \tau'_n \rightarrow (\tau',\texttt{CTree})$.
The arity $n$ is passed as first argument to \texttt{transformType}.

The function \texttt{transformType'} implements the basic
transformation of types:
\begin{displaymath}
  \begin{array}{rcll}
    \alpha' &=& \alpha \\
    \texttt{IO}\:\tau &=& \texttt{IO}\:(\tau',\texttt{CTree}) \\
    C\,\tau_1\dots\tau_n &=& C\,\tau'_1\dots\tau'_n & (C\not=\texttt{IO}) \\
    (\mu \rightarrow \nu)' &=& \mu' \rightarrow (\nu',\texttt{CTree})
  \end{array}
\end{displaymath}
Note the special case for \texttt{IO}, which is necessary in order to
implement debugging for actions. Recall that $\texttt{IO}\:\tau$ is
equivalent to $\textit{World} \rightarrow (\tau,\textit{World})$ for
some abstract representation \textit{World} of the state of the
external world. With the standard rules, this type would be
transformed into
$\textit{World} \rightarrow ((\tau',\textit{World}), \texttt{CTree})$.
Since this is no longer an instance of \texttt{IO}, this would mean
that we cannot use the standard runtime system primitives in order to
implement the primitives transformed for debugging. Therefore, we
prefer using the isomorphic type
$\textit{World} \rightarrow ((\tau',\texttt{CTree}), \textit{World})$
for transforming the type \texttt{IO}, giving rise to the special case
for \texttt{IO}.
\begin{verbatim}

> transformType :: Int -> Type -> Type
> transformType 0 fType = debugTypePair (transformType' fType) debugTypeCTree
> transformType _ fType@(TypeArrow ty1 (TypeConstructor tc [ty2,ty3]))
>   | tc == qPairId && ty1 == TypeConstructor qWorldId [] && ty1 == ty3 =
>       transformType' fType
> transformType n (TypeArrow type1 type2) =
>   TypeArrow (transformType' type1) (transformType (n-1) type2)
> transformType _ fType = transformType' fType

> transformType' :: Type -> Type
> transformType' (TypeArrow ty1 (TypeConstructor tc [ty2,ty3]))
>   | tc == qPairId && ty1 == TypeConstructor qWorldId [] && ty1 == ty3 =
>       TypeArrow ty1 (TypeConstructor tc [transformType 0 ty2,ty3])
> transformType' t@(TypeArrow type1 type2) = transformType 1 t
> transformType' (TypeConstructor tc lTypes)
>   | tc == qIOId = TypeConstructor tc [transformType 0 (head lTypes)]
>   | otherwise = TypeConstructor tc (map transformType' lTypes)
> transformType' (TypeVariable v) = TypeVariable v

> typeArity :: Type -> Int
> typeArity ty = length (argumentTypes ty)

> argumentTypes :: Type -> [Type]
> argumentTypes (TypeArrow ty1 (TypeConstructor tc [ty2,ty3]))
>   | tc == qPairId && ty1 == TypeConstructor qWorldId [] && ty1 == ty3 = []
> argumentTypes (TypeArrow ty1 ty2) = ty1 : argumentTypes ty2
> argumentTypes _                   = []

> resultType :: Type -> Type
> resultType (TypeArrow ty1 (TypeConstructor tc [ty2,ty3]))
>   | tc == qPairId && ty1 == TypeConstructor qWorldId [] && ty1 == ty3 =
>       TypeConstructor qIOId [ty2]
> resultType (TypeArrow _ ty) = resultType ty
> resultType ty               = ty

> isIOType :: Type -> Bool
> isIOType (TypeArrow ty1 (TypeConstructor tc [_,ty2])) =
>   tc == qPairId && ty1 == TypeConstructor qWorldId [] && ty1 == ty2
> isIOType (TypeConstructor tc [_]) = tc == qIOId
> isIOType _                        = False

> isArrowType :: Type -> Bool
> isArrowType (TypeArrow ty1 (TypeConstructor tc [_,ty2])) =
>   not (tc == qPairId && ty1 == TypeConstructor qWorldId [] && ty1 == ty2)
> isArrowType (TypeArrow _ _) = True
> isArrowType _               = False

> qWorldId :: QualIdent
> qWorldId = qualify (mkIdent "World")

\end{verbatim}

The transformation must add auxiliary functions for all partial applications
of the list constructor and tuple constructors which are used in the module.
These constructors are defined implicitly in every module, therefore we collect
these definitions here.
\begin{verbatim}

> type DebugTypeList = [(QualIdent,SymbolType,Int,Type)]

> typesPredefined :: [Decl] -> DebugTypeList
> typesPredefined ds = nub (foldr typesBody [] ds)

> typesBody :: Decl -> DebugTypeList -> DebugTypeList
> typesBody (DataDecl _ _ _) = id
> typesBody (TypeDecl _ _ _) = id
> typesBody (FunctionDecl _ _ _ e) = typesExpr e
> typesBody (ForeignDecl _ _ _ _) = id

> typesExpr :: Expression -> DebugTypeList -> DebugTypeList
> typesExpr (Literal _) env = env
> typesExpr (Variable _) env = env
> typesExpr (Function _ _) env = env
> typesExpr (Constructor qId n) env =
>   if idModule == Nothing && n > 0 then env' else env
>   where (idModule,ident) = splitQualIdent qId
>         env' = (qId,IsConstructor,n,debugTypePredef ident n) : env
> typesExpr (Apply e1 e2) env = typesExpr e1 (typesExpr e2 env)
> typesExpr (Case _ e alts) env = typesExpr e (foldr typesAlt env alts)
>   where typesAlt (Alt _ e) = typesExpr e
> typesExpr (Or e1 e2) env = typesExpr e1 (typesExpr e2 env)
> typesExpr (Exist _ e) env = typesExpr e env
> typesExpr (Let (Binding _ e1) e2) env = typesExpr e1 (typesExpr e2 env)
> typesExpr (Letrec binds e) env = foldr typesBinding (typesExpr e env) binds
>   where typesBinding (Binding _ e) = typesExpr e

> debugTypePredef :: Ident -> Int -> Type
> debugTypePredef ident n
>   | ident == consId && n == 2 = typeCons
>   | isTupleId ident = typeTuple n
>   | otherwise = error ("debugTypePredef: " ++ show ident ++ "/" ++ show n)

\end{verbatim}

The transformation of user defined functions is performed in two
phases.

\begin{verbatim}

> debugFunction :: ModuleIdent -> (QualIdent -> Bool) -> QualIdent -> [Ident]
>               -> Type -> Expression -> Decl
> debugFunction m trusted f vs ty e = FunctionDecl f' vs ty' e'
>   where f' = changeFunctionqId m f
>         ty' = transformType (length vs) ty
>         e' = debugSecondPhase f (trusted f) vs ty' (debugFirstPhase m e)

> changeFunctionqId :: ModuleIdent -> QualIdent -> QualIdent
> changeFunctionqId m f = debugRenameqId "" m f

\end{verbatim}

The first phase of the transformation process changes the names of all
function and partial constructor applications.

\begin{verbatim}

> debugFirstPhase :: ModuleIdent -> Expression -> Expression
> debugFirstPhase m e = firstPhase m 0 e

> class FirstPhase a where
>   firstPhase :: ModuleIdent -> Int -> a -> a

> instance FirstPhase a => FirstPhase [a] where
>   firstPhase m d = map (firstPhase m d)

> instance FirstPhase Expression where
>   firstPhase _ _ (Literal l) = Literal l
>   firstPhase _ _ (Variable v) = Variable v
>   firstPhase m d (Function f n)
>     | isQSelectorId f = Function f n
>     | d < n-1         = Function (qidAuxiliaryFunction m f d) (d+1)
>     | otherwise       = Function (changeFunctionqId m f) n
>   firstPhase m d (Constructor c n)
>     | d < n     = Function (qidAuxiliaryFunction m c d) (d+1)
>     | otherwise = Constructor c n
>   firstPhase m d (Apply e1 e2) =
>     Apply (firstPhase m (d+1) e1) (firstPhase m 0 e2)
>   firstPhase m _ (Case eval expr lAlts) =
>     Case eval (firstPhase m 0 expr) (firstPhase m 0 lAlts)
>   firstPhase m _ (Or e1 e2) = Or (firstPhase m 0 e1) (firstPhase m 0 e2)
>   firstPhase m d (Exist ident e) = Exist ident (firstPhase m d e)
>   firstPhase m d (Let binding e) =
>     Let (firstPhase m 0 binding) (firstPhase m d e)
>   firstPhase m d (Letrec lbind e) =
>     Letrec (firstPhase m 0 lbind) (firstPhase m d e)

> instance FirstPhase Alt where
>   firstPhase m d (Alt term expr) = Alt term (firstPhase m d expr)

> instance FirstPhase Binding where
>   firstPhase m d (Binding ident expr) = Binding ident (firstPhase m d expr)

\end{verbatim}

The second phase transforms the rules of the original functions. All
partial applications of functions and constructors have been replaced
by auxiliary functions. Also, the type of the function has been
transformed.
We only need:
\begin{itemize}
\item Introduce local definitions replacing function calls.
\item Guess if the function is a lifted function, in order to build an 
      appropriate name and include only the function variables in the node.
\end{itemize}

A special cases handles $\eta$-expanded functions with result type
\texttt{IO}~$t$. According to the special transformation rule that
applies to the \texttt{IO} type (see notes on \texttt{transformType}),
we must not add a computation tree to the result of the transformed
function, but rather make the transformed function return the
computation tree together with its result in the \texttt{IO} monad.
Thus, an $\eta$-expanded \texttt{IO} function $f \, x_1 \dots x_{n-1}
\, x_n = e \, x_{n}$ is transformed into $f' \, x_1 \dots x_{n-1} \,
x_n = \texttt{performIO} \, e' \, x_n$ where $e'$ is the transformed
expression derived for $e$ and the auxiliary function
\texttt{performIO}, which is defined in \texttt{DebugPrelude}, takes
care of evaluating the transformed monadic action and returning a
suitable computation tree. Its definition is
\begin{verbatim}
  performIO (m,t1) = m >>= \(r,t2) -> return (r, ioCTree t1 (r,t2))
\end{verbatim}
The auxiliary function \texttt{ioCTree}, which is also defined in
\texttt{DebugPrelude}, simply adds the pair \texttt{(dEval r,t2)} to
the list of subcomputations of the computation tree \texttt{t1}.
\begin{verbatim}

> debugSecondPhase :: QualIdent -> Bool -> [Ident] -> Type -> Expression
>                  -> Expression
> debugSecondPhase f trust vs ty e
>   | isIOType (resultType ty) && length vs > typeArity ty =
>       newLocalDeclarationsEtaIO f trust vs e
>   | otherwise = newLocalDeclarations f trust vs e

> newLocalDeclarations :: QualIdent -> Bool -> [Ident] -> Expression
>                      -> Expression
> newLocalDeclarations f trust vs e = fst (newBindings createNode e 0 [])
>   where createNode = if trust then createEmptyNode else createTree f vs

> newLocalDeclarationsEtaIO :: QualIdent -> Bool -> [Ident] -> Expression
>                           -> Expression
> newLocalDeclarationsEtaIO f trust vs e =
>   etaExpandIO (newLocalDeclarations f trust (init vs) e') v
>   where (e',v) = etaReduceIO e

> etaExpandIO :: Expression -> Expression -> Expression
> etaExpandIO (Case rf e as) = Case rf e . zipWith etaExpandIOAlt as . repeat
>   where etaExpandIOAlt (Alt t e) = Alt t . etaExpandIO e
> etaExpandIO (Exist v e)    = Exist v . etaExpandIO e
> etaExpandIO (Let d e)      = Let d . etaExpandIO e
> etaExpandIO (Letrec ds e)  = Letrec ds . etaExpandIO e
> etaExpandIO e              = Apply (Apply debugPerformIO e)

> etaReduceIO :: Expression -> (Expression,Expression)
> etaReduceIO (Apply e1 e2) = (e1, e2)
> etaReduceIO (Case rf e1 [Alt t e2]) = (Case rf e1 [Alt t e2'], v)
>                                               where (e2', v) = etaReduceIO e2
> etaReduceIO (Exist v e)   = (Exist v e', v')  where (e', v') = etaReduceIO e
> etaReduceIO (Let d e)     = (Let d e', v)     where (e', v) = etaReduceIO e
> etaReduceIO (Letrec ds e) = (Letrec ds e', v) where (e', v) = etaReduceIO e
> etaReduceIO e = error ("etaReduceIO " ++ showsPrec 11 e "")

> debugPerformIO :: Expression
> debugPerformIO = Function (debugQualPreludeName "performIO") 2

\end{verbatim}

This type represents the result of the next set of functions. The
first part is a list with the new computation trees introduced,
prepared for function \texttt{clean}, the second is a context for the
transformed expression with the new local definitions (bindings)
introduced. The third component is the transformed expression itself
(without the new local definitions).

\begin{verbatim}

> type SecondPhaseResult = ([Expression],Context,Expression,Int)
> type Context = Expression -> Expression

\end{verbatim}

The next function changes an expression \texttt{e} into
\texttt{let aux$N$ = e in } \texttt{let result$N$ = fst e in }
\texttt{let tree$N$ = snd e in} \texttt{Variable result$N$},
where $N$ represents a number used to ensure distinct names of
variables. Actually this information is returned in the following,
more convenient format:
\texttt{(Trees++[cleanTree], lets, Variable resultId)}, where
\texttt{cleanTree} is \texttt{(dVal result$N$, tree$N$)} and
\texttt{lets} is the context for the transformed expression, i.e., the
local declarations of \texttt{aux$N$}, \texttt{result$N$}, and
\texttt{tree$N$}.

\begin{verbatim}

> decomposeExp :: Int -> Expression -> SecondPhaseResult
>
> decomposeExp n exp = ([cleanTree],lets,Variable resultId,n+1)
>   where auxId     = newIdName n "Aux"
>         resultId  = newIdName n "result"
>         treeId    = newIdName n "tree"
>         fst       = Function (qualifyWith preludeMIdent (mkIdent "fst")) 1
>         snd       = Function (qualifyWith preludeMIdent (mkIdent "snd")) 1
>         lets      = Let (Binding auxId exp) .
>                     Let (Binding resultId (Apply fst (Variable auxId))) .
>                     Let (Binding treeId (Apply snd (Variable auxId)))
>         cleanTree = retrieveCleanTree resultId treeId


> newBindings :: (Ident -> [Expression] -> Expression) -> Expression -> Int
>             -> [Expression] -> (Expression,Int)
> newBindings createNode (Case eval exp lAlt) n lTrees =
>   (lets (Case eval e1 lAlt'),n2)
>   where (lTrees1,lets,e1,n1) = extractBindings exp n
>         (lAlt',n2) = newBindingsAlts createNode lAlt n1 (lTrees++lTrees1)

> newBindings createNode (Or e1 e2) n lTrees = (Or e1' e2',n2)
>   where (e1',n1) = newBindings createNode e1 n lTrees
>         (e2',n2) = newBindings createNode e2 n1 lTrees

> newBindings createNode (Exist id exp) n lTrees = (Exist id exp',n')
>   where (exp',n') = newBindings createNode exp n lTrees

> newBindings createNode (Let binding e) n lTrees = (lets1 e2,n2)
>   where (lTrees1,lets1,n1) = extractBindingsBinding binding n
>         (e2,n2) = newBindings createNode e n1 (lTrees++lTrees1)

> newBindings createNode (Letrec lbinding e) n lTrees =
>   (letrecBindings lets1 e2,n2)
>   where (lTrees1,lets1,n1) = extractBindingsLBindings lbinding n
>         (e2,n2) = newBindings createNode e n1 (lTrees++lTrees1)

> newBindings createNode exp n lTrees = (lets' rhs,n2+1)
>   where (lTrees2,lets,exp2,n2) = extractBindings exp n
>         treeId   = newIdName n2 "tree"
>         resultId = newIdName n2 "result"
>         cTree    = createNode resultId (lTrees++lTrees2)
>         lets'    = lets .
>                    Let (Binding resultId exp2) .
>                    Let (Binding treeId cTree)
>         rhs      = debugBuildPairExp (Variable resultId) (Variable treeId)


> newBindingsAlts :: (Ident -> [Expression] -> Expression) -> [Alt] -> Int
>                 -> [Expression] -> ([Alt],Int)
> newBindingsAlts _ [] n _ = ([],n)
> newBindingsAlts createNode (Alt const e:xs) n lTrees = (Alt const e':xs',n2)
>   where (e',n1) = newBindings createNode e n lTrees
>         (xs',n2) = newBindingsAlts createNode xs n1 lTrees


> extractBindings :: Expression -> Int -> SecondPhaseResult
>
> extractBindings e@(Function f a) n
>   | a > 0 = ([],id,e,n)
>   | otherwise = decomposeExp n e

> extractBindings e@(Case _ _ _) n = decomposeExp n' e'
>   where (e',n') = newBindings createEmptyNode e n []

> extractBindings e@(Or _ _) n = decomposeExp n' e'
>   where (e',n') = newBindings createEmptyNode e n []

> extractBindings (Exist id exp) n = (lTrees',Exist id . lets',exp',n')
>   where (lTrees',lets',exp',n') = extractBindings exp n

> extractBindings (Let binding e) n = (lTrees1++lTrees2,lets1 . lets2,e',n2)
>   where (lTrees1,lets1,n1) = extractBindingsBinding binding n
>         (lTrees2,lets2,e',n2) = extractBindings e n1

> extractBindings (Letrec lbinding e) n =
>   (lTrees1++lTrees2,letrecBindings lets1 . lets2,e',n2)
>   where (lTrees1,lets1,n1) = extractBindingsLBindings lbinding n
>         (lTrees2,lets2,e',n2) = extractBindings e n1

> extractBindings e@(Apply _ _) n = (lTrees1++lTrees2,letsargs . letse,e1,n2)
>   where (f,args) = extractApply e []
>         (lTrees1,letsargs,f':args1,n1) = extractBindingsList (f:args) n
>         (lTrees2,letse,e1,n2) = extractBindingsApply f' args1 n1
>
> extractBindings exp n = ([],id,exp,n)


> extractBindingsApply :: Expression -> [Expression] -> Int -> SecondPhaseResult

> extractBindingsApply e@(Constructor _ _) args n = ([],id,createApply e args,n)

> extractBindingsApply f@(Function qId arity) args n
>   | length args == arity-1 = ([],id,partialApp,n)
>   | isQSelectorId qId = extractBindingsApply app extraArgs n
>   | otherwise = (lTrees1++lTrees2,lets1 . lets2,e,n2)
>   where (nArgs,extraArgs) = splitAt arity args
>         app = createApply f nArgs
>         partialApp = createApply f args --05-12-2001
>         (lTrees1,lets1,v,n1) = decomposeExp n app
>         (lTrees2,lets2,e,n2) = extractBindingsApply v extraArgs n1

> extractBindingsApply f [] n = ([],id,f,n)
> 
> extractBindingsApply f (e:es) n = (t++t',lets . lets',e',n2)
>   where (t,lets,v,n1) = decomposeExp n (Apply f e)
>         (t',lets',e',n2) = extractBindingsApply v es n1


> extractBindingsList :: [Expression] -> Int
>                     -> ([Expression],Context,[Expression],Int)
> extractBindingsList [] n = ([],id,[],n)
> extractBindingsList (x:xs) n = (lTrees1++lTrees2, lets1 . lets2, x':xs', n2)
>   where (lTrees1,lets1,x',n1) = extractBindings x n
>         (lTrees2,lets2,xs',n2) = extractBindingsList xs n1


> extractBindingsBinding :: Binding -> Int -> ([Expression],Context,Int)
> extractBindingsBinding (Binding vId e) n = (lTrees,lBinding,n')
>   where (lTrees,lets,e1,n') = extractBindings e n
>         lBinding = lets . Let (Binding vId e1)


> extractBindingsLBindings :: [Binding] -> Int -> ([Expression],Context,Int)
> extractBindingsLBindings [] n = ([],id,n)
> extractBindingsLBindings (x:xs) n = (lTrees1++lTrees2,letsX . letsXs,n2)
>   where (lTrees1,letsX,n1) = extractBindingsBinding x n
>         (lTrees2,letsXs,n2) = extractBindingsLBindings xs n1


> createTree :: QualIdent -> [Ident] -> Ident -> [Expression] -> Expression
> createTree qId lVars resultId trees =
>   node fName fParams fResult debugNil clean
>   where (idModule,ident) = splitQualIdent qId
>         fNameCh = maybe "" moduleName idModule ++ "." ++ name ident
>         fName   = debugBuildList (map (Literal . Char) fNameCh)
>         fParams = debugBuildList (map (dEvalApply.Variable) lVars)
>         fResult = (dEvalApply.Variable) resultId
>         clean   = if null trees then debugNil
>                   else Apply (Function debugClean 1) (debugBuildList trees)

> createEmptyNode :: Ident -> [Expression] -> Expression
> createEmptyNode resultId trees = if null trees then void else emptyNode clean
>   where clean = Apply (Function debugClean 1) (debugBuildList trees)

> letrecBindings :: Context -> Context
> letrecBindings bindings =
>   fixLetrecBindings Letrec (bindings (Variable undefined))

> fixLetrecBindings :: ([Binding]->Context) -> Expression -> Context
> fixLetrecBindings bindings (Variable _) = bindings []
> fixLetrecBindings bindings (Exist var exp) =
>   Exist var . fixLetrecBindings bindings exp
> fixLetrecBindings bindings (Let binding exp) =
>   fixLetrecBindings (bindings . (binding:)) exp
> fixLetrecBindings bindings (Letrec lbindings exp) =
>   fixLetrecBindings (bindings . (lbindings++)) exp

\end{verbatim}

The function \texttt{retrieveCleanTree} computes an element of the
list of computation trees of the form \texttt{(dEval $r$,$t$)} for a
given pair of variables $r$ and $t$ bound to a subcomputation result
and its associated computation tree, respectively.

\begin{verbatim}

> retrieveCleanTree :: Ident -> Ident -> Expression
> retrieveCleanTree id1 id2 =
>   debugBuildPairExp (dEvalApply (Variable id1)) (Variable id2)

\end{verbatim}
