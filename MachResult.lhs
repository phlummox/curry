% -*- LaTeX -*-
% $Id: MachResult.lhs 1889 2006-04-06 16:55:47Z wlux $
%
% Copyright (c) 1998-2006, Wolfgang Lux
% See LICENSE for the full license.
%
\nwfilename{MachResult.lhs}
\subsection{Building a Disjunctive Expression}
When we construct the answer expression from the final state of the
computation, all (free) variables are given unique names. For the
global free variables, these are the names which where specified at
the program startup. The other variables are assigned fresh names. For
the answer part of the result, we will consider only those variables
which have been bound to some value (even if it is another unbound
variable). As a side effect, the process shown below constructs the
list of variables used in the answer expression.
\begin{verbatim}

> module MachResult where
> import MachTypes
> import MachNode
> import List
> import Set
> import Monad
> import Error
> import Combined

> type BrowseState a = StateT [Integer] MachState a

> newtype MachState a = MachState (MachStateT a)
> instance Monad MachState where
>   return m = MachState (return m)
>   MachState m >>= f = MachState (m >>= \x -> let MachState m' = f x in m')
> instance RefMonad MachState where
>   newRef x = MachState (newRef x)
>   readRef r = MachState (readRef r)
>   writeRef r x = MachState (writeRef r x)

> browse :: [(String,NodePtr)] -> NodePtr -> MachStateT ShowS
> browse freeVars node = 
>   call (browseResult freeVars node) (map (nodeAdr . snd) freeVars)
>   where nodeAdr (Ptr adr _) = adr
>         call m is = let MachState m' = callSt m is in m'

> browseResult :: [(String,NodePtr)] -> NodePtr -> BrowseState ShowS
> browseResult freeVars ptr =
>   do
>     answer <- browseSubsts names freeVars
>     cstrs <- browseConstraints names freeVars ptr
>     Ptr adr ref <- derefPtr ptr
>     node <- readRef ref
>     exp <- browseExpression 0 names adr node
>     return (showsAnswer (nodeTag node == successTag) (answer ++ cstrs) exp)
>   where names = variableNames freeVars

> browseExpression :: Int -> [String] -> Integer -> Node -> BrowseState ShowS
> browseExpression p names adr (CharNode c) = return (shows c)
> browseExpression p names adr (IntNode i) = return (shows i)
> browseExpression p names adr (FloatNode f) = return (shows f)
> browseExpression p names adr (ConstructorNode _ name args)
>   | isTupleName name = liftM showsTuple (mapM (browseElem names) args)
>   | name == cons =
>       do
>         mbCs <- getString args
>         case mbCs of
>           Just cs -> return (shows cs)
>           Nothing -> liftM showsList (browseList names args)
>   | otherwise = liftM (showsTerm p name) (mapM (browseArg names) args)
>   where ConstructorTag _ cons _ = consTag
> browseExpression p names adr (VarNode _ _ _) =
>   liftM showString (varName names adr)
> browseExpression p names adr (ClosureNode name _ _ args) =
>   liftM (showsTerm p name) (mapM (browseArg names) args)
> browseExpression p names adr (LazyNode name arity code args _) =
>   browseExpression p names adr (ClosureNode name arity code args)
> browseExpression p names adr (QueueMeNode _ _) =
>   return (showString "Suspended")
> browseExpression p names adr (IndirNode (Ptr adr' ref)) =
>   readRef ref >>= browseExpression p names adr'
> browseExpression p names adr (SearchContinuation _ _ _ _) =
>   return (showString "<search>")

> browseArg :: [String] -> NodePtr -> BrowseState ShowS
> browseArg names (Ptr adr ref) = readRef ref >>= browseExpression 1 names adr

> browseElem :: [String] -> NodePtr -> BrowseState ShowS
> browseElem names (Ptr adr ref) = readRef ref >>= browseExpression 0 names adr

> browseList :: [String] -> [NodePtr] -> BrowseState ShowS
> browseList names [head,tail] =
>   do
>     hd <- browseElem names head
>     tl <- derefPtr tail >>= browseTail names
>     return (hd . tl)

> browseTail :: [String] -> NodePtr -> BrowseState ShowS
> browseTail names (Ptr adr ref) =
>   readRef ref >>= \node ->
>   case node of
>     ConstructorNode _ cName args
>       | cName == nil -> return id
>       | cName == cons -> liftM (showString "," .) (browseList names args)
>     _ -> liftM (showString "|" .) (browseExpression 0 names adr node)
>   where ConstructorTag _ nil _  = nilTag
>         ConstructorTag _ cons _ = consTag

> getString :: [NodePtr] -> BrowseState (Maybe String)
> getString [head,tail] =
>   do
>     mbC <- getStringHead head
>     case mbC of
>       Just c ->
>         do
>           mbCs <- getStringTail tail
>           case mbCs of
>             Just cs -> return (Just (c:cs))
>             Nothing -> return Nothing
>       Nothing -> return Nothing

> getStringHead :: NodePtr -> BrowseState (Maybe Char)
> getStringHead (Ptr _ ref) =
>   readRef ref >>= \node ->
>   case node of
>     CharNode c -> return (Just c)
>     IndirNode ptr -> getStringHead ptr
>     _ -> return Nothing

> getStringTail :: NodePtr -> BrowseState (Maybe String)
> getStringTail (Ptr _ ref) =
>   readRef ref >>= \node ->
>   case node of
>     ConstructorNode _ cName args
>       | cName == nil -> return (Just [])
>       | cName == cons -> getString args
>       | otherwise -> return Nothing
>     IndirNode ptr -> getStringTail ptr
>     _ -> return Nothing
>   where ConstructorTag _ nil _  = nilTag
>         ConstructorTag _ cons _ = consTag

> browseSubsts :: [String] -> [(String,NodePtr)] -> BrowseState [ShowS]
> browseSubsts names freeVars =
>   mapM readVar freeVars >>= mapM (browseSubst names) . filter isBound
>   where readVar (name,Ptr adr ref) =
>           readRef ref >>= \node -> return (name,adr,node)
>         isBound (_,_,VarNode _ _ _) = False
>         isBound _ = True

> browseSubst :: [String] -> (String,Integer,Node) -> BrowseState ShowS
> browseSubst names (name,adr,node) =
>   liftM (showString (name ++ " = ") .) (browseExpression 0 names adr node)

> browseConstraints ::
>     [String] -> [(String,NodePtr)] -> NodePtr -> BrowseState [ShowS]
> browseConstraints names freeVars ptr =
>   foldM constrainedVars zeroSet (ptr : map snd freeVars) >>=
>   mapM constraints . toListSet >>=
>   mapM (browseConstraint names) . concat
>   where constraints (Ptr adr ref) =
>           varName names adr >>= \name ->
>           readRef ref >>= \(VarNode cs _ _) ->
>           return [(name,c) | c <- cs]

> browseConstraint :: [String] -> (String,Constraint) -> BrowseState ShowS
> browseConstraint names (name,DisEq (Ptr adr ref)) =
>   readRef ref >>= 
>   liftM (showString (name ++ " /= ") .) . browseExpression 0 names adr

> constrainedVars :: Set NodePtr -> NodePtr -> BrowseState (Set NodePtr)
> constrainedVars vars ptr@(Ptr _ ref) =
>   readRef ref >>= \node ->
>   case node of
>     ConstructorNode _ _ args -> foldM constrainedVars vars args
>     VarNode cstrs _ _
>       | ptr `notElemSet` vars && not (null cstrs) ->
>           foldM constrainedVars (addToSet ptr vars) [ptr | DisEq ptr <- cstrs]
>       | otherwise -> return vars
>     ClosureNode _ _ _ args -> foldM constrainedVars vars args
>     LazyNode _ _ _ args _ -> foldM constrainedVars vars args
>     IndirNode ptr -> constrainedVars vars ptr
>     _ -> return vars

> showsAnswer :: Bool -> [ShowS] -> ShowS -> ShowS
> showsAnswer isSuccess answer exp
>   | null answer = exp
>   | isSuccess = braces ('{','}') (catBy ", " answer)
>   | otherwise = braces ('{','}') (catBy ", " answer) . showChar ' ' . exp

> showsTerm :: Int -> String -> [ShowS] -> ShowS
> showsTerm p root args =
>   showParen (not (null args) && p > 0) (catBy " " (showString root : args))

> showsTuple :: [ShowS] -> ShowS
> showsTuple args = braces ('(',')') (catBy "," args)

> showsList :: ShowS -> ShowS
> showsList = braces ('[',']')

> catBy :: String -> [ShowS] -> ShowS
> catBy sep = cat . intersperse (showString sep)

> cat :: [ShowS] -> ShowS
> cat = foldr (.) id

> braces :: (Char,Char) -> ShowS -> ShowS
> braces (lb,rb) x = showChar lb . x . showChar rb

\end{verbatim}
The assignment of names to variables uses a list of names and a list
of known variable addresses. For each variable, a unique name is
returned and the list of known addresses may be updated. The function
\texttt{varName} assumes that the name supply is unbounded.
\begin{verbatim}

> varName :: [String] -> Integer -> BrowseState String
> varName names adr = 
>   do
>     (adrs1,adrs2) <- liftM (break (adr ==)) fetchSt
>     when (null adrs2) (updateSt_ (++ [adr]))
>     return (names !! length adrs1)

\end{verbatim}
The list of variable names is initialized with the names of the global
variables, followed by a supply of generated names. This generator
is just a copy of the function used to generate fresh variables names
in the interpreter \ToDo{So they should probably be joined into a
single utility function}. Note that we use lowercase letters for
variable names here, too.
\begin{verbatim}

> variableNames :: [(String,NodePtr)] -> [String]
> variableNames freeVars = names ++ filter (`notElem` names) genVars
>   where names = map fst freeVars
>         genVars = [genName c i | i <- [0..], c <- ['a'..'z']]
>         genName c i = '_' : c : if i == 0 then "" else show i

\end{verbatim}
