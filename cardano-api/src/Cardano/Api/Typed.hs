{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ConstraintKinds #-}

{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

-- The Shelley ledger uses promoted data kinds which we have to use, but we do
-- not export any from this API. We also use them unticked as nature intended.
{-# LANGUAGE DataKinds #-}
{-# OPTIONS_GHC -Wno-unticked-promoted-constructors #-}

-- | This module provides a library interface for interacting with Cardano as
-- a user of the system.
--
-- It is intended to be used to write tools and 
--
-- In the interest of simplicity it glosses over some details of the system.
-- Most simple tools should be able to work just using this interface,
-- however you can go deeper and expose the types from the underlying libraries
-- using "Cardano.Api.Byron" or "Cardano.Api.Shelley".
--
module Cardano.Api.Typed (
    -- * Eras
    Byron,
    Shelley,
    HasTypeProxy(..),
    AsType(..),

    -- * Cryptographic key interface
    -- $keys
    Key,
    VerificationKey(..),
    SigningKey(..),
    getVerificationKey,
--  verificationKeyHash,
    castVerificationKey,
    castSigningKey,

    -- ** Generating keys
    generateSigningKey,
    deterministicSigningKey,
    deterministicSigningKeySeedSize,
    Crypto.Seed,
    Crypto.mkSeedFromBytes,
    Crypto.readSeedFromSystemEntropy,

    -- ** Hashes
    -- | In Cardano most keys are identified by their hash, and hashes are
    -- used in many other places.
    Hash,
    castHash,

    -- * Payment addresses
    -- | Constructing and inspecting normal payment addresses
    Address,
    NetworkId,
    -- * Byron addresses
    makeByronAddress,
    ByronKey,
    -- * Shelley addresses
    makeShelleyAddress,
    PaymentCredential(..),
    StakeCredentialReference(..),
    PaymentKey,

    -- * Stake addresses
    -- | Constructing and inspecting stake addresses
    StakeAddress(..),
    StakeCredential(..),
    makeStakeAddress,

    -- * Building transactions
    -- | Constructing and inspecting transactions
    TxUnsigned(..),
    TxId,
    getTxId,
    TxIn(..),
    TxOut(..),
    TxIx,
    Lovelace,
    makeByronTransaction,
    makeShelleyTransaction,
    SlotNo,
    TxOptional(..),

    -- * Signing transactions
    -- | Creating transaction witnesses one by one, or all in one go.
    TxSigned(..),
    getTxUnsigned,
    getTxWitnesses,

    -- ** Signing in one go
    signByronTransaction,
    signShelleyTransaction,

    -- ** Incremental signing and separate witnesses
    makeSignedTransaction,
    Witness(..),
    byronKeyWitness,
    shelleyKeyWitness,
    shelleyScriptWitness,

    -- * Fee calculation

    -- * Registering stake address and delegating
    -- | Certificates that are embedded in transactions for registering and
    -- unregistering stake address, and for setting the stake pool delegation
    -- choice for a stake address.

    -- * Registering stake pools
    -- | Certificates that are embedded in transactions for registering and
    -- retiring stake pools. This incldes updating the stake pool parameters.

    -- * Scripts
    -- | Both 'PaymentCredential's and 'StakeCredential's can use scripts.
    -- Shelley supports multi-signatures via scripts.

    -- ** Script addresses
    -- | Making addresses from scripts.

    -- ** Multi-sig scripts
    -- | Making multi-signature scripts.

    -- * Serialisation
    -- | Support for serialising data in JSON, CBOR and text files.
    -- ** CBOR
    ToCBOR,
    FromCBOR,
    serialiseToCBOR,
    deserialiseFromCBOR,

    -- ** JSON
    ToJSON,
    FromJSON,
    serialiseToJSON,
    deserialiseFromJSON,

    -- ** Raw binary
    -- | Some types have a natural raw binary format.
    serialiseToRawBytes,
    deserialiseFromRawBytes,
    serialiseToRawBytesHex,
    deserialiseFromRawBytesHex,

    -- ** Text envelope
    -- | Support for a envelope file format with text headers and a hex-encoded
    -- binary payload.
    HasTextEnvelope,
    serialiseToTextEnvelope,
    deserialiseFromTextEnvelope,
    readFileTextEnvelope,
    writeFileTextEnvelope,
    -- *** Reading one of several key types
    FromSomeType(..),
    deserialiseFromTextEnvelopeAnyOf,
    readFileTextEnvelopeAnyOf,

    -- * Errors
    Error,
    throwErrorAsException,

    -- * Node interaction
    -- | Operations that involve talking to a local Cardano node.

    -- ** Queries
    -- ** Protocol parameters
    -- ** Submitting transactions

    -- * Node operation
    -- | Support for the steps needed to operate a node, including the
    -- operator's offline keys, operational KES and VRF keys, and operational
    -- certificates.

    -- ** Stake pool operator's keys
    StakePoolKey,

    -- ** KES keys
    KesKey,

    -- ** VRF keys
    VrfKey,

    -- ** Operational certificates

    -- * Genesis file
    -- | Types and functions needed to inspect or create a genesis file.
    GenesisKey,
    GenesisDelegateKey,

    -- * Special transactions
    -- | There are various additional things that can be embedded in a
    -- transaction for special operations.

  ) where


import Prelude

import           Data.Proxy (Proxy(..))
import           Data.Kind (Constraint)
import           Data.Maybe
import           Data.List as List
--import           Data.Either
import           Data.String (IsString(fromString))

import           Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Base16 as Base16

--import Control.Monad
--import Control.Monad.IO.Class
--import           Control.Monad.Trans.Except
import           Control.Monad.Trans.Except.Extra
import           Control.Exception (Exception(..), IOException, throwIO)

import qualified Data.Aeson as Aeson
import           Data.Aeson (ToJSON(..), FromJSON(..))


--
-- Common types, consensus, network
--
import qualified Cardano.Binary as CBOR
import           Cardano.Binary (ToCBOR(..), FromCBOR(..))
import           Cardano.Slotting.Slot (SlotNo)
import           Ouroboros.Network.Magic (NetworkMagic(..))

--
-- Crypto API used by consensus and Shelley (and should be used by Byron)
--
import qualified Cardano.Crypto.Seed        as Crypto
--import qualified Cardano.Crypto.Hash.Class  as Crypto
import qualified Cardano.Crypto.DSIGN.Class as Crypto
import qualified Cardano.Crypto.KES.Class   as Crypto
import qualified Cardano.Crypto.VRF.Class   as Crypto

--
-- Byron imports
--
import qualified Cardano.Crypto.Signing as Byron
import qualified Cardano.Chain.Common as Byron
--import qualified Cardano.Chain.UTxO   as Byron

--
-- Shelley imports
--
import qualified Ouroboros.Consensus.Shelley.Protocol.Crypto as Shelley
--import qualified Shelley.Spec.Ledger.BaseTypes               as Shelley
--import qualified Shelley.Spec.Ledger.Coin                    as Shelley
--import qualified Shelley.Spec.Ledger.Delegation.Certificates as Shelley
import qualified Shelley.Spec.Ledger.Keys                    as Shelley
import qualified Shelley.Spec.Ledger.TxData                  as Shelley
--import qualified Shelley.Spec.Ledger.Tx                      as Shelley
import qualified Shelley.Spec.Ledger.PParams                 as Shelley

-- TODO: replace the above with
--import qualified Cardano.Api.Byron   as Byron
--import qualified Cardano.Api.Shelley as Shelley

--
-- Other config and common types
--
import qualified Cardano.Config.TextView as TextView


-- ----------------------------------------------------------------------------
-- Cardano eras, sometimes we have to distinguish them
--

-- | A type used as a tag to distinguish the Byron era.
data Byron

-- | A type used as a tag to distinguish the Shelley era.
data Shelley


class HasTypeProxy t where
  -- | A family of singleton types used in this API to indicate which type to
  -- use where it would otherwise be ambiguous or merely unclear.
  --
  -- Values of this type are passed to 
  --
  data AsType t

  proxyToAsType :: Proxy t -> AsType t


-- ----------------------------------------------------------------------------
-- Keys key keys!
--



-- $keys
-- Cardano has lots of cryptographic keys used for lots of different purposes.
-- Some keys have different representations, but most are just using keys in
-- different roles.
--
-- To allow for the different representations and to avoid mistakes we
-- distinguish the key /role/. These are type level distinctions, so each of
-- these roles is a type level tag.
--

-- | An interface for cryptographic keys used for signatures with a 'SigningKey'
-- and a 'VerificationKey' key.
--
-- This interface does not provide actual signing or verifying functions since
-- this API is concerned with the management of keys: generating and
-- serialising.
--
class Key keyrole where

    -- | The type of cryptographic verification key, for each key role.
    data VerificationKey keyrole :: *

    -- | The type of cryptographic signing key, for each key role.
    data SigningKey keyrole :: *

    -- | Get the corresponding verification key from a signing key.
    getVerificationKey :: SigningKey keyrole -> VerificationKey keyrole

    -- | Generate a 'SigningKey' deterministically, given a 'Crypto.Seed'. The
    -- required size of the seed is given by 'deterministicSigningKeySeedSize'.
    --
    deterministicSigningKey :: AsType keyrole -> Crypto.Seed -> SigningKey keyrole
    deterministicSigningKeySeedSize :: AsType keyrole -> Word

--    verificationKeyHash :: VerificationKey keyrole -> Hash keyrole


-- | Generate a 'SigningKey' using a seed from operating system entropy.
--
generateSigningKey :: Key keyrole => AsType keyrole -> IO (SigningKey keyrole)
generateSigningKey keytype = do
    seed <- Crypto.readSeedFromSystemEntropy seedSize
    return $! deterministicSigningKey keytype seed
  where
    seedSize = deterministicSigningKeySeedSize keytype


-- | Some key roles share the same representation and it is sometimes
-- legitimate to change the role of a key.
--
class CastKeyRole keyroleA keyroleB where

    -- | Change the role of a 'VerificationKey', if the representation permits.
    castVerificationKey :: VerificationKey keyroleA -> VerificationKey keyroleB

    -- | Change the role of a 'SigningKey', if the representation permits.
    castSigningKey :: SigningKey keyroleA -> SigningKey keyroleB


data family Hash keyrole :: *

class CastHash keyroleA keyroleB where

    castHash :: Hash keyroleA -> Hash keyroleB


-- ----------------------------------------------------------------------------
-- Addresses
--

data Address era where

     -- | Byron addresses are valid in both the Byron and Shelley era.
     --
     ByronAddress
       :: Byron.Address
       -> Address era

     -- | Shelley addresses are only valid in the Shelley era.
     --
     ShelleyAddress
       :: PaymentCredential
       -> StakeCredentialReference
       -> NetworkId
       -> Address Shelley

data StakeAddress where

     StakeAddress
       :: StakeCredential
       -> NetworkId
       -> StakeAddress

data NetworkId
       = Mainnet
       | Testnet !NetworkMagic

data PaymentCredential
       = PaymentCredentialByKey    (Hash PaymentKey)
       | PaymentCredentialByScript (Hash Script)

data StakeCredential
       = StakeCredentialByKey    (Hash StakeKey)
       | StakeCredentialByScript (Hash Script)

data StakeCredentialReference
       = StakeCredentialByValue   StakeCredential
       | StakeCredentialByPointer StakeCredentialPointer
       | NoStakeCredential

type StakeCredentialPointer = Shelley.Ptr


makeByronAddress :: VerificationKey ByronKey
                 -> NetworkId
                 -> Address era
makeByronAddress (ByronVerificationKey vk) nid =
    ByronAddress (Byron.makeVerKeyAddress (byronNetworkMagic nid) vk)
  where
    byronNetworkMagic :: NetworkId -> Byron.NetworkMagic
    byronNetworkMagic Mainnet                     = Byron.NetworkMainOrStage
    byronNetworkMagic (Testnet (NetworkMagic nm)) = Byron.NetworkTestnet nm


makeShelleyAddress :: PaymentCredential
                   -> StakeCredentialReference
                   -> NetworkId
                   -> Address Shelley
makeShelleyAddress = ShelleyAddress


makeStakeAddress :: StakeCredential
                 -> NetworkId
                 -> StakeAddress
makeStakeAddress = StakeAddress



-- ----------------------------------------------------------------------------
-- Unsigned transactions
--

data TxUnsigned era where

     ByronTxUnsigned
       :: TxUnsigned Byron

     ShelleyTxUnsigned
       :: TxUnsigned Shelley
       -- we'll include optional metadata here, even though technically it is
       -- placed with the witnesses

data TxId

getTxId :: TxUnsigned era -> TxId
getTxId = undefined

data TxIn = TxIn TxId TxIx

data TxIx

data TxOut era = TxOut (Address era) Lovelace

data Lovelace


makeByronTransaction :: [TxIn] -> [TxOut Byron] -> TxUnsigned Byron
makeByronTransaction = undefined


data TxOptional =
     TxOptional {
       txMetadata        :: Maybe TxMetadata,
       txWithdrawals     :: [(StakeAddress, Lovelace)],
       txCertificates    :: [Certificate],
       txProtocolUpdates :: Maybe ProtocolUpdates
     }

data TxMetadata
data Certificate
type ProtocolUpdates = Shelley.ProposedPPUpdates Shelley.TPraosStandardCrypto

makeShelleyTransaction :: TxOptional
                       -> SlotNo
                       -> Lovelace
                       -> [TxIn]
                       -> [TxOut anyera]
                       -> TxUnsigned Shelley
makeShelleyTransaction = undefined


-- ----------------------------------------------------------------------------
-- Signed transactions
--

data TxSigned era where

     ByronTxSigned
       :: TxSigned Byron

     ShelleyTxSigned
       :: TxSigned Shelley

-- order of signing keys must match txins
signByronTransaction :: NetworkId
                     -> TxUnsigned Byron
                     -> [SigningKey ByronKey]
                     -> TxSigned Byron
signByronTransaction = undefined

-- signing keys is a set
signShelleyTransaction :: TxUnsigned Shelley
                       -> [SigningKey Shelley]
                       -> TxSigned Shelley
signShelleyTransaction = undefined


data Witness era where

     ByronKeyWitness
       :: Witness Byron

     ShelleyKeyWitness
       :: Witness Shelley

     ShelleyScriptWitness
       :: Witness Shelley

getTxUnsigned :: TxSigned era -> TxUnsigned era
getTxUnsigned = undefined

getTxWitnesses :: TxSigned era -> [Witness era]
getTxWitnesses = undefined

makeSignedTransaction :: [Witness era]
                      -> TxUnsigned era
                      -> TxSigned era
makeSignedTransaction = undefined


byronKeyWitness :: NetworkId -> SigningKey ByronKey -> TxUnsigned era -> Witness Byron
byronKeyWitness = undefined


shelleyKeyWitness :: SigningKey keyrole -> TxUnsigned era -> Witness Shelley
shelleyKeyWitness = undefined
-- this may need some class constraint on the keyrole, we can sign with:
--
--  ByronKey     -- for utxo inputs at byron addresses
--  PaymentKey   -- for utxo inputs, including multi-sig
--  StakeKey     -- for stake addr withdrawals and retiring and pool owners
--  StakePoolKey -- for stake pool ops
--  GenesisDelegateKey -- for update proposals, MIR etc


shelleyScriptWitness :: Script -> TxId -> Witness Shelley
shelleyScriptWitness = undefined


-- ----------------------------------------------------------------------------
-- Scripts
--

data Script


-- ----------------------------------------------------------------------------
-- CBOR and JSON Serialisation
--


serialiseToCBOR :: ToCBOR a => a -> ByteString
serialiseToCBOR = CBOR.serialize'

deserialiseFromCBOR :: FromCBOR a => AsType a -> ByteString -> Maybe a
deserialiseFromCBOR _proxy = either (const Nothing) Just . CBOR.decodeFull'

newtype JsonDecodeError = JsonDecodeError String

serialiseToJSON :: ToJSON a => a -> ByteString
serialiseToJSON = LBS.toStrict . Aeson.encode

deserialiseFromJSON :: FromJSON a
                    => AsType a
                    -> ByteString
                    -> Either JsonDecodeError a
deserialiseFromJSON _proxy = either (Left . JsonDecodeError) Right
                           . Aeson.eitherDecodeStrict'

class SerialiseAsRawBytes a where

  serialiseToRawBytes :: a -> ByteString

  deserialiseFromRawBytes :: AsType a -> ByteString -> Maybe a

serialiseToRawBytesHex :: SerialiseAsRawBytes a => a -> ByteString
serialiseToRawBytesHex = Base16.encode . serialiseToRawBytes

deserialiseFromRawBytesHex :: SerialiseAsRawBytes a
                           => AsType a -> ByteString -> Maybe a
deserialiseFromRawBytesHex proxy hex =
  case Base16.decode hex of
    (raw, trailing)
      | BS.null trailing -> deserialiseFromRawBytes proxy raw
      | otherwise        -> Nothing


-- ----------------------------------------------------------------------------
-- TextEnvelope Serialisation
--

type TextEnvelope = TextView.TextView
type TextEnvelopeType = TextView.TextViewType
type TextEnvelopeDescr = TextView.TextViewTitle

class (ToCBOR a, FromCBOR a, HasTypeProxy a) => HasTextEnvelope a where
    textEnvelopeType :: AsType a -> TextEnvelopeType

    textEnvelopeDefaultDescr :: AsType a -> TextEnvelopeDescr
    textEnvelopeDefaultDescr _ = ""

type TextEnvelopeError = TextView.TextViewError

data FileError e = FileError   FilePath e
                 | FileIOError FilePath IOException


serialiseToTextEnvelope :: forall a. HasTextEnvelope a
                        => Maybe TextEnvelopeDescr -> a -> TextEnvelope
serialiseToTextEnvelope mbDescr =
    TextView.encodeToTextView
      (textEnvelopeType ttoken)
      (fromMaybe (textEnvelopeDefaultDescr ttoken) mbDescr)
      toCBOR
  where
    ttoken :: AsType a
    ttoken = proxyToAsType Proxy


deserialiseFromTextEnvelope :: HasTextEnvelope a
                            => AsType a
                            -> TextEnvelope
                            -> Either TextEnvelopeError a
deserialiseFromTextEnvelope ttoken te = do
    TextView.expectTextViewOfType (textEnvelopeType ttoken) te
    TextView.decodeFromTextView fromCBOR te


data FromSomeType (c :: * -> Constraint) b where
     FromSomeType :: c a => AsType a -> (a -> b) -> FromSomeType c b


deserialiseFromTextEnvelopeAnyOf :: [FromSomeType HasTextEnvelope b]
                                 -> TextEnvelope
                                 -> Either TextEnvelopeError b
deserialiseFromTextEnvelopeAnyOf types te =
    case List.find matching types of
      Nothing ->
        Left (TextView.TextViewTypeError expectedTypes actualType)

      Just (FromSomeType _ttoken f) ->
        f <$> TextView.decodeFromTextView fromCBOR te
  where
    actualType    = TextView.tvType te
    expectedTypes = [ textEnvelopeType ttoken
                    | FromSomeType ttoken _f <- types ]

    matching (FromSomeType ttoken _f) = actualType == textEnvelopeType ttoken


writeFileTextEnvelope :: HasTextEnvelope a
                      => FilePath
                      -> Maybe TextEnvelopeDescr
                      -> a
                      -> IO (Either (FileError ()) ())
writeFileTextEnvelope path mbDescr a =
    runExceptT $ do
      handleIOExceptT (FileIOError path) $ BS.writeFile path content
  where
    content = TextView.renderTextView (serialiseToTextEnvelope mbDescr a)


readFileTextEnvelope :: HasTextEnvelope a
                     => AsType a
                     -> FilePath
                     -> IO (Either (FileError TextEnvelopeError) a)
readFileTextEnvelope ttoken path =
    runExceptT $ do
      content <- handleIOExceptT (FileIOError path) $ BS.readFile path
      firstExceptT (FileError path) $ hoistEither $ do
        te <- TextView.parseTextView content
        deserialiseFromTextEnvelope ttoken te


readFileTextEnvelopeAnyOf :: [FromSomeType HasTextEnvelope b]
                          -> FilePath
                          -> IO (Either (FileError TextEnvelopeError) b)
readFileTextEnvelopeAnyOf types path =
    runExceptT $ do
      content <- handleIOExceptT (FileIOError path) $ BS.readFile path
      firstExceptT (FileError path) $ hoistEither $ do
        te <- TextView.parseTextView content
        deserialiseFromTextEnvelopeAnyOf types te


-- ----------------------------------------------------------------------------
-- Error reporting
--

class Show e => Error e where

    displayError :: e -> String


-- | The preferred approach is to use 'Except' or 'ExceptT', but you can if
-- necessary use IO exceptions.
--
throwErrorAsException :: Error e => e -> IO a
throwErrorAsException e = throwIO (ErrorAsException e)

data ErrorAsException where
     ErrorAsException :: Error e => e -> ErrorAsException

instance Show ErrorAsException where
    show (ErrorAsException e) = show e

instance Exception ErrorAsException where
    displayException (ErrorAsException e) = displayError e


-- ----------------------------------------------------------------------------
-- Key instances
--

instance HasTypeProxy a => HasTypeProxy (VerificationKey a) where
    data AsType (VerificationKey a) = AsVerificationKey (AsType a)
    proxyToAsType _ = AsVerificationKey (proxyToAsType (Proxy :: Proxy a))

instance HasTypeProxy a => HasTypeProxy (SigningKey a) where
    data AsType (SigningKey a) = AsSigningKey (AsType a)
    proxyToAsType _ = AsSigningKey (proxyToAsType (Proxy :: Proxy a))

-- | Map the various Shelley key role types into corresponding 'Shelley.KeyRole'
-- types.
--
type family ShelleyKeyRole (keyrole :: *) :: Shelley.KeyRole

type instance ShelleyKeyRole PaymentKey         = Shelley.Payment
type instance ShelleyKeyRole GenesisKey         = Shelley.Genesis
type instance ShelleyKeyRole GenesisDelegateKey = Shelley.GenesisDelegate
type instance ShelleyKeyRole StakeKey           = Shelley.Staking
type instance ShelleyKeyRole StakePoolKey       = Shelley.StakePool


--
-- Byron keys
--

-- | Byron-era payment keys. Used for Byron addresses and witnessing
-- transactions that spend from these addresses.
--
-- These use Ed25519 but with a 32byte \"chaincode\" used in HD derivation.
-- The inclusion of the chaincode is a design mistake but one that cannot
-- be corrected for the Byron era. The Shelley era 'PaymentKey's do not include
-- a chaincode. It is safe to use a zero or random chaincode for new Byron keys.
--
-- This is a type level tag, used with other interfaces like 'Key'.
--
data ByronKey

instance HasTypeProxy ByronKey where
    data AsType ByronKey = AsByronKey
    proxyToAsType _ = AsByronKey

instance Key ByronKey where

    newtype VerificationKey ByronKey =
           ByronVerificationKey Byron.VerificationKey
      deriving newtype (ToCBOR, FromCBOR)

    newtype SigningKey ByronKey =
           ByronSigningKey Byron.SigningKey
      deriving newtype (ToCBOR, FromCBOR)

    deterministicSigningKey :: AsType ByronKey -> Crypto.Seed -> SigningKey ByronKey
    deterministicSigningKey AsByronKey seed =
       ByronSigningKey (snd (Crypto.runMonadRandomWithSeed seed Byron.keyGen))

    deterministicSigningKeySeedSize :: AsType ByronKey -> Word
    deterministicSigningKeySeedSize AsByronKey = 32

    getVerificationKey :: SigningKey ByronKey -> VerificationKey ByronKey
    getVerificationKey (ByronSigningKey sk) =
      ByronVerificationKey (Byron.toVerification sk)

--    verificationKeyHash :: VerificationKey keyrole -> Hash keyrole

--data instance Hash ByronKey = ByronKeyHash

instance HasTextEnvelope (VerificationKey ByronKey) where
    textEnvelopeType _ = "PaymentVerificationKeyByron"

instance HasTextEnvelope (SigningKey ByronKey) where
    textEnvelopeType _ = "SigningKeyByron"
    -- TODO: fix these inconsistent names for the public testnet re-spin


--
-- Shelley payment keys
--

-- | Shelley-era payment keys. Used for Shelley payment addresses and witnessing
-- transactions that spend from these addresses.
--
-- This is a type level tag, used with other interfaces like 'Key'.
--
data PaymentKey

instance HasTypeProxy PaymentKey where
    data AsType PaymentKey = AsPaymentKey
    proxyToAsType _ = AsPaymentKey

instance Key PaymentKey where

    newtype VerificationKey PaymentKey =
        PaymentVerificationKey (Shelley.VKey Shelley.Payment Shelley.TPraosStandardCrypto)
      deriving newtype (ToCBOR, FromCBOR)

    newtype SigningKey PaymentKey =
        PaymentSigningKey (Shelley.SignKeyDSIGN Shelley.TPraosStandardCrypto)
      deriving newtype (ToCBOR, FromCBOR)

    deterministicSigningKey :: AsType PaymentKey -> Crypto.Seed -> SigningKey PaymentKey
    deterministicSigningKey AsPaymentKey seed =
        PaymentSigningKey (Crypto.genKeyDSIGN seed)

    deterministicSigningKeySeedSize :: AsType PaymentKey -> Word
    deterministicSigningKeySeedSize AsPaymentKey =
        Crypto.seedSizeDSIGN proxy
      where
        proxy :: Proxy (Shelley.DSIGN Shelley.TPraosStandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey PaymentKey -> VerificationKey PaymentKey
    getVerificationKey (PaymentSigningKey sk) =
        PaymentVerificationKey (Shelley.VKey (Crypto.deriveVerKeyDSIGN sk))

--    verificationKeyHash :: VerificationKey PaymentKey -> Hash PaymentKey
--    verificationKeyHash (PaymentVerificationKey vk) =
--        PaymentKeyHash (Shelley.hashKey vk)

--newtype instance Hash PaymentKey =
--    PaymentKeyHash (Shelley.KeyHash Shelley.Payment Shelley.TPraosStandardCrypto)

instance HasTextEnvelope (VerificationKey PaymentKey) where
    textEnvelopeType _ = "PaymentVerificationKeyShelley"
    -- TODO: include the actual crypto algorithm name, to catch changes:
{-
                      <> fromString (Crypto.algorithmNameDSIGN proxy)
      where
        proxy :: Proxy (Shelley.DSIGN Shelley.TPraosStandardCrypto)
        proxy = Proxy
-}

instance HasTextEnvelope (SigningKey PaymentKey) where
    textEnvelopeType _ = "SigningKeyShelley"
    -- TODO: include the actual crypto algorithm name, to catch changes
    -- TODO: fix these inconsistent names for the public testnet re-spin


--
-- Stake keys
--

data StakeKey

instance HasTypeProxy StakeKey where
    data AsType StakeKey = AsStakeKey
    proxyToAsType _ = AsStakeKey

instance Key StakeKey where

    newtype VerificationKey StakeKey =
        StakeVerificationKey (Shelley.VKey Shelley.Staking Shelley.TPraosStandardCrypto)
      deriving newtype (ToCBOR, FromCBOR)

    newtype SigningKey StakeKey =
        StakeSigningKey (Shelley.SignKeyDSIGN Shelley.TPraosStandardCrypto)
      deriving newtype (ToCBOR, FromCBOR)

    deterministicSigningKey :: AsType StakeKey -> Crypto.Seed -> SigningKey StakeKey
    deterministicSigningKey AsStakeKey seed =
        StakeSigningKey (Crypto.genKeyDSIGN seed)

    deterministicSigningKeySeedSize :: AsType StakeKey -> Word
    deterministicSigningKeySeedSize AsStakeKey =
        Crypto.seedSizeDSIGN proxy
      where
        proxy :: Proxy (Shelley.DSIGN Shelley.TPraosStandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey StakeKey -> VerificationKey StakeKey
    getVerificationKey (StakeSigningKey sk) =
        StakeVerificationKey (Shelley.VKey (Crypto.deriveVerKeyDSIGN sk))

instance HasTextEnvelope (VerificationKey StakeKey) where
    textEnvelopeType _ = "StakingVerificationKeyShelley"
    -- TODO: include the actual crypto algorithm name, to catch changes

instance HasTextEnvelope (SigningKey StakeKey) where
    textEnvelopeType _ = "SigningKeyShelley"
    -- TODO: include the actual crypto algorithm name, to catch changes
    -- TODO: fix these inconsistent names for the public testnet re-spin


--
-- Genesis keys
--

data GenesisKey

instance HasTypeProxy GenesisKey where
    data AsType GenesisKey = AsGenesisKey
    proxyToAsType _ = AsGenesisKey

instance Key GenesisKey where

    newtype VerificationKey GenesisKey =
        GenesisVerificationKey (Shelley.VKey Shelley.Genesis Shelley.TPraosStandardCrypto)
      deriving newtype (ToCBOR, FromCBOR)

    newtype SigningKey GenesisKey =
        GenesisSigningKey (Shelley.SignKeyDSIGN Shelley.TPraosStandardCrypto)
      deriving newtype (ToCBOR, FromCBOR)

    deterministicSigningKey :: AsType GenesisKey -> Crypto.Seed -> SigningKey GenesisKey
    deterministicSigningKey AsGenesisKey seed =
        GenesisSigningKey (Crypto.genKeyDSIGN seed)

    deterministicSigningKeySeedSize :: AsType GenesisKey -> Word
    deterministicSigningKeySeedSize AsGenesisKey =
        Crypto.seedSizeDSIGN proxy
      where
        proxy :: Proxy (Shelley.DSIGN Shelley.TPraosStandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey GenesisKey -> VerificationKey GenesisKey
    getVerificationKey (GenesisSigningKey sk) =
        GenesisVerificationKey (Shelley.VKey (Crypto.deriveVerKeyDSIGN sk))

instance HasTextEnvelope (VerificationKey GenesisKey) where
    textEnvelopeType _ = "Genesis verification key"
    -- TODO: include the actual crypto algorithm name, to catch changes

instance HasTextEnvelope (SigningKey GenesisKey) where
    textEnvelopeType _ = "Genesis signing key"
    -- TODO: include the actual crypto algorithm name, to catch changes


--
-- Genesis delegate keys
--

data GenesisDelegateKey

instance HasTypeProxy GenesisDelegateKey where
    data AsType GenesisDelegateKey = AsGenesisDelegateKey
    proxyToAsType _ = AsGenesisDelegateKey


instance Key GenesisDelegateKey where

    newtype VerificationKey GenesisDelegateKey =
        GenesisDelegateVerificationKey (Shelley.VKey Shelley.GenesisDelegate Shelley.TPraosStandardCrypto)
      deriving newtype (ToCBOR, FromCBOR)

    newtype SigningKey GenesisDelegateKey =
        GenesisDelegateSigningKey (Shelley.SignKeyDSIGN Shelley.TPraosStandardCrypto)
      deriving newtype (ToCBOR, FromCBOR)

    deterministicSigningKey :: AsType GenesisDelegateKey -> Crypto.Seed -> SigningKey GenesisDelegateKey
    deterministicSigningKey AsGenesisDelegateKey seed =
        GenesisDelegateSigningKey (Crypto.genKeyDSIGN seed)

    deterministicSigningKeySeedSize :: AsType GenesisDelegateKey -> Word
    deterministicSigningKeySeedSize AsGenesisDelegateKey =
        Crypto.seedSizeDSIGN proxy
      where
        proxy :: Proxy (Shelley.DSIGN Shelley.TPraosStandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey GenesisDelegateKey -> VerificationKey GenesisDelegateKey
    getVerificationKey (GenesisDelegateSigningKey sk) =
        GenesisDelegateVerificationKey (Shelley.VKey (Crypto.deriveVerKeyDSIGN sk))

instance HasTextEnvelope (VerificationKey GenesisDelegateKey) where
    textEnvelopeType _ = "Node operator verification key"
    -- TODO: include the actual crypto algorithm name, to catch changes

instance HasTextEnvelope (SigningKey GenesisDelegateKey) where
    textEnvelopeType _ = "Node operator signing key"
    -- TODO: include the actual crypto algorithm name, to catch changes
    -- TODO: use a different type from the stake pool key, since some operations
    -- need a genesis key specifically


--
-- stake pool keys
--

data StakePoolKey

instance HasTypeProxy StakePoolKey where
    data AsType StakePoolKey = AsStakePoolKey
    proxyToAsType _ = AsStakePoolKey

instance Key StakePoolKey where

    newtype VerificationKey StakePoolKey =
        StakePoolVerificationKey (Shelley.VKey Shelley.StakePool Shelley.TPraosStandardCrypto)
      deriving newtype (ToCBOR, FromCBOR)

    newtype SigningKey StakePoolKey =
        StakePoolSigningKey (Shelley.SignKeyDSIGN Shelley.TPraosStandardCrypto)
      deriving newtype (ToCBOR, FromCBOR)

    deterministicSigningKey :: AsType StakePoolKey -> Crypto.Seed -> SigningKey StakePoolKey
    deterministicSigningKey AsStakePoolKey seed =
        StakePoolSigningKey (Crypto.genKeyDSIGN seed)

    deterministicSigningKeySeedSize :: AsType StakePoolKey -> Word
    deterministicSigningKeySeedSize AsStakePoolKey =
        Crypto.seedSizeDSIGN proxy
      where
        proxy :: Proxy (Shelley.DSIGN Shelley.TPraosStandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey StakePoolKey -> VerificationKey StakePoolKey
    getVerificationKey (StakePoolSigningKey sk) =
        StakePoolVerificationKey (Shelley.VKey (Crypto.deriveVerKeyDSIGN sk))

instance HasTextEnvelope (VerificationKey StakePoolKey) where
    textEnvelopeType _ = "Node operator verification key"
    -- TODO: include the actual crypto algorithm name, to catch changes

instance HasTextEnvelope (SigningKey StakePoolKey) where
    textEnvelopeType _ = "Node operator signing key"
    -- TODO: include the actual crypto algorithm name, to catch changes


--
-- KES keys
--

data KesKey

instance HasTypeProxy KesKey where
    data AsType KesKey = AsKesKey
    proxyToAsType _ = AsKesKey

instance Key KesKey where

    newtype VerificationKey KesKey =
        KesVerificationKey (Shelley.VerKeyKES Shelley.TPraosStandardCrypto)
      deriving newtype (ToCBOR, FromCBOR)

    newtype SigningKey KesKey =
        KesSigningKey (Shelley.SignKeyKES Shelley.TPraosStandardCrypto)
      deriving newtype (ToCBOR, FromCBOR)

    deterministicSigningKey :: AsType KesKey -> Crypto.Seed -> SigningKey KesKey
    deterministicSigningKey AsKesKey seed =
        KesSigningKey (Crypto.genKeyKES seed)

    deterministicSigningKeySeedSize :: AsType KesKey -> Word
    deterministicSigningKeySeedSize AsKesKey =
        Crypto.seedSizeKES proxy
      where
        proxy :: Proxy (Shelley.KES Shelley.TPraosStandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey KesKey -> VerificationKey KesKey
    getVerificationKey (KesSigningKey sk) =
        KesVerificationKey (Crypto.deriveVerKeyKES sk)

instance HasTextEnvelope (VerificationKey KesKey) where
    textEnvelopeType _ = "VKeyES TPraosStandardCrypto"
    -- TODO: include the actual crypto algorithm name, to catch changes

instance HasTextEnvelope (SigningKey KesKey) where
    textEnvelopeType _ = "SKeyES TPraosStandardCrypto"
    -- TODO: include the actual crypto algorithm name, to catch changes


--
-- VRF keys
--

data VrfKey

instance HasTypeProxy VrfKey where
    data AsType VrfKey = AsVrfKey
    proxyToAsType _ = AsVrfKey

instance Key VrfKey where

    newtype VerificationKey VrfKey =
        VrfVerificationKey (Shelley.VerKeyVRF Shelley.TPraosStandardCrypto)
      deriving (Show)
      deriving newtype (ToCBOR, FromCBOR)

    newtype SigningKey VrfKey =
        VrfSigningKey (Shelley.SignKeyVRF Shelley.TPraosStandardCrypto)
      deriving (Show)
      deriving newtype (ToCBOR, FromCBOR)

    deterministicSigningKey :: AsType VrfKey -> Crypto.Seed -> SigningKey VrfKey
    deterministicSigningKey AsVrfKey seed =
        VrfSigningKey (Crypto.genKeyVRF seed)

    deterministicSigningKeySeedSize :: AsType VrfKey -> Word
    deterministicSigningKeySeedSize AsVrfKey =
        Crypto.seedSizeVRF proxy
      where
        proxy :: Proxy (Shelley.VRF Shelley.TPraosStandardCrypto)
        proxy = Proxy

    getVerificationKey :: SigningKey VrfKey -> VerificationKey VrfKey
    getVerificationKey (VrfSigningKey sk) =
        VrfVerificationKey (Crypto.deriveVerKeyVRF sk)

instance HasTextEnvelope (VerificationKey VrfKey) where
    textEnvelopeType _ = "VerKeyVRF " <> fromString (Crypto.algorithmNameVRF proxy)
      where
        proxy :: Proxy (Shelley.VRF Shelley.TPraosStandardCrypto)
        proxy = Proxy

instance HasTextEnvelope (SigningKey VrfKey) where
    textEnvelopeType _ = "SignKeyVRF " <> fromString (Crypto.algorithmNameVRF proxy)
      where
        proxy :: Proxy (Shelley.VRF Shelley.TPraosStandardCrypto)
        proxy = Proxy
