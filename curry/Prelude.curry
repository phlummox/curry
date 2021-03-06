-- $Id: Prelude.curry 3206 2016-06-07 07:17:22Z wlux $
--
-- Copyright (c) 1999-2016, Wolfgang Lux
-- See ../LICENSE for the full license.

module Prelude((.), id, const, curry, uncurry, flip, until,
               seq, ensureNotFree, ensureGround, ensureSpine,
               ($), ($!), ($!!), ($#), ($##),
               error, undefined, failed,
               Bool(..), (&&), (||), not, if_then_else, otherwise, solve,
               (==), (/=),
               Ordering(..), compare, (<), (>), (<=), (>=), max, min,
               fst, snd,
               head, tail, null, (++), length, (!!),
               map, foldl, foldl1, foldr, foldr1, filter,
               zip, zip3, zipWith, zipWith3, unzip, unzip3,
               concat, concatMap, iterate, repeat, replicate,
               take, drop, splitAt, takeWhile, dropWhile, span, break,
               reverse, and, or, any, all, elem, notElem, lookup,
               Char(), ord, chr,
               String, lines, unlines, words, unwords,
               ShowS, show, shows, showChar, showString, showList, showParen,
               Int(), (+), (-), (*), quot, rem, div, mod,
               negate, abs, signum, subtract, even, odd, gcd, lcm, (^),
               Float(), (+.), (-.), (*.), (/.),
               negateFloat, absFloat, signumFloat, subtractFloat, (^.), (^^.),
               floatFromInt, truncateFloat, roundFloat,
               enumFrom, enumFromThen, enumFromTo, enumFromThenTo,
               Success, (=:=), (=/=), (=:<=), (==<=), success, (&), (&>),
               Maybe(..), maybe,
               Either(..), either,
               IO(), done, return, (>>), (>>=), fail,
               sequenceIO, sequenceIO_, mapIO, mapIO_,
               getChar, getLine, getContents,
               putChar, putStr, putStrLn, print,
               FilePath, readFile, writeFile, appendFile,
               IOError, ioError, catch,
               interact, doSolve,
               (?), unknown,
               try, inject, solveAll, once, best, findall, findfirst,
               browse, browseList, unpack) where
import IO

-- Infix operator declarations:

infixl 9 !!
infixr 9 .
infixl 8 ^, ^., ^^.
infixl 7 *, `quot`, `rem`, `div`, `mod`, *., /.
infixl 6 +, -, +., -.
infixr 5 :, ++
infix  4 =:=, =/=, =:<=, ==<=, ==, /=, <, >, <=, >=
infix  4 `elem`, `notElem`
infixr 3 &&
infixr 2 ||
infixl 1 >>, >>=
infixr 0 $, $!, $!!, $#, $##, `seq`, &, &>, ?

-- Some standard combinators:

--- Function composition.
(.)   :: (b -> c) -> (a -> b) -> (a -> c)
(f . g) x = f (g x)

--- Identity function.
id              :: a -> a
id x            = x

--- Constant function.
const           :: a -> b -> a
const x _       = x

--- Converts an uncurried function to a curried function.
curry           :: ((a,b) -> c) -> a -> b -> c
curry f a b     =  f (a,b)

--- Converts an curried function to a function on pairs.
uncurry         :: (a -> b -> c) -> (a,b) -> c
uncurry f (a,b) = f a b

--- (flip f) is identical to f but with the order of arguments reversed.
flip            :: (a -> b -> c) -> b -> a -> c
flip  f x y     = f y x

--- Repeat application of a function until a predicate holds.
until          :: (a -> Bool) -> (a -> a) -> a -> a
until p f x     = if p x then x else until p f (f x)


--- Evaluate the first argument to head normal form and return the
--- second argument.
foreign import primitive seq :: a -> b -> b

--- (ensureNotFree x) is equivalent to (id x) except that it suspends
--- until x is instantiated to a non-variable term.
foreign import primitive ensureNotFree :: a -> a

--- (ensureGround x) is equivalent to (id x) except that it ensures that the
--- result is a ground term.
foreign import primitive ensureGround :: a -> a


--- Right-associative application.
($)             :: (a -> b) -> a -> b
f $ x           = f x

--- Right-associative application with strict evaluation of its argument.
($!)		:: (a -> b) -> a -> b
f $! x		= x `seq` f x

--- Right-associative application with strict evaluation of its argument
--- to normal form.
($!!)		:: (a -> b) -> a -> b
f $!! x		| x=:=y = f y where y free

--- Right-associative application with strict evaluation of its argument
--- to a non-variable term.
($#)		:: (a -> b) -> a -> b
f $# x		= f $! ensureNotFree x

--- Right-associative application with strict evaluation of its argument
--- to ground normal form.
($##)		:: (a -> b) -> a -> b
f $## x		= f $!! ensureGround x


--- Abort the execution with an error message.
error :: String -> a
error msg = unsafePerformIO (abort ("Error: " ++ msg ++ "\n"))
  where abort msg = hPutStr stderr msg >> exit_with 1 >> undefined
	foreign import primitive unsafePerformIO :: IO a -> a
 	foreign import ccall exit_with :: Int -> IO ()
        -- NB exit_with does not return and therefore should have type
        --    Int -> IO a, but this type is not a valid foreign type for
        --    the ccall calling convention.

--- The totally undefined function.
undefined :: a
undefined = Prelude.error "Prelude.undefined"


--- failed is a non-reducible polymorphic function.
--- It is useful to express a failure in a search branch of the execution.
foreign import primitive failed :: a


-- Boolean values
-- already defined as builtin, since it is required for if-then-else
data Bool = False | True

--- Sequential conjunction on Booleans.
(&&)            :: Bool -> Bool -> Bool
True  && x      = x
False && _      = False

--- Sequential disjunction on Booleans.
(||)            :: Bool -> Bool -> Bool
True  || _      = True
False || x      = x

--- Negation.
not             :: Bool -> Bool
not True        = False
not False       = True

--- Conditional.
if_then_else	:: Bool -> a -> a -> a
if_then_else b t f =
  case b of 
    True -> t
    False -> f

--- Useful name for the last condition in a sequence of conditional equations.
otherwise       :: Bool
otherwise       = True


--- Enforce a boolean condition to be True.
--- The computation fails if the argument evaluates to False.
solve :: Bool -> Bool
solve True = True


--- Equality on finite ground data terms
foreign import primitive (==) :: a -> a -> Bool

--- Disequality
(/=) :: a -> a -> Bool
(/=) x y = not (x == y)


-- Ordering
data Ordering = LT | EQ | GT

--- Comparison of arbitrary ground data terms.
--- Data constructors are compared in the order of their definition
--- in the datatype decalrations and recursively in the arguments.
foreign import primitive compare :: a -> a -> Ordering

--- Less-than on ground data terms
(<) :: a -> a -> Bool
x < y = case compare x y of LT -> True; _ -> False

--- Greater-than on ground data terms
(>) :: a -> a -> Bool
x > y = case compare x y of GT -> True; _ -> False

--- Less-or-equal on ground data terms
(<=) :: a -> a -> Bool
x <= y = not (x > y)

--- Greater-or-equal on ground data terms
(>=) :: a -> a -> Bool
x >= y = not (x < y)

--- Maximum of ground data terms
max :: a -> a -> a
max x y = if x >= y then x else y

--- Minimum of ground data terms
min :: a -> a -> a
min x y = if x <= y then x else y

 
-- Tuples

data (,) a b = (,) a b
data (,,) a b c = (,,) a b c
data (,,,) a b c d = (,,,) a b c d
data (,,,,) a b c d e = (,,,,) a b c d e
data (,,,,,) a b c d e f = (,,,,,) a b c d e f
data (,,,,,,) a b c d e f g = (,,,,,,) a b c d e f g
data (,,,,,,,) a b c d e f g h = (,,,,,,,) a b c d e f g h
data (,,,,,,,,) a b c d e f g h i = (,,,,,,,,) a b c d e f g h i
data (,,,,,,,,,) a b c d e f g h i j = (,,,,,,,,,) a b c d e f g h i j
data (,,,,,,,,,,) a b c d e f g h i j k = (,,,,,,,,,,) a b c d e f g h i j k
data (,,,,,,,,,,,) a b c d e f g h i j k l =
  (,,,,,,,,,,,) a b c d e f g h i j k l
data (,,,,,,,,,,,,) a b c d e f g h i j k l m =
  (,,,,,,,,,,,,) a b c d e f g h i j k l m
data (,,,,,,,,,,,,,) a b c d e f g h i j k l m n =
  (,,,,,,,,,,,,,) a b c d e f g h i j k l m n
data (,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o =
  (,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o
data (,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p =
  (,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p
data (,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q =
  (,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q
data (,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r =
  (,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r
data (,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s =
  (,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s
data (,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t =
  (,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t
data (,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u =
  (,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u
data (,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v =
  (,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v
data (,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w =
  (,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w
data (,,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w x =
  (,,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w x
data (,,,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w x y =
  (,,,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w x y
data (,,,,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w x y z =
  (,,,,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w x y z
data (,,,,,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w x y z a1 =
  (,,,,,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w x y z a1
data (,,,,,,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w x y z a1 b1 =
  (,,,,,,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w x y z a1 b1
data (,,,,,,,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w x y z a1 b1 c1 =
  (,,,,,,,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w x y z a1 b1 c1
data (,,,,,,,,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w x y z a1 b1 c1 d1 =
  (,,,,,,,,,,,,,,,,,,,,,,,,,,,,,) a b c d e f g h i j k l m n o p q r s t u v w x y z a1 b1 c1 d1

--- Selects the first component of a pair.
fst             :: (a,b) -> a
fst (x,_)       = x

--- Selects the second component of a pair.
snd             :: (a,b) -> b
snd (_,y)       = y


-- Unit type
data () = ()


-- Lists

data [] a = [] | a : [a]

--- Evaluates the argument to spine form and returns it.
--- Suspends until the result is bound to a non-variable spine.
ensureSpine    	 :: [a] -> [a]
ensureSpine l =
  case l of
     []   -> []
     x:xs -> x : ensureSpine xs

--- Computes the first element of a list.
head            :: [a] -> a
head (x:_)      = x

--- Computes the remaining elements of a list.
tail            :: [a] -> [a]
tail (_:xs)     = xs

--- Is a list empty?
null            :: [a] -> Bool
null []         = True
null (_:_)      = False

--- Concatenates two lists.
(++)            :: [a] -> [a] -> [a]
[]     ++ ys    = ys
(x:xs) ++ ys    = x : xs++ys

--- Computes the length of a list.
length          :: [a] -> Int
length		= count 0
  where count n []     = n
  	count n (_:xs) = n' `seq` count n' xs where n' = n + 1

--- List index (subscript) operator, head has index 0
(!!)              :: [a] -> Int -> a
(x:xs) !! n
  | n == 0        = x
  | n > 0         = xs !! (n-1)

--- Map a function on all elements of a list.
map             :: (a -> b) -> [a] -> [b]
map _ []        = []
map f (x:xs)    = f x : map f xs

--- Accumulates all list elements by applying a binary operator from
--- left to right. Thus,
--- <CODE>foldl f z [x1,x2,...,xn] = (...((z `f` x1) `f` x2) ...) `f` xn</CODE>
foldl            :: (a -> b -> a) -> a -> [b] -> a
foldl _ z []     = z
foldl f z (x:xs) = foldl f (f z x) xs

--- Accumulates a non-empty list from left to right.
foldl1           :: (a -> a -> a) -> [a] -> a
foldl1 f (x:xs)  = foldl f x xs

--- Accumulates all list elements by applying a binary operator from
--- right to left. Thus,
--- <CODE>foldr f z [x1,x2,...,xn] = (x1 `f` (x2 `f` ... (xn `f` z)...))</CODE>
foldr            :: (a -> b -> b) -> b -> [a] -> b
foldr _ z []     = z
foldr f z (x:xs) = f x (foldr f z xs)

--- Accumulates a non-empty list from right to left:
foldr1              :: (a -> a -> a) -> [a] -> a
foldr1 _ [x]        = x
foldr1 f (x1:x2:xs) = f x1 (foldr1 f (x2:xs))

--- Filters all elements satisfying a given predicate in a list.
filter            :: (a -> Bool) -> [a] -> [a]
filter _ []       = []
filter p (x:xs)   = if p x then x : filter p xs
                           else filter p xs

--- Joins two lists into one list of pairs. If one input list is shorter than
--- the other, the additional elements of the longer list are discarded.
zip               :: [a] -> [b] -> [(a,b)]
zip		  = zipWith (,)

--- Joins three lists into one list of triples. If one input list is shorter
--- than the other, the additional elements of the longer lists are discarded.
zip3              :: [a] -> [b] -> [c] -> [(a,b,c)]
zip3		  = zipWith3 (,,)

--- Joins two lists into one list by applying a combination function to
--- corresponding pairs of elements. Thus <CODE>zip = zipWith (,)</CODE>
zipWith                 :: (a -> b -> c) -> [a] -> [b] -> [c]
zipWith _ []     _      = []
zipWith _ (_:_)  []     = []
zipWith f (x:xs) (y:ys) = f x y : zipWith f xs ys

--- Joins three lists into one list by applying a combination function to
--- corresponding triples of elements. Thus <CODE>zip3 = zipWith3 (,,)</CODE>
zipWith3	  :: (a -> b -> c -> d) -> [a] -> [b] -> [c] -> [d]
zipWith3 _ []     _      _      = []
zipWith3 _ (_:_)  []     _      = []
zipWith3 _ (_:_)  (_:_)  []     = []
zipWith3 f (x:xs) (y:ys) (z:zs) = f x y z : zipWith3 f xs ys zs

--- Transforms a list of pairs into a pair of lists.
unzip               :: [(a,b)] -> ([a],[b])
unzip []            = ([],[])
unzip ((x,y):ps)    = (x:xs,y:ys) where (xs,ys) = unzip ps

--- Transforms a list of triples into a triple of lists.
unzip3              :: [(a,b,c)] -> ([a],[b],[c])
unzip3 []           = ([],[],[])
unzip3 ((x,y,z):ts) = (x:xs,y:ys,z:zs) where (xs,ys,zs) = unzip3 ts

--- Concatenates a list of lists into one list.
concat            :: [[a]] -> [a]
concat l          = foldr (++) [] l

--- Maps a function from elements to lists and merges the result into one list.
concatMap         :: (a -> [b]) -> [a] -> [b]
concatMap f xs    = concat (map f xs)

--- Infinite list of repeated applications of a function f to an element x.
--- Thus, <CODE>iterate f x = [x, f x, f (f x),...]</CODE>
iterate           :: (a -> a) -> a -> [a]
iterate f x       = x : iterate f (f x)

--- Infinite list where all elements have the same value.
--- Thus, <CODE>repeat x = [x, x, x,...]</CODE>
repeat            :: a -> [a]
repeat x          = x : repeat x

--- List of length n where all elements have the same value.
replicate         :: Int -> a -> [a]
replicate n x     = take n (repeat x)

--- Returns prefix of length n.
take              :: Int -> [a] -> [a]
take n l          = if n<=0 then [] else takep n l
   where takep _ []     = []
         takep n (x:xs) = x : take (n-1) xs

--- Returns suffix without first n elements.
drop              :: Int -> [a] -> [a]
drop n l          = if n<=0 then l else dropp n l
   where dropp _ []     = []
         dropp n (_:xs) = drop (n-1) xs

--- (splitAt n xs) is equivalent to (take n xs, drop n xs)
splitAt		  :: Int -> [a] -> ([a],[a])
splitAt n l	  = if n <= 0 then ([],l) else splitAtp n l
  where splitAtp _ []     = ([],[])
	splitAtp n (x:xs) = let (ys,zs) = splitAt (n-1) xs in (x:ys,zs)

--- Returns longest prefix with elements satisfying a predicate.
takeWhile          :: (a -> Bool) -> [a] -> [a]
takeWhile _ []     = []
takeWhile p (x:xs) = if p x then x : takeWhile p xs else []

--- Returns suffix without takeWhile prefix.
dropWhile          :: (a -> Bool) -> [a] -> [a]
dropWhile _ []     = []
dropWhile p (x:xs) = if p x then dropWhile p xs else x:xs

--- (span p xs) is equivalent to (takeWhile p xs, dropWhile p xs)
span               :: (a -> Bool) -> [a] -> ([a],[a])
span _ []          = ([],[])
span p (x:xs)
  | p x	      = let (ys,zs) = span p xs in (x:ys,zs)
  | otherwise = ([],x:xs)

--- (break p xs) is equivalent to (takeWhile (not.p) xs, dropWhile (not.p) xs).
--- Thus, it breaks a list at the first occurrence of an element satisfying p.
break              :: (a -> Bool) -> [a] -> ([a],[a])
break p            = span (not . p)

--- Reverses the order of all elements in a list.
reverse    :: [a] -> [a]
reverse    = foldl (flip (:)) []

--- Computes the conjunction of a Boolean list.
and        :: [Bool] -> Bool
and []     = True
and (x:xs) = if x then and xs else False

--- Computes the disjunction of a Boolean list.
or         :: [Bool] -> Bool
or []      = False
or (x:xs)  = if x then True else or xs

--- Is there an element in a list satisfying a given predicate?
any        :: (a -> Bool) -> [a] -> Bool
any p xs   = or (map p xs)

--- Is a given predicate satisfied by all elements in a list?
all        :: (a -> Bool) -> [a] -> Bool
all p xs   = and (map p xs)

--- Element of a list?
elem       :: a -> [a] -> Bool
elem x     = any (x==)

--- Not element of a list?
notElem    :: a -> [a] -> Bool
notElem x  = all (x/=)

--- Looks up a key in an association list
lookup		     :: a -> [(a,b)] -> Maybe b
lookup x []	     = Nothing
lookup x ((y,z):yzs) = if x == y then Just z else lookup x yzs



-- character type

-- Characters
data Char

--- Converts a characters into its ASCII value.
foreign import ccall "prims.h primOrd" ord :: Char -> Int

--- Converts an ASCII value into a character.
foreign import ccall "prims.h primChr" chr :: Int -> Char


-- Strings

type String = [Char]

--- Breaks a string into a list of lines where a line is terminated at a
--- newline character. The resulting lines do not contain newline characters.
lines        :: String -> [String]
lines []     = []
lines (c:cs) = l : lines' s'
  where (l,s') = break ('\n' ==) (c:cs)
	lines' []    = []
	lines' (_:s'') = lines s''

--- Concatenates a list of strings with terminating newlines.
unlines    :: [String] -> String
unlines ls = concatMap (++ "\n") ls

--- Breaks a string into a list of words where the words are delimited by
--- white spaces.
words      :: String -> [String]
words cs   =
  case dropWhile isSpace cs of
    "" -> []
    cs' -> let (w,cs'') = break isSpace cs' in w : words cs''
  where isSpace c = c `elem` " \t\n\r\f\v\xA0"

--- Concatenates a list of strings with a blank between two strings.
unwords    	:: [String] -> String
unwords []	 = []
unwords (w:ws) = w ++ foldr (\w cs -> (' ' : w) ++ cs) "" ws

--- Converts an arbitrary term into an external string representation.
show :: a -> String
show x = shows x ""

type ShowS = String -> String
foreign import primitive shows :: a -> ShowS

showChar :: Char -> ShowS
showChar c = (c :)

showString :: String -> ShowS
showString s = (s ++)

showList :: [a] -> ShowS
showList [] = showString "[]"
showList (x:xs) = showChar '[' . shows x . showl xs
  where showl [] = showChar ']'
        showl (x:xs) = showChar ',' . shows x . showl xs

showParen :: Bool -> ShowS -> ShowS
showParen True x = showChar '(' . x . showChar ')'
showParen False x = x

-- Types of primitive arithmetic functions and predicates
-- NB quot,rem and div,mod are compatible with Haskell, i.e.
--    N `quot` M + N `rem` M = N
--    N `div`  M + N `mod` M = N
--    the result of quot is truncated towards zero and the result
--    of div is truncated towards negative infinity

data Int
foreign import ccall "prims.h primAddInt" (+) :: Int -> Int -> Int
foreign import ccall "prims.h primSubInt" (-) :: Int -> Int -> Int
foreign import ccall "prims.h primMulInt" (*) :: Int -> Int -> Int
foreign import ccall "prims.h primQuotInt" quot :: Int -> Int -> Int
foreign import ccall "prims.h primRemInt" rem :: Int -> Int -> Int
foreign import ccall "prims.h primDivInt" div :: Int -> Int -> Int
foreign import ccall "prims.h primModInt" mod :: Int -> Int -> Int

negate, abs, signum :: Int -> Int
negate n = 0 - n
abs n = if n < 0 then negate n else n
signum n = if n > 0 then 1 else if n < 0 then -1 else 0

subtract :: Int -> Int -> Int
subtract m n = n - m

even, odd :: Int -> Bool
even n = n `rem` 2 == 0
odd n = not (even n)

gcd, lcm :: Int -> Int -> Int
gcd m n
  | m == 0 && n == 0 = error "Prelude.gcd 0 0"
  | otherwise = gcd' (abs m) (abs n)
  where gcd' m n = if n == 0 then m else gcd' n (m `rem` n)
lcm m n
  | m == 0 || n == 0 = 0
  | otherwise = abs ((m `quot` gcd m n) * n)

(^) :: Int -> Int -> Int
x ^ n
  | n == 0 = 1
  | n > 0  = f x (n - 1) x
  | otherwise = error "Prelude.^: negative exponent"
  where f x n y = if n == 0 then y else g x n y
        g x n y =
          if even n then g (x * x) (n `quot` 2) y else f x (n - 1) (x * y)


data Float
foreign import ccall "prims.h primAddFloat" (+.) :: Float -> Float -> Float
foreign import ccall "prims.h primSubFloat" (-.) :: Float -> Float -> Float
foreign import ccall "prims.h primMulFloat" (*.) :: Float -> Float -> Float
foreign import ccall "prims.h primDivFloat" (/.) :: Float -> Float -> Float

negateFloat, absFloat, signumFloat :: Float -> Float
negateFloat f = 0.0 -. f
absFloat f = if f < 0.0 then negateFloat f else f
signumFloat f = if f > 0.0 then 1.0 else if f < 0.0 then -1.0 else 0.0

subtractFloat :: Float -> Float -> Float
subtractFloat f g = g -. f

(^.) :: Float -> Int -> Float
x ^. n
  | n == 0 = 1
  | n > 0  = f x (n - 1) x
  | otherwise = error "Prelude.^.: negative exponent"
  where f x n y = if n == 0 then y else g x n y
        g x n y =
          if even n then g (x *. x) (n `quot` 2) y else f x (n - 1) (x *. y)

(^^.) :: Float -> Int -> Float
x ^^. n = if n >= 0 then x ^. n else 1 /. x ^. (-n)


-- conversions
foreign import ccall "prims.h primFloat" floatFromInt  :: Int -> Float
foreign import ccall "prims.h primTrunc" truncateFloat :: Float -> Int
foreign import ccall "prims.h primRound" roundFloat    :: Float -> Int


--- Generates an infinite sequence of ascending integers.
enumFrom               :: Int -> [Int]                   -- [n..]
enumFrom n             = iterate (1 +) n

--- Generates an infinite sequence of integers with a particular in/decrement.
enumFromThen           :: Int -> Int -> [Int]            -- [n1,n2..]
enumFromThen n1 n2     = iterate ((n2 - n1) +) n1

--- Generates a sequence of ascending integers.
enumFromTo             :: Int -> Int -> [Int]            -- [n..m]
enumFromTo n m         = takeWhile (m >=) (enumFrom n)

--- Generates a sequence of integers with a particular in/decrement.
enumFromThenTo         :: Int -> Int -> Int -> [Int]     -- [n1,n2..m]
enumFromThenTo n1 n2 m =
  takeWhile (if n1 <= n2 then (m >=) else (m <=)) (enumFromThen n1 n2)


--- Equational constraint
foreign import primitive (=:=) :: a -> a -> Bool

--- Disequality constraint
foreign import primitive (=/=) :: a -> a -> Bool

--- Lazy unification (for function patterns only)
-- To do: This should not be exported from the Prelude, but from module Unsafe
foreign import primitive (=:<=) :: a -> a -> Bool

--- Lazy unification (for function patterns only)
-- To do: This should not be exported from the Prelude, but from module Unsafe
foreign import primitive (==<=) :: a -> a -> Bool


--- Concurrent conjunction of constraints
--- NB The definition of (&) is equivalent to True & True = True,
--- but with both arguments being evaluated concurrently
foreign import primitive (&) :: Bool -> Bool -> Bool

--- Constrained expression. (c &> e) is evaluated by first solving c
--- and then evaluating e.
(&>) :: Bool -> a -> a
True &> x = x


-- Maybe type

data Maybe a = Nothing | Just a

maybe		   :: b -> (a -> b) -> Maybe a -> b
maybe z _ Nothing  = z
maybe _ f (Just x) = f x


-- Either type

data Either a b = Left a | Right b

either		     :: (a -> c) -> (b -> c) -> Either a b -> c
either f _ (Left x)  = f x
either _ g (Right x) = g x


-- Monadic IO

data IO a  -- conceptually: World -> (a,World)

type FilePath = String

done :: IO ()
done = return ()

foreign import primitive return :: a -> IO a
foreign import primitive (>>)   :: IO a -> IO b        -> IO b
foreign import primitive (>>=)  :: IO a -> (a -> IO b) -> IO b

--- Raise an error in the IO monad
fail :: String -> IO a
fail s = ioError ({-userError-} s)

--- Action that (lazily) reads file and returns its contents.
readFile :: FilePath -> IO String
readFile fn = openFile fn ReadMode >>= hGetContents

--- Actions that writes a file.
writeFile :: FilePath -> String -> IO ()
writeFile fn str = bracket (openFile fn WriteMode) hClose (flip hPutStr str)

--- Actions that appends a string to a file.
appendFile :: FilePath -> String -> IO ()
appendFile fn str = bracket (openFile fn AppendMode) hClose (flip hPutStr str)

--- Action to read a single character from stanard input.
getChar :: IO Char
getChar = hGetChar stdin

--- Action to read a single line from standard input.
getLine :: IO String
getLine = hGetLine stdin

--- Action that (lazily) reads all of standard input.
getContents :: IO String
getContents = hGetContents stdin

--- Action to print a character on stdout.
putChar :: Char -> IO ()
putChar = hPutChar stdout

--- Action to print a string on stdout.
putStr :: String -> IO ()
putStr = hPutStr stdout
 
--- Action to print a string with a newline on stdout.
putStrLn :: String -> IO ()
putStrLn = hPutStrLn stdout

--- Converts a term into a string and prints it.
print   :: a -> IO ()
print t = putStrLn (show t)

--- Convert a simple stream filter into an I/O program
--- Note: interact closes the standard input
interact   :: (String -> String) -> IO ()
interact f = getContents >>= putStr . f

--- Solves a constraint as an I/O action.
--- Note: the constraint should be always solvable in a deterministic way
doSolve :: Bool -> IO ()
doSolve b | b = done


-- IO monad auxiliary functions

--- Execute a sequence of I/O actions and collect all results in a list
sequenceIO :: [IO a] -> IO [a]
sequenceIO = foldr mcons (return [])
  where mcons m ms = do x <- m; xs <- ms; return (x:xs)

--- Execute a sequence of I/O actions and ignore the result
sequenceIO_ :: [IO a] -> IO ()
sequenceIO_ = foldr (>>) done

--- Map an I/O action function on a list of elements.
--- The results are of all I/O actions are collected in a list.
mapIO :: (a -> IO b) -> [a] -> IO [b]
mapIO f ms = sequenceIO (map f ms)

--- Map an I/O action function on a list of elements.
--- The results are of all I/O actions are ignored.
mapIO_ :: (a -> IO b) -> [a] -> IO ()
mapIO_ f ms = sequenceIO_ (map f ms)


-- IO Exceptions
-- At present exception values are strings, this will change in the future
type IOError = String

--- Raise an I/O exception
foreign import primitive ioError :: IOError -> IO a

--- Establish an exception handler for the execution of an action
foreign import primitive catch :: IO a -> (IOError -> IO a) -> IO a


----------------------------------------------------------------
-- Encapsulated search:

--- Basic search control operator.
foreign import primitive try :: (a -> Bool) -> [a -> Bool]


--- Non-deterministic choice par excellence
(?)   :: a -> a -> a
x ? _ = x
_ ? y = y


--- Evaluates to a fresh free variable.
unknown :: a
unknown = x where x free


-- Type of constraints (included for backward compatibility)
type Success = Bool

success :: Success
success = True


--- Inject operator which adds the application of the unary
--- procedure p to the search variable to the search goal
--- taken from Oz. p x comes before g x to enable a test+generate
--- form in a sequential implementation.
inject	   :: (a -> Bool) -> (a -> Bool) -> (a -> Bool)
inject g p = \x -> p x & g x

--- Compute all solutions via a left-to-right strategy.
solveAll   :: (a -> Bool) -> [a -> Bool]
solveAll g = all (try g) []
  where all []           gs  = all2 gs
        all [g]          gs  = g : all2 gs 
        all (g:gs@(_:_)) gs' = all (try g) (gs ++ gs')

        all2 []     = []
        all2 (g:gs) = all (try g) gs


--- Get the first solution via left-to-right strategy.
once :: (a -> Bool) -> a -> Bool
once g = head (solveAll g)


--- Get the best solution via left-to-right strategy according to
--- a specified operator that can always take a decision which
--- of two solutions is better.
--- In general, the comparison operation should be rigid in its arguments!
best    :: (a -> Bool) -> (a -> a -> Bool) -> [a -> Bool]
best g compare = bestHelp [] (try g) []
 where
   bestHelp [] []     curbest = curbest
   bestHelp [] (y:ys) curbest = evalB (try (constrain y curbest)) ys curbest
   bestHelp (x:xs) ys curbest = evalA (try x) xs ys curbest
   
   evalB []         ys curbest = bestHelp [] ys curbest
   evalB [newbest]  ys _       = bestHelp [] ys [newbest]
   evalB (x1:x2:xs) ys curbest = bestHelp (x1:x2:xs) ys curbest
   
   evalA []         xs ys curbest = bestHelp xs ys curbest
   evalA [newbest]  xs ys _       = bestHelp [] (xs++ys) [newbest]
   evalA (u1:u2:us) xs ys curbest = bestHelp ((u1:u2:us)++xs) ys curbest
   
   constrain b []        = b
   constrain b [curbest] =
       inject b (\x -> let y free in curbest y & compare x y)


--- Get all solutions via left-to-right strategy and unpack
--- the values from the lambda-abstractions.
--- Similar to Prolog's findall.
findall :: (a -> Bool) -> [a]
findall g = map unpack (solveAll g)

--- Get the first solution via left-to-right strategy
--- and unpack the values from the search goals.
findfirst :: (a -> Bool) -> a
findfirst g = head (findall g)


--- Show the solution of a solved constraint.
browse  :: (a -> Bool) -> IO ()
browse g = putStr (show (unpack g))

--- Unpack solutions from a list of lambda abstractions and write 
--- them to the screen.
browseList :: [a -> Bool] -> IO ()
browseList [] = done
browseList (g:gs) = browse g >> putChar '\n' >> browseList gs


--- Unpack a solution's value from a (solved) search goal.
unpack  :: (a -> Bool) -> a
unpack g | g x  = x  where x free
