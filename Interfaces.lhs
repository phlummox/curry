% -*- LaTeX -*-
% $Id: Interfaces.lhs 2472 2007-09-19 14:55:02Z wlux $
%
% Copyright (c) 1999-2007, Wolfgang Lux
% See LICENSE for the full license.
%
\nwfilename{Interfaces.lhs}
\section{Interfaces}
The compiler maintains a global environment containing all interfaces
imported directly or indirectly into the current module.
\begin{verbatim}

> module Interfaces where
> import Curry
> import Env

> type ModuleEnv = Env ModuleIdent Interface

> bindModule :: Interface -> ModuleEnv -> ModuleEnv
> bindModule (Interface m is ds) = bindEnv m (Interface m is ds)

> unbindModule :: ModuleIdent -> ModuleEnv -> ModuleEnv
> unbindModule = unbindEnv

\end{verbatim}
