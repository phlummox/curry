% -*- LaTeX -*-
% $Id: CurryPP.lhs 3048 2011-10-02 14:14:03Z wlux $
%
% Copyright (c) 1999-2011, Wolfgang Lux
% See LICENSE for the full license.
%
\nwfilename{CurryPP.lhs}
\section{A Pretty Printer for Curry}\label{sec:CurryPP}
This module implements a pretty printer for Curry expressions. It was
derived from the Haskell pretty printer provided in Simon Marlow's
Haskell parser.
\begin{verbatim}

> module CurryPP(module CurryPP, Doc) where
> import Curry
> import Char
> import Pretty

\end{verbatim}
Pretty print a module
\begin{verbatim}

> ppModule :: Module a -> Doc
> ppModule (Module m es is ds) =
>   vcat (ppModuleHeader m es : map ppImportDecl is ++ map ppTopDecl ds)

\end{verbatim}
Module header
\begin{verbatim}

> ppModuleHeader :: ModuleIdent -> Maybe ExportSpec -> Doc
> ppModuleHeader m es =
>   text "module" <+> ppMIdent m <+> maybePP ppExportSpec es <+> text "where"

> ppExportSpec :: ExportSpec -> Doc
> ppExportSpec (Exporting _ es) = parenList (map ppExport es)

> ppExport :: Export -> Doc
> ppExport (Export x) = ppQIdent x
> ppExport (ExportTypeWith tc cs) = ppQIdent tc <> parenList (map ppIdent cs)
> ppExport (ExportTypeAll tc) = ppQIdent tc <> text "(..)"
> ppExport (ExportModule m) = text "module" <+> ppMIdent m

> ppImportDecl :: ImportDecl -> Doc
> ppImportDecl (ImportDecl _ m q asM is) =
>   text "import" <+> ppQualified q <+> ppMIdent m <+> maybePP ppAs asM
>                 <+> maybePP ppImportSpec is
>   where ppQualified q = if q then text "qualified" else empty
>         ppAs m = text "as" <+> ppMIdent m

> ppImportSpec :: ImportSpec -> Doc
> ppImportSpec (Importing _ is) = parenList (map ppImport is)
> ppImportSpec (Hiding _ is) = text "hiding" <+> parenList (map ppImport is)

> ppImport :: Import -> Doc
> ppImport (Import x) = ppIdent x
> ppImport (ImportTypeWith tc cs) = ppIdent tc <> parenList (map ppIdent cs)
> ppImport (ImportTypeAll tc) = ppIdent tc <> text "(..)"

\end{verbatim}
Declarations
\begin{verbatim}

> ppTopDecl :: TopDecl a -> Doc
> ppTopDecl (DataDecl _ tc tvs cs) =
>   sep (ppTypeDeclLhs "data" tc tvs :
>        map indent (zipWith (<+>) (equals : repeat vbar) (map ppConstr cs)))
> ppTopDecl (NewtypeDecl _ tc tvs nc) =
>   sep [ppTypeDeclLhs "newtype" tc tvs <+> equals,indent (ppNewConstr nc)]
> ppTopDecl (TypeDecl _ tc tvs ty) =
>   sep [ppTypeDeclLhs "type" tc tvs <+> equals,indent (ppTypeExpr 0 ty)]
> ppTopDecl (BlockDecl d) = ppDecl d

> ppTypeDeclLhs :: String -> Ident -> [Ident] -> Doc
> ppTypeDeclLhs kw tc tvs = text kw <+> ppIdent tc <+> hsep (map ppIdent tvs)

> ppConstr :: ConstrDecl -> Doc
> ppConstr (ConstrDecl _ tvs c tys) =
>   sep [ppExistVars tvs,ppIdent c <+> fsep (map (ppTypeExpr 2) tys)]
> ppConstr (ConOpDecl _ tvs ty1 op ty2) =
>   sep [ppExistVars tvs,ppTypeExpr 1 ty1,ppInfixOp op <+> ppTypeExpr 1 ty2]
> ppConstr (RecordDecl _ tvs c fs) =
>   sep [ppExistVars tvs,ppIdent c <+> braces (list (map ppFieldDecl fs))]

> ppFieldDecl :: FieldDecl -> Doc
> ppFieldDecl (FieldDecl p ls ty) = ppDecl (TypeSig p ls ty)

> ppExistVars :: [Ident] -> Doc
> ppExistVars tvs
>   | null tvs = empty
>   | otherwise = text "forall" <+> hsep (map ppIdent tvs) <+> char '.'

> ppNewConstr :: NewConstrDecl -> Doc
> ppNewConstr (NewConstrDecl _ c ty) = ppIdent c <+> ppTypeExpr 2 ty
> ppNewConstr (NewRecordDecl p c l ty) =
>   ppIdent c <+> braces (ppDecl (TypeSig p [l] ty))

> ppBlock :: [Decl a] -> Doc
> ppBlock = vcat . map ppDecl

> ppDecl :: Decl a -> Doc
> ppDecl (InfixDecl _ fix p ops) = ppPrec fix p <+> list (map ppInfixOp ops)
> ppDecl (TypeSig _ fs ty) = ppIdentList fs <+> text "::" <+> ppTypeExpr 0 ty
> ppDecl (FunctionDecl _ _ _ eqs) = vcat (map ppEquation eqs)
> ppDecl (ForeignDecl p fi _ f ty) =
>   sep [text "foreign import" <+> ppForeignImport fi,
>        indent (ppDecl (TypeSig p [f] ty))]
>   where ppForeignImport (cc,s,ie) =
>           ppCallConv cc <+> maybePP ppSafety s <+> maybePP (text . show) ie
>         ppCallConv CallConvPrimitive = text "primitive"
>         ppCallConv CallConvCCall = text "ccall"
>         ppCallConv CallConvRawCall = text "rawcall"
>         ppSafety Unsafe = text "unsafe"
>         ppSafety Safe = text "safe"
> ppDecl (PatternDecl _ t rhs) = ppRule (ppConstrTerm 0 t) equals rhs
> ppDecl (FreeDecl _ vs) = ppIdentList [v | FreeVar _ v <- vs] <+> text "free"
> ppDecl (TrustAnnot _ t fs) = ppPragma (trust t) (ppIdentList fs)
>   where trust Suspect = "SUSPECT"
>         trust Trust = "TRUST"

> ppPragma :: String -> Doc -> Doc
> ppPragma kw p = text "{-#" <+> text kw <+> p <+> text "#-}"

> ppPrec :: Infix -> Maybe Integer -> Doc
> ppPrec fix p = ppAssoc fix <+> maybe empty integer p
>   where ppAssoc InfixL = text "infixl"
>         ppAssoc InfixR = text "infixr"
>         ppAssoc Infix = text "infix"

> ppEquation :: Equation a -> Doc
> ppEquation (Equation _ lhs rhs) = ppRule (ppLhs lhs) equals rhs

> ppLhs :: Lhs a -> Doc
> ppLhs (FunLhs f ts) = ppIdent f <+> fsep (map (ppConstrTerm 2) ts)
> ppLhs (OpLhs t1 f t2) =
>   ppConstrTerm 1 t1 <+> ppInfixOp f <+> ppConstrTerm 1 t2
> ppLhs (ApLhs lhs ts) = parens (ppLhs lhs) <+> fsep (map (ppConstrTerm 2) ts)

> ppRule :: Doc -> Doc -> Rhs a -> Doc
> ppRule lhs eq (SimpleRhs _ e ds) =
>   sep [lhs <+> eq,indent (ppExpr 0 e)] $$ ppLocalDefs ds
> ppRule lhs eq (GuardedRhs es ds) =
>   sep [lhs,indent (vcat (map (ppCondExpr eq) es))] $$ ppLocalDefs ds

> ppLocalDefs :: [Decl a] -> Doc
> ppLocalDefs ds
>   | null ds = empty
>   | otherwise = indent (text "where" <+> ppBlock ds)

\end{verbatim}
Interfaces
\begin{verbatim}

> ppInterface :: Interface -> Doc
> ppInterface (Interface m is ds) =
>   text "interface" <+> ppModuleIdent m <+> text "where" <+> lbrace $$
>   vcat (punctuate semi (map ppIImportDecl is ++ map ppIDecl ds)) $$
>   rbrace
>   where ppModuleIdent m
>           | isMIdent m = ppMIdent m
>           | otherwise = text (show (moduleName m))
>         isMIdent m = not (null ms) && all isIdent ms
>           where ms = moduleQualifiers m
>         isIdent "" = False
>         isIdent (c:cs) = isAlpha c && all isAlphaNum_ cs
>         isAlphaNum_ c = isAlphaNum c || c `elem` "'_"

> ppIImportDecl :: IImportDecl -> Doc
> ppIImportDecl (IImportDecl _ m) = text "import" <+> ppMIdent m

> ppIDecl :: IDecl -> Doc
> ppIDecl (IInfixDecl _ fix p op) = ppPrec fix (Just p) <+> ppQInfixOp op
> ppIDecl (HidingDataDecl _ tc tvs) =
>   ppPragma "DATA" (ppQIdent tc <+> hsep (map ppIdent tvs))
> ppIDecl (IDataDecl _ tc tvs cs xs) =
>   sep (ppITypeDeclLhs "data" tc tvs :
>        map indent (zipWith (<+>) (equals : repeat vbar) (map ppConstr cs)) ++
>        [indent (ppHiding xs)])
> ppIDecl (INewtypeDecl _ tc tvs nc xs) =
>   sep [ppITypeDeclLhs "newtype" tc tvs <+> equals,
>        indent (ppNewConstr nc),
>        indent (ppHiding xs)]
> ppIDecl (ITypeDecl _ tc tvs ty) =
>   sep [ppITypeDeclLhs "type" tc tvs <+> equals,indent (ppTypeExpr 0 ty)]
> ppIDecl (IFunctionDecl _ f n ty) =
>   ppQIdent f <+> text "::" <+> maybePP ppArity n <+> ppTypeExpr 0 ty
>   where ppArity n = ppPragma "ARITY" (integer n)

> ppITypeDeclLhs :: String -> QualIdent -> [Ident] -> Doc
> ppITypeDeclLhs kw tc tvs = text kw <+> ppQIdent tc <+> hsep (map ppIdent tvs)

> ppHiding :: [Ident] -> Doc
> ppHiding cs
>   | null cs = empty
>   | otherwise = ppPragma "HIDING" (ppIdentList cs)

\end{verbatim}
Types
\begin{verbatim}

> ppTypeExpr :: Int -> TypeExpr -> Doc
> ppTypeExpr p (ConstructorType tc tys) =
>   parenExp (p > 1 && not (null tys))
>            (ppQIdent tc <+> fsep (map (ppTypeExpr 2) tys))
> ppTypeExpr _ (VariableType tv) = ppIdent tv
> ppTypeExpr _ (TupleType tys) = parenList (map (ppTypeExpr 0) tys)
> ppTypeExpr _ (ListType ty) = brackets (ppTypeExpr 0 ty)
> ppTypeExpr p (ArrowType ty1 ty2) =
>   parenExp (p > 0) (fsep (ppArrowType (ArrowType ty1 ty2)))
>   where ppArrowType (ArrowType ty1 ty2) =
>           ppTypeExpr 1 ty1 <+> rarrow : ppArrowType ty2
>         ppArrowType ty = [ppTypeExpr 0 ty]

\end{verbatim}
Literals
\begin{verbatim}

> ppLiteral :: Literal -> Doc
> ppLiteral (Char c) = text (show c)
> ppLiteral (Int i) = integer i
> ppLiteral (Float f) = double f
> ppLiteral (String s) = text (show s)

\end{verbatim}
Patterns
\begin{verbatim}

> ppConstrTerm :: Int -> ConstrTerm a -> Doc
> ppConstrTerm p (LiteralPattern _ l) =
>   parenExp (p > 1 && isNegative l) (ppLiteral l)
>   where isNegative (Char _) = False
>         isNegative (Int i) = i < 0
>         isNegative (Float f) = f < 0.0
>         isNegative (String _ ) = False
> ppConstrTerm p (NegativePattern _ op l) =
>   parenExp (p > 1) (ppInfixOp op <> ppLiteral l)
> ppConstrTerm _ (VariablePattern _ v) = ppIdent v
> ppConstrTerm p (ConstructorPattern _ c ts) =
>   parenExp (p > 1 && not (null ts))
>            (ppQIdent c <+> fsep (map (ppConstrTerm 2) ts))
> ppConstrTerm p (FunctionPattern _ f ts) =
>   parenExp (p > 1 && not (null ts))
>            (ppQIdent f <+> fsep (map (ppConstrTerm 2) ts))
> ppConstrTerm p (InfixPattern _ t1 op t2) =
>   parenExp (p > 0)
>            (sep [ppConstrTerm 1 t1 <+> ppOp op,indent (ppConstrTerm 0 t2)])
> ppConstrTerm _ (ParenPattern t) = parens (ppConstrTerm 0 t)
> ppConstrTerm _ (RecordPattern _ c fs) =
>   ppRecord (ppConstrTerm 0) (ppQIdent c) fs
> ppConstrTerm _ (TuplePattern ts) = parenList (map (ppConstrTerm 0) ts)
> ppConstrTerm _ (ListPattern _ ts) = bracketList (map (ppConstrTerm 0) ts)
> ppConstrTerm _ (AsPattern v t) = ppIdent v <> char '@' <> ppConstrTerm 2 t
> ppConstrTerm _ (LazyPattern t) = char '~' <> ppConstrTerm 2 t

\end{verbatim}
Expressions
\begin{verbatim}

> ppCondExpr :: Doc -> CondExpr a -> Doc
> ppCondExpr eq (CondExpr _ g e) =
>   vbar <+> sep [ppExpr 0 g <+> eq,indent (ppExpr 0 e)]

> ppExpr :: Int -> Expression a -> Doc
> ppExpr _ (Literal _ l) = ppLiteral l
> ppExpr _ (Variable _ v) = ppQIdent v
> ppExpr _ (Constructor _ c) = ppQIdent c
> ppExpr _ (Paren e) = parens (ppExpr 0 e)
> ppExpr p (Typed e ty) =
>   parenExp (p > 0) (ppExpr 0 e <+> text "::" <+> ppTypeExpr 0 ty)
> ppExpr _ (Record _ c fs) = ppRecord (ppExpr 0) (ppQIdent c) fs
> ppExpr _ (RecordUpdate e fs) = ppRecord (ppExpr 0) (ppExpr 2 e) fs
> ppExpr _ (Tuple es) = parenList (map (ppExpr 0) es)
> ppExpr _ (List _ es) = bracketList (map (ppExpr 0) es)
> ppExpr _ (ListCompr e qs) =
>   brackets (ppExpr 0 e <+> vbar <+> list (map ppStmt qs))
> ppExpr _ (EnumFrom e) = brackets (ppExpr 0 e <+> text "..")
> ppExpr _ (EnumFromThen e1 e2) =
>   brackets (ppExpr 0 e1 <> comma <+> ppExpr 0 e2 <+> text "..")
> ppExpr _ (EnumFromTo e1 e2) =
>   brackets (ppExpr 0 e1 <+> text ".." <+> ppExpr 0 e2)
> ppExpr _ (EnumFromThenTo e1 e2 e3) =
>   brackets (ppExpr 0 e1 <> comma <+> ppExpr 0 e2
>               <+> text ".." <+> ppExpr 0 e3)
> ppExpr p (UnaryMinus op e) = parenExp (p > 1) (ppInfixOp op <> ppExpr 1 e)
> ppExpr p (Apply e1 e2) =
>   parenExp (p > 1) (sep [ppExpr 1 e1,indent (ppExpr 2 e2)])
> ppExpr p (InfixApply e1 op e2) =
>   parenExp (p > 0) (sep [ppExpr 1 e1 <+> ppOp op,indent (ppExpr 1 e2)])
> ppExpr _ (LeftSection e op) = parens (ppExpr 1 e <+> ppOp op)
> ppExpr _ (RightSection op e) = parens (ppOp op <+> ppExpr 1 e)
> ppExpr p (Lambda _ ts e) =
>   parenExp (p > 0)
>            (sep [backsl <> fsep (map (ppConstrTerm 2) ts) <+> rarrow,
>                  indent (ppExpr 0 e)])
> ppExpr p (Let ds e) =
>   parenExp (p > 0)
>            (sep [text "let" <+> ppBlock ds <+> text "in",ppExpr 0 e])
> ppExpr p (Do sts e) =
>   parenExp (p > 0) (text "do" <+> (vcat (map ppStmt sts) $$ ppExpr 0 e))
> ppExpr p (IfThenElse e1 e2 e3) =
>   parenExp (p > 0)
>            (text "if" <+>
>             sep [ppExpr 0 e1,
>                  text "then" <+> ppExpr 0 e2,
>                  text "else" <+> ppExpr 0 e3])
> ppExpr p (Case e alts) =
>   parenExp (p > 0)
>            (text "case" <+> ppExpr 0 e <+> text "of" $$
>             indent (vcat (map ppAlt alts)))
> ppExpr p (Fcase e alts) =
>   parenExp (p > 0)
>            (text "fcase" <+> ppExpr 0 e <+> text "of" $$
>             indent (vcat (map ppAlt alts)))

> ppStmt :: Statement a -> Doc
> ppStmt (StmtExpr e) = ppExpr 0 e
> ppStmt (StmtBind _ t e) =
>   sep [ppConstrTerm 0 t <+> larrow,indent (ppExpr 0 e)]
> ppStmt (StmtDecl ds) = text "let" <+> ppBlock ds

> ppAlt :: Alt a -> Doc
> ppAlt (Alt _ t rhs) = ppRule (ppConstrTerm 0 t) rarrow rhs

> ppOp :: InfixOp a -> Doc
> ppOp (InfixOp _ op) = ppQInfixOp op
> ppOp (InfixConstr _ op) = ppQInfixOp op

> ppRecord :: (a -> Doc) -> Doc -> [Field a] -> Doc
> ppRecord pp c fs = c <> braces (list (map (ppField pp) fs))

> ppField :: (a -> Doc) -> Field a -> Doc
> ppField pp (Field l x) = ppQIdent l <+> equals <+> pp x

\end{verbatim}
Goals
\begin{verbatim}

> ppGoal :: Goal a -> Doc
> ppGoal (Goal _ e ds) = sep [ppExpr 0 e,indent (ppLocalDefs ds)]

\end{verbatim}
Names
\begin{verbatim}

> ppIdent :: Ident -> Doc
> ppIdent x = parenExp (isInfixOp x) (text (name x))

> ppQIdent :: QualIdent -> Doc
> ppQIdent x = parenExp (isQInfixOp x) (text (qualName x))

> ppInfixOp :: Ident -> Doc
> ppInfixOp x = backQuoteExp (not (isInfixOp x)) (text (name x))

> ppQInfixOp :: QualIdent -> Doc
> ppQInfixOp x = backQuoteExp (not (isQInfixOp x)) (text (qualName x))

> ppMIdent :: ModuleIdent -> Doc
> ppMIdent m = text (moduleName m)

> ppIdentList :: [Ident] -> Doc
> ppIdentList = list . map ppIdent

\end{verbatim}
Print printing utilities
\begin{verbatim}

> indent :: Doc -> Doc
> indent = nest 2

> maybePP :: (a -> Doc) -> Maybe a -> Doc
> maybePP pp = maybe empty pp

> parenExp :: Bool -> Doc -> Doc
> parenExp b doc = if b then parens doc else doc

> backQuoteExp :: Bool -> Doc -> Doc
> backQuoteExp b doc = if b then backQuote <> doc <> backQuote else doc

> list, parenList, bracketList, braceList :: [Doc] -> Doc
> list = fsep . punctuate comma
> parenList = parens . list
> bracketList = brackets . list
> braceList = braces . list

> backQuote,backsl,vbar,rarrow,larrow :: Doc
> backQuote = char '`'
> backsl = char '\\'
> vbar = char '|'
> rarrow = text "->"
> larrow = text "<-"

\end{verbatim}
