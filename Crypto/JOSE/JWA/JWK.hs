-- This file is part of jose - web crypto library
-- Copyright (C) 2013  Fraser Tweedale
--
-- jose is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Crypto.JOSE.JWA.JWK where

import Control.Applicative
import Data.Maybe
import Data.Tuple
import GHC.Generics (Generic)

import Data.Aeson
import Data.Hashable
import qualified Data.HashMap.Strict as M

import qualified Crypto.JOSE.Types as Types


--
-- JWA §5.1.  "kty" (Key Type) Parameter Values
--

parseKty t e s = if s == e then pure t else fail "bad kty"

-- Recommended+
data EC = EC deriving (Eq, Show)
instance FromJSON EC where parseJSON = withText "kty" (parseKty EC "EC")
instance ToJSON EC where toJSON EC = String "EC"

-- Required
data RSA = RSA deriving (Eq, Show)
instance FromJSON RSA where parseJSON = withText "kty" (parseKty RSA "RSA")
instance ToJSON RSA where toJSON RSA = String "RSA"

-- Required
data Oct = Oct deriving (Eq, Show)
instance FromJSON Oct where parseJSON = withText "kty" (parseKty Oct "Oct")
instance ToJSON Oct where toJSON Oct = String "Oct"


--
-- JWA §5.2.1.1.  "crv" (Curve) Parameter
--

data Crv = P256 | P384 | P521
  deriving (Eq, Show)

instance Hashable Crv

crvList = [
  ("P-256", P256),
  ("P-384", P384),
  ("P-521", P521)
  ]
crvMap = M.fromList crvList
crvMap' = M.fromList $ map swap crvList

instance FromJSON Crv where
  parseJSON (String s) = case M.lookup s crvMap of
    Just v -> pure v
    Nothing -> fail "undefined EC crv"

instance ToJSON Crv where
  toJSON crv = String $ M.lookupDefault "?" crv crvMap'


--
-- JWA §5.3.2.7.  "oth" (Other Primes Info) Parameter
--

data RSAPrivateKeyOthElem = RSAPrivateKeyOthElem {
  rOth :: Types.Base64Integer,
  dOth :: Types.Base64Integer,
  tOth :: Types.Base64Integer
  }
  deriving (Eq, Show)

instance FromJSON RSAPrivateKeyOthElem where
  parseJSON (Object o) = RSAPrivateKeyOthElem <$>
    o .: "r" <*>
    o .: "d" <*>
    o .: "t"

instance ToJSON RSAPrivateKeyOthElem where
  toJSON (RSAPrivateKeyOthElem r d t) = object ["r" .= r, "d" .= d, "t" .= t]


--
-- JWA §5.3.2.  JWK Parameters for RSA Private Keys
--

data RSAPrivateKeyOptionalParameters = RSAPrivateKeyOptionalParameters {
  p :: Maybe Types.Base64Integer,
  q :: Maybe Types.Base64Integer,
  dp :: Maybe Types.Base64Integer,
  dq :: Maybe Types.Base64Integer,
  qi :: Maybe Types.Base64Integer,
  oth :: Maybe [RSAPrivateKeyOthElem] -- TODO oth must not be empty array
  }
  deriving (Eq, Show)

instance FromJSON RSAPrivateKeyOptionalParameters where
  parseJSON (Object o) = RSAPrivateKeyOptionalParameters <$>
    o .: "p" <*>
    o .: "q" <*>
    o .: "dp" <*>
    o .: "dq" <*>
    o .: "qi" <*>
    o .:? "oth"

instance ToJSON RSAPrivateKeyOptionalParameters where
  toJSON (RSAPrivateKeyOptionalParameters p q dp dq qi oth) = object $ [
    "p" .= p
    , "q" .= q
    , "dp" .= dp
    , "dq" .= dq
    , "dq" .= qi
    ] ++ (map ("oth" .=) $ maybeToList oth)


--
-- JWA §5.  Cryptographic Algorithms for JWK
--

objectPairs (Object o) = M.toList o


data ECKeyParameters =
  ECPrivateKeyParameters {
    d :: Types.SizedBase64Integer
    }
  | ECPublicKeyParameters {
    crv :: Crv,
    x :: Types.SizedBase64Integer,
    y :: Types.SizedBase64Integer
    }
  deriving (Eq, Show)

instance FromJSON ECKeyParameters where
  parseJSON = withObject "EC" (\o ->
    ECPrivateKeyParameters    <$> o .: "d"
    <|> ECPublicKeyParameters <$> o .: "crv" <*> o .: "x" <*> o .: "y")

instance ToJSON ECKeyParameters where
  toJSON (ECPrivateKeyParameters d) = object ["d" .= d]
  toJSON (ECPublicKeyParameters crv x y) = object [
    "crv" .= crv
    , "x" .= x
    , "y" .= y
    ]


data RSAKeyParameters =
  RSAPrivateKeyParameters {
    d' :: Types.SizedBase64Integer,
    optionalParameters :: Maybe RSAPrivateKeyOptionalParameters
    }
  | RSAPublicKeyParameters {
    n :: Types.Base64Integer,
    e :: Types.Base64Integer
    }
  deriving (Eq, Show)

instance FromJSON RSAKeyParameters where
  parseJSON = withObject "RSA" (\o ->
    RSAPrivateKeyParameters    <$> o .: "d" <*> parseJSON (Object o)
    <|> RSAPublicKeyParameters <$> o .: "n" <*> o .: "e")

instance ToJSON RSAKeyParameters where
  toJSON (RSAPrivateKeyParameters d params) = object $
    ["d" .= d] ++ (objectPairs $ toJSON params)
  toJSON (RSAPublicKeyParameters n e) = object ["n" .= n, "e" .= e]


data KeyMaterial =
  ECKeyMaterial EC ECKeyParameters
  | RSAKeyMaterial RSA RSAKeyParameters
  | OctKeyMaterial Oct Types.Base64Integer
  deriving (Eq, Show)

instance FromJSON KeyMaterial where
  parseJSON = withObject "KeyMaterial" (\o ->
    ECKeyMaterial      <$> o .: "kty" <*> parseJSON (Object o)
    <|> RSAKeyMaterial <$> o .: "kty" <*> parseJSON (Object o)
    <|> OctKeyMaterial <$> o .: "kty" <*> o .: "k")

instance ToJSON KeyMaterial where
  toJSON (ECKeyMaterial k p)  = object $ ["kty" .= k] ++ objectPairs (toJSON p)
  toJSON (RSAKeyMaterial k p) = object $ ["kty" .= k] ++ objectPairs (toJSON p)
  toJSON (OctKeyMaterial k i) = object ["kty" .= k, "k" .= i]
