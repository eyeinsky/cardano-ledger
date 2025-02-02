{-# LANGUAGE ConstrainedClassMethods #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE TypeFamilyDependencies #-}
{-# LANGUAGE ViewPatterns #-}

module Cardano.Ledger.Core.DCert (
  EraDCert (..),
  pattern DCertPool,
  pattern DCertGenesis,
  Delegation (..),
  PoolCert (..),
  poolCWitness,
  ConstitutionalDelegCert (..),
  genesisCWitness,
)
where

import Cardano.Ledger.Binary (DecCBOR, EncCBOR, FromCBOR, ToCBOR)
import Cardano.Ledger.Core.Era (Era (EraCrypto))
import Cardano.Ledger.Credential (Credential (..), StakeCredential)
import Cardano.Ledger.Keys (
  Hash,
  KeyHash (..),
  KeyRole (..),
  VerKeyVRF,
 )
import Cardano.Ledger.PoolParams
import Cardano.Ledger.Slot (EpochNo (..))
import Control.DeepSeq (NFData (..), rwhnf)
import Data.Kind (Type)
import GHC.Generics (Generic)
import NoThunks.Class (NoThunks (..))

class
  ( Era era
  , DecCBOR (DCert era)
  , EncCBOR (DCert era)
  , ToCBOR (DCert era)
  , FromCBOR (DCert era)
  , NoThunks (DCert era)
  , NFData (DCert era)
  , Show (DCert era)
  , Eq (DCert era)
  ) =>
  EraDCert era
  where
  type DCert era = (r :: Type) | r -> era

  mkDCertPool :: PoolCert (EraCrypto era) -> DCert era

  getDCertPool :: DCert era -> Maybe (PoolCert (EraCrypto era))

  mkDCertGenesis :: ConstitutionalDelegCert (EraCrypto era) -> DCert era

  getDCertGenesis :: DCert era -> Maybe (ConstitutionalDelegCert (EraCrypto era))

pattern DCertPool :: EraDCert era => PoolCert (EraCrypto era) -> DCert era
pattern DCertPool d <- (getDCertPool -> Just d)
  where
    DCertPool d = mkDCertPool d

pattern DCertGenesis ::
  EraDCert era =>
  ConstitutionalDelegCert (EraCrypto era) ->
  DCert era
pattern DCertGenesis d <- (getDCertGenesis -> Just d)
  where
    DCertGenesis d = mkDCertGenesis d

-- | The delegation of one stake key to another.
data Delegation c = Delegation
  { dDelegator :: !(StakeCredential c)
  , dDelegatee :: !(KeyHash 'StakePool c)
  }
  deriving (Eq, Generic, Show)

instance NFData (Delegation c) where
  rnf = rwhnf

instance NoThunks (Delegation c)

data PoolCert c
  = -- | A stake pool registration certificate.
    RegPool !(PoolParams c)
  | -- | A stake pool retirement certificate.
    RetirePool !(KeyHash 'StakePool c) !EpochNo
  deriving (Show, Generic, Eq)

instance NoThunks (PoolCert c)

instance NFData (PoolCert c) where
  rnf = rwhnf

-- | Constitutional key delegation certificate
data ConstitutionalDelegCert c
  = ConstitutionalDelegCert
      !(KeyHash 'Genesis c)
      !(KeyHash 'GenesisDelegate c)
      !(Hash c (VerKeyVRF c))
  deriving (Show, Generic, Eq)

instance NoThunks (ConstitutionalDelegCert c)

instance NFData (ConstitutionalDelegCert c) where
  rnf = rwhnf

poolCWitness :: PoolCert c -> Credential 'StakePool c
poolCWitness (RegPool pool) = KeyHashObj $ ppId pool
poolCWitness (RetirePool k _) = KeyHashObj k

genesisCWitness :: ConstitutionalDelegCert c -> KeyHash 'Genesis c
genesisCWitness (ConstitutionalDelegCert gk _ _) = gk
