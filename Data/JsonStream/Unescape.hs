{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE MagicHash                #-}
{-# LANGUAGE UnliftedFFITypes         #-}
{-# LANGUAGE CPP                      #-}

module Data.JsonStream.Unescape (
  unescapeText
) where

import           Control.Exception          (evaluate, throw, try)
import           Control.Monad.ST.Unsafe    (unsafeIOToST, unsafeSTToIO)
import           Data.ByteString            as B
import           Data.ByteString.Internal   as B hiding (c2w)
import qualified Data.Text.Array            as A
import           Data.Text.Encoding.Error   (UnicodeException (..))
import           Data.Text.Internal         (Text (..))
import           Data.Text.Internal.Private (runText)
import           Data.Text.Unsafe           (unsafeDupablePerformIO)
import           Data.Word                  (Word8)
import           Foreign.C.Types            (CInt (..), CSize (..))
import           Foreign.ForeignPtr         (withForeignPtr)
import           Foreign.Marshal.Utils      (with)
import           Foreign.Ptr                (Ptr, plusPtr)
import           Foreign.Storable           (peek)
import           GHC.Base                   (MutableByteArray#)

foreign import ccall unsafe "_jstream_decode_string" c_js_decode
    :: MutableByteArray# s -> Ptr CSize
    -> Ptr Word8 -> Ptr Word8 -> IO CInt

unescapeText' :: ByteString -> Text
unescapeText' (PS fp off len) = runText $ \done -> do
  let go dest = withForeignPtr fp $ \ptr ->
        with (0::CSize) $ \destOffPtr -> do
          let end = ptr `plusPtr` (off + len)
              loop curPtr = do
                res <- c_js_decode (getByteArray dest) destOffPtr curPtr end
                case res of
                  0 -> do
                    n <- peek destOffPtr
                    unsafeSTToIO (done dest (fromIntegral n))
                  _ ->
                    throw (DecodeError desc Nothing)
          loop (ptr `plusPtr` off)
  (unsafeIOToST . go) =<< A.new len
 where
  desc = "Data.JsonStream.Unescape.unescapeText': Invalid UTF-8 stream"
#if MIN_VERSION_text(2,0,0)
  getByteArray (A.MutableByteArray arr) = arr
#else
  getByteArray = A.maBA
#endif
{-# INLINE unescapeText' #-}

unescapeText :: ByteString -> Either UnicodeException Text
unescapeText = unsafeDupablePerformIO . try . evaluate . unescapeText'
{-# INLINE unescapeText #-}
