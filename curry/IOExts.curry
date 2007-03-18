-- $Id: IOExts.curry 2126 2007-03-18 21:36:17Z wlux $
--
-- Copyright (c) 2004-2007, Wolfgang Lux
-- See ../LICENSE for the full license.

module IOExts(fixIO, unsafePerformIO,unsafeInterleaveIO,
 	      IORef, newIORef,readIORef,writeIORef,modifyIORef,
	      IOArray, newIOArray,boundsIOArray,readIOArray,writeIOArray,
	      freezeIOArray,thawIOArray, unsafeFreezeIOArray,unsafeThawIOArray,
 	      hIsTerminalDevice, openFd, openProcess, pClose, connectTcpSocket,
	      trace, performGC) where

import Array
import IO
import IOVector
import Monad
import Unsafe(unsafePerformIO,unsafeInterleaveIO,trace)

-- used to prevent premature evaluation of foreign function arguments
data Wrap a = Wrap a

-- monadic fix-point operator
foreign import primitive fixIO :: (a -> IO a) -> IO a

-- mutable references
data IORef a

newIORef :: a -> IO (IORef a)
newIORef x = primNewIORef (Wrap x)
  where foreign import rawcall "refs.h" primNewIORef :: Wrap a -> IO (IORef a)

foreign import rawcall "refs.h primReadIORef" readIORef :: IORef a -> IO a

writeIORef :: IORef a -> a -> IO ()
writeIORef r x = primWriteIORef r (Wrap x)
  where foreign import rawcall "refs.h"
  		       primWriteIORef :: IORef a -> Wrap a -> IO ()

modifyIORef :: IORef a -> (a -> a) -> IO ()
modifyIORef r f = readIORef r >>= \x -> writeIORef r (f x)

-- mutable arrays
data IOArray a = IOArray (Int,Int) (IOVector a)

newIOArray :: (Int,Int) -> a -> IO (IOArray a)
newIOArray b x =
  do
    v <- newIOVector (rangeSize b) x
    return (IOArray b v)

boundsIOArray :: IOArray a -> (Int,Int)
boundsIOArray (IOArray b _) = b

readIOArray :: IOArray a -> Int -> IO a
readIOArray (IOArray b v) i = readIOVector v (index b i)

writeIOArray :: IOArray a -> Int -> a -> IO ()
writeIOArray (IOArray b v) i x = writeIOVector v (index b i) x

freezeIOArray :: IOArray a -> IO (Array a)
freezeIOArray (IOArray b v) = copyIOVector v >>= unsafeArray b

thawIOArray :: Array a -> IO (IOArray a)
thawIOArray a =
  do
    v <- unsafeVector a
    v' <- copyIOVector v
    return (IOArray (bounds a) v')

unsafeFreezeIOArray :: IOArray a -> IO (Array a)
unsafeFreezeIOArray (IOArray b v) = unsafeArray b v

unsafeThawIOArray :: Array a -> IO (IOArray a)
unsafeThawIOArray a =
  do
    v <- unsafeVector a
    return (IOArray (bounds a) v)

-- assorted IO functions
foreign import ccall unsafe "files.h primHIsTerminalDevice"
	       hIsTerminalDevice :: Handle -> IO Bool

foreign import ccall unsafe "files.h primOpenFd"
	       openFd :: Int -> IOMode -> IO Handle

openProcess :: String -> IOMode -> IO Handle
openProcess cmd mode = (primOpenProcess $## cmd) mode
  where foreign import ccall unsafe "files.h"
  		       primOpenProcess :: String -> IOMode -> IO Handle

foreign import ccall unsafe "files.h primPClose"
	       pClose :: Handle -> IO Int

connectTcpSocket :: String -> Int -> IOMode -> IO Handle
connectTcpSocket host port mode = (primConnectTcpSocket $## host) port mode
  where foreign import ccall unsafe "files.h"
  		       primConnectTcpSocket :: String -> Int -> IOMode -> IO Handle

-- perform a garbage collection
foreign import ccall "primPerformGC" performGC :: IO ()
