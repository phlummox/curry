-- $Id: IOVector.curry 2127 2007-03-18 21:43:50Z wlux $
--
-- Copyright (c) 2004-2007, Wolfgang Lux
-- See ../LICENSE for the full license.

module IOVector(IOVector, newIOVector, copyIOVector, readIOVector,
		writeIOVector, lengthIOVector) where

-- used to prevent premature evaluation of foreign function arguments
data Wrap a = Wrap a

-- Primitive vectors

data IOVector a

newIOVector :: Int -> a -> IO (IOVector a)
newIOVector n x = primNewIOVector n (Wrap x)
  where foreign import rawcall "vector.h"
  		       primNewIOVector :: Int -> Wrap a -> IO (IOVector a)

foreign import rawcall "vector.h primCopyIOVector"
	       copyIOVector :: IOVector a -> IO (IOVector a)

foreign import rawcall "vector.h primReadIOVector"
	       readIOVector :: IOVector a -> Int -> IO a

writeIOVector :: IOVector a -> Int -> a -> IO ()
writeIOVector v i x = primWriteIOVector v i (Wrap x)
  where foreign import rawcall "vector.h"
  		       primWriteIOVector :: IOVector a -> Int -> Wrap a -> IO ()

foreign import rawcall "vector.h primLengthIOVector"
	       lengthIOVector :: IOVector a -> Int
