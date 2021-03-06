-- $Id: Unsafe.curry 3206 2016-06-07 07:17:22Z wlux $
--
-- Copyright (c) 2002-2016, Wolfgang Lux
-- See ../LICENSE for the full license.

module Unsafe(unsafePerformIO, unsafeInterleaveIO, trace,
	      spawnConstraint, isVar) where
import IO

foreign import primitive unsafePerformIO :: IO a -> a

unsafeInterleaveIO :: IO a -> IO a
unsafeInterleaveIO m = return (unsafePerformIO m)

trace :: String -> a -> a
trace msg x = unsafePerformIO (hPutStrLn stderr msg) `seq` x

foreign import primitive spawnConstraint :: Bool -> a -> a

foreign import primitive isVar :: a -> Bool

