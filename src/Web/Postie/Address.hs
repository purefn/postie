
module Web.Postie.Address(
    Address          -- | Represents an email address
  , address          -- | Returns address from local and domain part
  , addressLocalPart -- | Returns local part of address
  , addressDomain    -- | Retuns domain part of address

  , toByteString     -- | Resulting ByteString has format localPart\@domainPart.
  , toLazyByteString -- | Resulting Lazy.ByteString has format localPart\@domainPart.

  , parseAddress     -- | Parses a ByteString to Address
  , addrSpec
  ) where

import Data.String
import Data.Maybe (fromMaybe)
import Data.Typeable (Typeable)
import Data.Attoparsec.ByteString.Char8
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy.Char8 as LBS

import Control.Applicative
import Control.Monad (void)

data Address = Address {
    addressLocalPart :: !BS.ByteString
  , addressDomain    :: !BS.ByteString
  }
  deriving (Eq, Ord, Typeable)

instance Show Address where
  show = BS.unpack . toByteString

instance IsString Address where
  fromString = fromMaybe (error "invalid email literal") . parseAddress . BS.pack

address :: BS.ByteString -> BS.ByteString -> Address
address = Address

toByteString :: Address -> BS.ByteString
toByteString (Address l d) = BS.concat [l, BS.singleton '@', d]

toLazyByteString :: Address -> LBS.ByteString
toLazyByteString (Address l d) = LBS.fromChunks [l, BS.singleton '@', d]

parseAddress :: BS.ByteString -> Maybe Address
parseAddress = maybeResult . parse addrSpec

-- | Address Parser. Borrowed form email-validate-2.0.1. Parser for email address.
addrSpec :: Parser Address
addrSpec = do
  localPart <- local
  _ <- char '@'
  domainPart <- domain
  return (Address localPart domainPart)

local :: Parser BS.ByteString
local = dottedAtoms

domain :: Parser BS.ByteString
domain = dottedAtoms <|> domainLiteral

dottedAtoms :: Parser BS.ByteString
dottedAtoms = BS.intercalate (BS.singleton '.') <$>
  (optional cfws *> (atom <|> quotedString) <* optional cfws)  `sepBy1` char '.'

atom :: Parser BS.ByteString
atom = takeWhile1 isAtomText

isAtomText :: Char -> Bool
isAtomText x = isAlphaNum x || inClass "!#$%&'*+/=?^_`{|}~-" x

domainLiteral :: Parser BS.ByteString
domainLiteral = (BS.cons '[' . flip BS.snoc ']' . BS.concat) <$> between (optional cfws *> char '[') (char ']' <* optional cfws)
  (many (optional fws >> takeWhile1 isDomainText) <* optional fws)

isDomainText :: Char -> Bool
isDomainText x = inClass "\33-\90\94-\126" x || isObsNoWsCtl x

quotedString :: Parser BS.ByteString
quotedString = (\x -> BS.concat [BS.singleton '"', BS.concat x, BS.singleton '"']) <$> between (char '"') (char '"')
  (many (optional fws >> quotedContent) <* optional fws)

quotedContent :: Parser BS.ByteString
quotedContent = takeWhile1 isQuotedText <|> quotedPair

isQuotedText :: Char -> Bool
isQuotedText x = inClass "\33\35-\91\93-\126" x || isObsNoWsCtl x

quotedPair :: Parser BS.ByteString
quotedPair = (BS.cons '\\' . BS.singleton) <$> (char '\\' *> (vchar <|> wsp <|> lf <|> cr <|> obsNoWsCtl <|> nullChar))

cfws :: Parser ()
cfws = ignore $ many (comment <|> fws)

fws :: Parser ()
fws = ignore $
  ignore (wsp1 >> optional (crlf >> wsp1))
  <|> ignore (many1 (crlf >> wsp1))

ignore :: Parser a -> Parser ()
ignore = void

between :: Parser l -> Parser r -> Parser x -> Parser x
between l r x = l *> x <* r

comment :: Parser ()
comment = ignore (between (char '(') (char ')') $
  many (ignore commentContent <|> fws))

commentContent :: Parser ()
commentContent = skipWhile1 isCommentText <|> ignore quotedPair <|> comment

isCommentText :: Char -> Bool
isCommentText x = inClass "\33-\39\42-\91\93-\126" x || isObsNoWsCtl x

nullChar :: Parser Char
nullChar = char '\0'

skipWhile1 :: (Char -> Bool) -> Parser ()
skipWhile1 x = satisfy x >> skipWhile x

wsp1 :: Parser()
wsp1 = skipWhile1 isWsp

wsp :: Parser Char
wsp = satisfy isWsp

isWsp :: Char -> Bool
isWsp x = x == ' ' || x == '\t'


isAlphaNum :: Char -> Bool
isAlphaNum x = isDigit x || isAlpha_ascii x

cr :: Parser Char
cr = char '\r'

lf :: Parser Char
lf = char '\n'

crlf :: Parser ()
crlf = cr >> lf >> return ()

isVchar :: Char -> Bool
isVchar = inClass "\x21-\x7e"

vchar :: Parser Char
vchar = satisfy isVchar

isObsNoWsCtl :: Char -> Bool
isObsNoWsCtl = inClass "\1-\8\11-\12\14-\31\127"

obsNoWsCtl :: Parser Char
obsNoWsCtl = satisfy isObsNoWsCtl
