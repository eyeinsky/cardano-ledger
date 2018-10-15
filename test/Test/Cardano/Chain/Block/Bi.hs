{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

module Test.Cardano.Chain.Block.Bi
       ( tests
       , exampleMainBody
       , exampleMainConsensusData
       , exampleMainToSign
       , exampleBlockSignature
       , exampleBlockPSignatureLight
       , exampleBlockPSignatureHeavy
       ) where

import           Cardano.Prelude
import           Test.Cardano.Prelude

import           Data.Coerce (coerce)
import           Data.List ((!!))
import           Data.Maybe (fromJust)

import           Hedgehog (Property)
import qualified Hedgehog as H

import           Cardano.Binary.Class (decodeFullDecoder, dropBytes,
                     serializeEncoding)
import           Cardano.Chain.Block (BlockHeaderAttributes,
                     BlockSignature (..), Header, HeaderHash, MainBody (..),
                     MainConsensusData (..), MainExtraBodyData (..),
                     MainExtraHeaderData (..), MainProof (..), MainToSign (..),
                     SlogUndo (..), Undo (..), decodeBlock, decodeHeader,
                     dropBoundaryBody, dropBoundaryConsensusData,
                     dropBoundaryHeader, encodeBlock, encodeHeader,
                     mkHeaderExplicit)
import           Cardano.Chain.Common (mkAttributes)
import           Cardano.Chain.Delegation as Delegation (Payload (..))
import           Cardano.Chain.Ssc (SscPayload (..), SscProof (..))
import           Cardano.Crypto (ProtocolMagic (..), SignTag (..), abstractHash,
                     createPsk, hash, proxySign, sign, toPublic)

import           Test.Cardano.Binary.Helpers.GoldenRoundTrip (goldenTestBi,
                     legacyGoldenDecode, roundTripsBiBuildable,
                     roundTripsBiShow)
import           Test.Cardano.Chain.Block.Gen
import           Test.Cardano.Chain.Common.Example (exampleChainDifficulty)
import           Test.Cardano.Chain.Delegation.Example (exampleLightDlgIndices,
                     staticHeavyDlgIndexes, staticProxySKHeavys)
import qualified Test.Cardano.Chain.Delegation.Example as Delegation
import           Test.Cardano.Chain.Slotting.Example (exampleSlotId)
import           Test.Cardano.Chain.Slotting.Gen (feedPMEpochSlots)
import           Test.Cardano.Chain.Txp.Example (exampleTxPayload,
                     exampleTxProof, exampleTxpUndo)
import qualified Test.Cardano.Chain.Update.Example as Update
import           Test.Cardano.Crypto.Example (examplePublicKey,
                     exampleSecretKey, exampleSecretKeys)
import           Test.Cardano.Crypto.Gen (feedPM)


--------------------------------------------------------------------------------
-- BlockBodyAttributes
--------------------------------------------------------------------------------

golden_BlockBodyAttributes :: Property
golden_BlockBodyAttributes = goldenTestBi bba "test/golden/BlockBodyAttributes"
  where bba = mkAttributes ()

roundTripBlockBodyAttributesBi :: Property
roundTripBlockBodyAttributesBi =
  eachOf 1000 genBlockBodyAttributes roundTripsBiBuildable


--------------------------------------------------------------------------------
-- Header
--------------------------------------------------------------------------------

golden_Header :: Property
golden_Header =
  goldenTestBi exampleHeader "test/golden/MainBlockHeader"

roundTripHeaderBi :: Property
roundTripHeaderBi =
  eachOf 10 (feedPMEpochSlots genHeader) roundTripsBiBuildable

-- | Round-trip test the backwards compatible header encoding/decoding functions
roundTripHeaderCompat :: Property
roundTripHeaderCompat = eachOf
  10
  (feedPMEpochSlots genHeader)
  roundTripsHeaderCompat
 where
  roundTripsHeaderCompat a = trippingBuildable
    a
    (serializeEncoding . encodeHeader)
    (fmap fromJust . decodeFullDecoder "Header" decodeHeader)


--------------------------------------------------------------------------------
-- Block
--------------------------------------------------------------------------------

roundTripBlock :: Property
roundTripBlock = eachOf 10 (feedPMEpochSlots genBlock) roundTripsBiBuildable

-- | Round-trip test the backwards compatible block encoding/decoding functions
roundTripBlockCompat :: Property
roundTripBlockCompat = eachOf
  10
  (feedPMEpochSlots genBlock)
  roundTripsBlockCompat
 where
  roundTripsBlockCompat a = trippingBuildable
    a
    (serializeEncoding . encodeBlock)
    (fmap fromJust . decodeFullDecoder "Block" decodeBlock)


--------------------------------------------------------------------------------
-- BlockHeaderAttributes
--------------------------------------------------------------------------------

golden_BlockHeaderAttributes :: Property
golden_BlockHeaderAttributes = goldenTestBi
  (mkAttributes () :: BlockHeaderAttributes)
  "test/golden/BlockHeaderAttributes"

roundTripBlockHeaderAttributesBi :: Property
roundTripBlockHeaderAttributesBi =
  eachOf 1000 genBlockHeaderAttributes roundTripsBiBuildable


--------------------------------------------------------------------------------
-- BlockSignature
--------------------------------------------------------------------------------

golden_BlockSignature :: Property
golden_BlockSignature =
  goldenTestBi exampleBlockSignature "test/golden/BlockSignature"

golden_BlockSignature_Light :: Property
golden_BlockSignature_Light =
  goldenTestBi exampleBlockPSignatureLight "test/golden/BlockSignature_Light"

golden_BlockSignature_Heavy :: Property
golden_BlockSignature_Heavy =
  goldenTestBi exampleBlockPSignatureHeavy "test/golden/BlockSignature_Heavy"

roundTripBlockSignatureBi :: Property
roundTripBlockSignatureBi =
  eachOf 10 (feedPMEpochSlots genBlockSignature) roundTripsBiBuildable


--------------------------------------------------------------------------------
-- BoundaryBlockHeader
--------------------------------------------------------------------------------

golden_legacy_BoundaryBlockHeader :: Property
golden_legacy_BoundaryBlockHeader = legacyGoldenDecode
  "BoundaryBlockHeader"
  dropBoundaryHeader
  "test/golden/BoundaryBlockHeader"


--------------------------------------------------------------------------------
-- BoundaryBody
--------------------------------------------------------------------------------

golden_legacy_BoundaryBody :: Property
golden_legacy_BoundaryBody = legacyGoldenDecode
  "BoundaryBody"
  dropBoundaryBody
  "test/golden/BoundaryBody"


--------------------------------------------------------------------------------
-- BoundaryConsensusData
--------------------------------------------------------------------------------

golden_legacy_BoundaryConsensusData :: Property
golden_legacy_BoundaryConsensusData = legacyGoldenDecode
  "BoundaryConsensusData"
  dropBoundaryConsensusData
  "test/golden/BoundaryConsensusData"


--------------------------------------------------------------------------------
-- HeaderHash
--------------------------------------------------------------------------------

golden_HeaderHash :: Property
golden_HeaderHash = goldenTestBi exampleHeaderHash "test/golden/HeaderHash"

roundTripHeaderHashBi :: Property
roundTripHeaderHashBi = eachOf 1000 genHeaderHash roundTripsBiBuildable


--------------------------------------------------------------------------------
-- BoundaryProof
--------------------------------------------------------------------------------

golden_legacy_BoundaryProof :: Property
golden_legacy_BoundaryProof = legacyGoldenDecode
  "BoundaryProof"
  dropBytes
  "test/golden/BoundaryProof"


--------------------------------------------------------------------------------
-- Header
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- MainBody
--------------------------------------------------------------------------------

golden_MainBody :: Property
golden_MainBody = goldenTestBi exampleMainBody "test/golden/MainBody"

roundTripMainBodyBi :: Property
roundTripMainBodyBi = eachOf 20 (feedPM genMainBody) roundTripsBiShow


--------------------------------------------------------------------------------
-- MainConsensusData
--------------------------------------------------------------------------------

golden_MainConsensusData :: Property
golden_MainConsensusData = goldenTestBi mcd "test/golden/MainConsensusData"
 where
  mcd = MainConsensusData
    exampleSlotId
    examplePublicKey
    exampleChainDifficulty
    exampleBlockSignature

roundTripMainConsensusData :: Property
roundTripMainConsensusData =
  eachOf 20 (feedPMEpochSlots genMainConsensusData) roundTripsBiShow


--------------------------------------------------------------------------------
-- MainExtraBodyData
--------------------------------------------------------------------------------

golden_MainExtraBodyData :: Property
golden_MainExtraBodyData = goldenTestBi mebd "test/golden/MainExtraBodyData"
  where mebd = MainExtraBodyData (mkAttributes ())

roundTripMainExtraBodyDataBi :: Property
roundTripMainExtraBodyDataBi =
  eachOf 1000 genMainExtraBodyData roundTripsBiBuildable


--------------------------------------------------------------------------------
-- MainExtraHeaderData
--------------------------------------------------------------------------------

golden_MainExtraHeaderData :: Property
golden_MainExtraHeaderData =
  goldenTestBi exampleMainExtraHeaderData "test/golden/MainExtraHeaderData"

roundTripMainExtraHeaderDataBi :: Property
roundTripMainExtraHeaderDataBi =
  eachOf 1000 genMainExtraHeaderData roundTripsBiBuildable


--------------------------------------------------------------------------------
-- MainProof
--------------------------------------------------------------------------------

golden_MainProof :: Property
golden_MainProof = goldenTestBi exampleMainProof "test/golden/MainProof"

roundTripMainProofBi :: Property
roundTripMainProofBi = eachOf 20 (feedPM genMainProof) roundTripsBiBuildable


--------------------------------------------------------------------------------
-- MainToSign
--------------------------------------------------------------------------------

golden_MainToSign :: Property
golden_MainToSign = goldenTestBi exampleMainToSign "test/golden/MainToSign"

roundTripMainToSignBi :: Property
roundTripMainToSignBi =
  eachOf 20 (feedPMEpochSlots genMainToSign) roundTripsBiShow


--------------------------------------------------------------------------------
-- Undo
--------------------------------------------------------------------------------

golden_Undo :: Property
golden_Undo = goldenTestBi exampleUndo "test/golden/Undo"

roundTripUndo :: Property
roundTripUndo = eachOf 20 (feedPMEpochSlots genUndo) roundTripsBiShow


--------------------------------------------------------------------------------
-- Example golden datatypes
--------------------------------------------------------------------------------

exampleHeader :: Header
exampleHeader = mkHeaderExplicit
  (ProtocolMagic 7)
  exampleHeaderHash
  exampleChainDifficulty
  exampleSlotId
  exampleSecretKey
  Nothing
  exampleMainBody
  exampleMainExtraHeaderData

exampleBlockSignature :: BlockSignature
exampleBlockSignature = BlockSignature
  (sign (ProtocolMagic 7) SignMainBlock exampleSecretKey exampleMainToSign)

exampleBlockPSignatureLight :: BlockSignature
exampleBlockPSignatureLight = BlockPSignatureLight sig
 where
  sig = proxySign pm SignProxySK delegateSk psk exampleMainToSign
  [delegateSk, issuerSk] = exampleSecretKeys 5 2
  psk = createPsk pm issuerSk (toPublic delegateSk) exampleLightDlgIndices
  pm = ProtocolMagic 2

exampleBlockPSignatureHeavy :: BlockSignature
exampleBlockPSignatureHeavy = BlockPSignatureHeavy sig
 where
  sig = proxySign pm SignProxySK delegateSk psk exampleMainToSign
  [delegateSk, issuerSk] = exampleSecretKeys 5 2
  psk =
    createPsk pm issuerSk (toPublic delegateSk) (staticHeavyDlgIndexes !! 0)
  pm = ProtocolMagic 2

exampleMainConsensusData :: MainConsensusData
exampleMainConsensusData = MainConsensusData
  exampleSlotId
  examplePublicKey
  exampleChainDifficulty
  exampleBlockSignature

exampleMainExtraHeaderData :: MainExtraHeaderData
exampleMainExtraHeaderData = MainExtraHeaderData
  Update.exampleBlockVersion
  Update.exampleSoftwareVersion
  (mkAttributes ())
  (abstractHash (MainExtraBodyData (mkAttributes ())))

exampleMainProof :: MainProof
exampleMainProof = MainProof
  exampleTxProof
  SscProof
  (abstractHash dp)
  Update.exampleProof
  where dp = Delegation.UnsafePayload (take 4 staticProxySKHeavys)

exampleHeaderHash :: HeaderHash
exampleHeaderHash = coerce (hash ("HeaderHash" :: Text))

exampleMainBody :: MainBody
exampleMainBody = MainBody exampleTxPayload SscPayload dp Update.examplePayload
  where dp = Delegation.UnsafePayload (take 4 staticProxySKHeavys)

exampleMainToSign :: MainToSign
exampleMainToSign = MainToSign
  exampleHeaderHash
  exampleMainProof
  exampleSlotId
  exampleChainDifficulty
  exampleMainExtraHeaderData

exampleSlogUndo :: SlogUndo
exampleSlogUndo = SlogUndo $ Just 999

exampleUndo :: Undo
exampleUndo = Undo
  { undoTx   = exampleTxpUndo
  , undoDlg  = Delegation.exampleUndo
  , undoUS   = Update.exampleUndo
  , undoSlog = exampleSlogUndo
  }


-----------------------------------------------------------------------
-- Main test export
-----------------------------------------------------------------------

tests :: IO Bool
tests = and <$> sequence
  [H.checkSequential $$discoverGolden, H.checkParallel $$discoverRoundTrip]
