% -*- LaTeX -*-
% $Id: PredefTypes.lhs 2462 2007-09-07 09:38:13Z wlux $
%
% Copyright (c) 2002-2007, Wolfgang Lux
% See LICENSE for the full license.
%
\nwfilename{PredefTypes.lhs}
\section{Predefined Types}
This module defines the predefined types that are known to the
compiler.
\begin{verbatim}

> module PredefTypes where
> import Ident
> import PredefIdent
> import PredefIdent
> import Types

> unitType,boolType,charType,intType,floatType,stringType,successType :: Type
> unitType = TypeConstructor qUnitId []
> boolType = TypeConstructor qBoolId []
> charType = TypeConstructor qCharId []
> intType = TypeConstructor qIntId []
> floatType = TypeConstructor qFloatId []
> stringType = listType charType
> successType = TypeConstructor qSuccessId []

> listType,ioType :: Type -> Type
> listType ty = TypeConstructor qListId [ty]
> ioType ty = TypeConstructor qIOId [ty]

> tupleType :: [Type] -> Type
> tupleType tys = TypeConstructor (qTupleId (length tys)) tys

\end{verbatim}
