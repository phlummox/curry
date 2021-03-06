% -*- LaTeX -*-
% $Id: Types.lhs 3206 2016-06-07 07:17:22Z wlux $
%
% Copyright (c) 2002-2016, Wolfgang Lux
% See LICENSE for the full license.
%
\nwfilename{Types.lhs}
\section{Types}
This module provides the definitions for the internal representation
of types in the compiler.
\begin{verbatim}

> module Types where
> import Ident

\end{verbatim}
A type is either a type variable, an application of a type constructor
to a list of arguments, or an arrow type. The \texttt{TypeConstrained}
case is used for representing type variables that are restricted to a
particular set of types. At present, this is used for integer
literals, which are restricted to types \texttt{Int} and
\texttt{Float}. If the type is not restricted, it defaults to the
first type from the constraint list. The case \texttt{TypeSkolem} is
used for handling skolem types, which result from matching data
constructors with existentially quantified types.

Type variables are represented with deBruijn style indices. Universally
quantified type variables are assigned indices in the order of their
occurrence in the type from left to right. This leads to a canonical
representation of types where $\alpha$-equivalence of two types
coincides with equality of the representation.

Note that even though \texttt{TypeConstrained} variables use indices
as well, these variables must never be quantified.
\begin{verbatim}

> data Type =
>     TypeConstructor QualIdent [Type]
>   | TypeVariable Int
>   | TypeConstrained [Type] Int
>   | TypeArrow Type Type
>   | TypeSkolem Int
>   deriving (Eq,Show)

\end{verbatim}
The function \texttt{isArrowType} checks whether a type
$t = t_1 \rightarrow t_2 \rightarrow \dots \rightarrow t_{n+1}$
($n\geq0$) is a function type, i.e., whether $n > 0$ . The function
\texttt{arrowArity} returns the arity $n$ of a function type, the
function \texttt{arrowArgs} returns the list of types
\texttt{[$t_1$,$\dots$,$t_{n}$]}, \texttt{arrowBase} returns the
type $t_{n+1}$, and \texttt{arrowUnapply} combines \texttt{arrowArgs}
and \texttt{arrowBase} in one call.
\begin{verbatim}

> isArrowType :: Type -> Bool
> isArrowType (TypeArrow _ _) = True
> isArrowType _ = False

> arrowArity :: Type -> Int
> arrowArity = length . arrowArgs

> arrowArgs :: Type -> [Type]
> arrowArgs = fst . arrowUnapply

> arrowBase :: Type -> Type
> arrowBase = snd . arrowUnapply

> arrowUnapply :: Type -> ([Type],Type)
> arrowUnapply (TypeArrow ty1 ty2) = (ty1 : tys,ty)
>   where (tys,ty) = arrowUnapply ty2
> arrowUnapply ty = ([],ty)

\end{verbatim}
The methods \texttt{typeVars} and \texttt{typeSkolems} return a list
of all type variables and skolem types occurring in a type $t$,
respectively. Note that \texttt{TypeConstrained} variables are not
included in the set of type variables because they cannot be
generalized.
\begin{verbatim}

> class IsType t where
>   typeVars :: t -> [Int]
>   typeSkolems :: t -> [Int]

> instance IsType Type where
>   typeVars ty = vars ty []
>     where vars (TypeConstructor _ tys) tvs = foldr vars tvs tys
>           vars (TypeVariable tv) tvs = tv : tvs
>           vars (TypeConstrained _ _) tvs = tvs
>           vars (TypeArrow ty1 ty2) tvs = vars ty1 (vars ty2 tvs)
>           vars (TypeSkolem _) tvs = tvs
>   typeSkolems ty = skolems ty []
>     where skolems (TypeConstructor _ tys) sks = foldr skolems sks tys
>           skolems (TypeVariable _) sks = sks
>           skolems (TypeConstrained _ _) sks = sks
>           skolems (TypeArrow ty1 ty2) sks = skolems ty1 (skolems ty2 sks)
>           skolems (TypeSkolem k) sks = k : sks

\end{verbatim}
Type schemes $\forall\overline{\alpha} . \tau(\overline{\alpha})$
introduce (universal) quantification of type variables in types. The
universally quantified type variables in a type are assigned
increasing indices starting at 0. Therefore, it is sufficient to
record only the number of quantified type variables in the
\texttt{ForAll} constructor.

In general, type variables are assigned indices from left to right in
the order of their occurrence in a type. However, a slightly different
scheme is used for types of data and newtype constructors. Here, the
type variables occurring on the left hand side of a declaration are
assigned indices $0, \dots, n-1$, where $n$ is the arity of the type
constructor, regardless of the order of their occurrence in the type.
Existentially quantified type variables that occur on the right hand
side of a type declaration are assigned ascending indices starting at
$n$ in the order of their occurrence. E.g., the type scheme $\forall 4
. (2 \rightarrow 1) \rightarrow (0 \rightarrow 3) \rightarrow
\texttt{T}\,0\,1$ is used for constructor \texttt{C} in the
declaration
\begin{verbatim}
  data T a b = forall c d . C (d -> b) (a -> c)
\end{verbatim}
Thus, it is very easy to distinguish universally and existentially
quantified type variables in the types of data and newtype
constructors. Given type scheme $\forall m . \tau_1 \rightarrow \dots
\tau_l \rightarrow T\,0\dots (n-1)$ for a constructor of type $T$, we
know that the type variables with indices $0, \dots, n-1$ are
universally quantified and the type variables with indices $n, \dots,
m-1$ are existentially quantified.
\begin{verbatim}

> data TypeScheme = ForAll Int Type deriving (Eq,Show)

> instance IsType TypeScheme where
>   typeVars (ForAll _ ty) = [tv | tv <- typeVars ty, tv < 0]
>   typeSkolems (ForAll _ ty) = typeSkolems ty

\end{verbatim}
The functions \texttt{monoType} and \texttt{polyType} translate a type
$\tau$ into a monomorphic type scheme $\forall.\tau$ and a polymorphic
type scheme $\forall\overline{\alpha}.\tau$ where $\overline{\alpha} =
\emph{vars}(\tau)$, respectively. Note that \texttt{polyType} does not
renumber the type variables in its argument type.
\begin{verbatim}

> monoType, polyType :: Type -> TypeScheme
> monoType ty = ForAll 0 ty
> polyType ty = ForAll (maximum (-1 : typeVars ty) + 1) ty

\end{verbatim}
The function \texttt{rawType} strips the quantifier from a type
scheme.
\begin{verbatim}

> rawType :: TypeScheme -> Type
> rawType (ForAll _ ty) = ty

\end{verbatim}
