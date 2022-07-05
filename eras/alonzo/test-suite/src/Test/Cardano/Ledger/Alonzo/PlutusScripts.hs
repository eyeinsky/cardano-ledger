-- | This file is generated by plutus-preprocessor/src/Main.hs
module Test.Cardano.Ledger.Alonzo.PlutusScripts where

import Cardano.Ledger.Alonzo.Language (Language (..))
import Cardano.Ledger.Alonzo.Scripts (AlonzoScript (..), CostModel, mkCostModel)
import Data.ByteString.Short (pack)
import Data.Either (fromRight)
import qualified Plutus.V1.Ledger.EvaluationContext as PV1

testingCostModelV1 :: CostModel
testingCostModelV1 =
  fromRight (error "testingCostModelV1 is not well-formed") $
    mkCostModel PlutusV1 PV1.costModelParamsForTesting

testingCostModelV2 :: CostModel
testingCostModelV2 =
  fromRight (error "testingCostModelV2 is not well-formed") $
    mkCostModel PlutusV2 PV1.costModelParamsForTesting -- TODO use PV2 when it exists

{- Preproceesed Plutus Script
guessTheNumber'2_0 :: PlutusTx.Builtins.Internal.BuiltinData ->
                      PlutusTx.Builtins.Internal.BuiltinData -> ()
guessTheNumber'2_0 d1_1 d2_2 = if d1_1 PlutusTx.Eq.== d2_2
                                then GHC.Tuple.()
                                else PlutusTx.Builtins.error GHC.Tuple.()
-}

guessTheNumber2 :: AlonzoScript era
guessTheNumber2 =
  PlutusScript PlutusV1 . pack $
    concat
      [ [88, 48, 1, 0, 0, 51, 50, 34, 51, 34, 34, 83, 53, 48, 5],
        [51, 53, 115, 70, 110, 188, 0, 128, 4, 1, 192, 24, 64, 16, 76],
        [152, 212, 192, 12, 1, 18, 97, 32, 1, 32, 1, 18, 32, 2, 18],
        [32, 1, 32, 1, 1]
      ]

{- Preproceesed Plutus Script
guessTheNumber'3_0 :: PlutusTx.Builtins.Internal.BuiltinData ->
                      PlutusTx.Builtins.Internal.BuiltinData ->
                      PlutusTx.Builtins.Internal.BuiltinData -> ()
guessTheNumber'3_0 d1_1 d2_2 _d3_3 = if d1_1 PlutusTx.Eq.== d2_2
                                      then GHC.Tuple.()
                                      else PlutusTx.Builtins.error GHC.Tuple.()
-}

guessTheNumber3 :: AlonzoScript era
guessTheNumber3 =
  PlutusScript PlutusV1 . pack $
    concat
      [ [88, 48, 1, 0, 0, 51, 50, 34, 51, 34, 34, 37, 51, 83, 0],
        [99, 51, 87, 52, 102, 235, 192, 12, 0, 128, 32, 1, 196, 1, 68],
        [201, 141, 76, 1, 0, 21, 38, 18, 0, 18, 0, 17, 34, 0, 33],
        [34, 0, 18, 0, 17]
      ]

{- Preproceesed Plutus Script
evendata'_0 :: PlutusTx.Builtins.Internal.BuiltinData ->
               PlutusTx.Builtins.Internal.BuiltinData ->
               PlutusTx.Builtins.Internal.BuiltinData -> ()
evendata'_0 d1_1 _d2_2 _d3_3 = let n_4 = PlutusTx.Builtins.unsafeDataAsI d1_1
                                in if PlutusTx.Prelude.modulo n_4 2 PlutusTx.Eq.== 0
                                    then GHC.Tuple.()
                                    else PlutusTx.Builtins.error GHC.Tuple.()
-}

evendata3 :: AlonzoScript era
evendata3 =
  PlutusScript PlutusV1 . pack $
    concat
      [ [88, 65, 1, 0, 0, 51, 50, 34, 51, 34, 34, 37, 51, 83, 0],
        [99, 50, 35, 51, 87, 52, 102, 225, 192, 8, 0, 64, 40, 2, 76],
        [200, 140, 220, 48, 1, 0, 9, 186, 208, 3, 72, 1, 18, 0, 1],
        [0, 81, 50, 99, 83, 0, 64, 5, 73, 132, 128, 4, 128, 4, 72],
        [128, 8, 72, 128, 4, 128, 5]
      ]

{- Preproceesed Plutus Script
odddata'_0 :: PlutusTx.Builtins.Internal.BuiltinData ->
              PlutusTx.Builtins.Internal.BuiltinData ->
              PlutusTx.Builtins.Internal.BuiltinData -> ()
odddata'_0 d1_1 _d2_2 _d3_3 = let n_4 = PlutusTx.Builtins.unsafeDataAsI d1_1
                               in if PlutusTx.Prelude.modulo n_4 2 PlutusTx.Eq.== 1
                                   then GHC.Tuple.()
                                   else PlutusTx.Builtins.error GHC.Tuple.()
-}

odddata3 :: AlonzoScript era
odddata3 =
  PlutusScript PlutusV1 . pack $
    concat
      [ [88, 65, 1, 0, 0, 51, 50, 34, 51, 34, 34, 37, 51, 83, 0],
        [99, 50, 35, 51, 87, 52, 102, 225, 192, 8, 0, 64, 40, 2, 76],
        [200, 140, 220, 48, 1, 0, 9, 186, 208, 3, 72, 1, 18, 0, 33],
        [0, 81, 50, 99, 83, 0, 64, 5, 73, 132, 128, 4, 128, 4, 72],
        [128, 8, 72, 128, 4, 128, 5]
      ]

{- Preproceesed Plutus Script
evenRedeemer'_0 :: PlutusTx.Builtins.Internal.BuiltinData ->
                   PlutusTx.Builtins.Internal.BuiltinData ->
                   PlutusTx.Builtins.Internal.BuiltinData -> ()
evenRedeemer'_0 _d1_1 d2_2 _d3_3 = let n_4 = PlutusTx.Builtins.unsafeDataAsI d2_2
                                    in if PlutusTx.Prelude.modulo n_4 2 PlutusTx.Eq.== 0
                                        then GHC.Tuple.()
                                        else PlutusTx.Builtins.error GHC.Tuple.()
-}

evenRedeemer3 :: AlonzoScript era
evenRedeemer3 =
  PlutusScript PlutusV1 . pack $
    concat
      [ [88, 65, 1, 0, 0, 51, 50, 34, 51, 34, 34, 37, 51, 83, 0],
        [99, 50, 35, 51, 87, 52, 102, 225, 192, 8, 0, 64, 40, 2, 76],
        [200, 140, 220, 48, 1, 0, 9, 186, 208, 2, 72, 1, 18, 0, 1],
        [0, 81, 50, 99, 83, 0, 64, 5, 73, 132, 128, 4, 128, 4, 72],
        [128, 8, 72, 128, 4, 128, 5]
      ]

{- Preproceesed Plutus Script
oddRedeemer'_0 :: PlutusTx.Builtins.Internal.BuiltinData ->
                  PlutusTx.Builtins.Internal.BuiltinData ->
                  PlutusTx.Builtins.Internal.BuiltinData -> ()
oddRedeemer'_0 _d1_1 d2_2 _d3_3 = let n_4 = PlutusTx.Builtins.unsafeDataAsI d2_2
                                   in if PlutusTx.Prelude.modulo n_4 2 PlutusTx.Eq.== 1
                                       then GHC.Tuple.()
                                       else PlutusTx.Builtins.error GHC.Tuple.()
-}

oddRedeemer3 :: AlonzoScript era
oddRedeemer3 =
  PlutusScript PlutusV1 . pack $
    concat
      [ [88, 65, 1, 0, 0, 51, 50, 34, 51, 34, 34, 37, 51, 83, 0],
        [99, 50, 35, 51, 87, 52, 102, 225, 192, 8, 0, 64, 40, 2, 76],
        [200, 140, 220, 48, 1, 0, 9, 186, 208, 2, 72, 1, 18, 0, 33],
        [0, 81, 50, 99, 83, 0, 64, 5, 73, 132, 128, 4, 128, 4, 72],
        [128, 8, 72, 128, 4, 128, 5]
      ]

{- Preproceesed Plutus Script
sumsTo10'_0 :: PlutusTx.Builtins.Internal.BuiltinData ->
               PlutusTx.Builtins.Internal.BuiltinData ->
               PlutusTx.Builtins.Internal.BuiltinData -> ()
sumsTo10'_0 d1_1 d2_2 _d3_3 = let {n_4 = PlutusTx.Builtins.unsafeDataAsI d1_1;
                                   m_5 = PlutusTx.Builtins.unsafeDataAsI d2_2}
                               in if (m_5 PlutusTx.Numeric.+ n_4) PlutusTx.Eq.== 10
                                   then GHC.Tuple.()
                                   else PlutusTx.Builtins.error GHC.Tuple.()
-}

sumsTo103 :: AlonzoScript era
sumsTo103 =
  PlutusScript PlutusV1 . pack $
    concat
      [ [88, 72, 1, 0, 0, 51, 50, 34, 50, 51, 34, 34, 37, 51, 83],
        [0, 115, 50, 35, 51, 87, 52, 102, 225, 192, 8, 0, 64, 44, 2],
        [140, 200, 140, 220, 0, 1, 0, 9, 128, 48, 1, 24, 3, 0, 26],
        [64, 40, 32, 10, 38, 76, 106, 96, 8, 0, 169, 48, 144, 0, 144],
        [0, 145, 186, 208, 1, 18, 32, 2, 18, 32, 1, 32, 1, 1]
      ]

{- Preproceesed Plutus Script
oddRedeemer2'_0 :: PlutusTx.Builtins.Internal.BuiltinData ->
                   PlutusTx.Builtins.Internal.BuiltinData -> ()
oddRedeemer2'_0 d1_1 _d3_2 = let n_3 = PlutusTx.Builtins.unsafeDataAsI d1_1
                              in if PlutusTx.Prelude.modulo n_3 2 PlutusTx.Eq.== 1
                                  then GHC.Tuple.()
                                  else PlutusTx.Builtins.error GHC.Tuple.()
-}

oddRedeemer2 :: AlonzoScript era
oddRedeemer2 =
  PlutusScript PlutusV1 . pack $
    concat
      [ [88, 65, 1, 0, 0, 51, 50, 34, 51, 34, 34, 83, 53, 48, 5],
        [51, 34, 51, 53, 115, 70, 110, 28, 0, 128, 4, 2, 64, 32, 204],
        [136, 205, 195, 0, 16, 0, 155, 173, 0, 36, 128, 17, 32, 2, 16],
        [4, 19, 38, 53, 48, 3, 0, 68, 152, 72, 0, 72, 0, 68, 136],
        [0, 132, 136, 0, 72, 0, 65]
      ]

{- Preproceesed Plutus Script
evenRedeemer2'_0 :: PlutusTx.Builtins.Internal.BuiltinData ->
                    PlutusTx.Builtins.Internal.BuiltinData -> ()
evenRedeemer2'_0 d1_1 _d3_2 = let n_3 = PlutusTx.Builtins.unsafeDataAsI d1_1
                               in if PlutusTx.Prelude.modulo n_3 2 PlutusTx.Eq.== 0
                                   then GHC.Tuple.()
                                   else PlutusTx.Builtins.error GHC.Tuple.()
-}

evenRedeemer2 :: AlonzoScript era
evenRedeemer2 =
  PlutusScript PlutusV1 . pack $
    concat
      [ [88, 65, 1, 0, 0, 51, 50, 34, 51, 34, 34, 83, 53, 48, 5],
        [51, 34, 51, 53, 115, 70, 110, 28, 0, 128, 4, 2, 64, 32, 204],
        [136, 205, 195, 0, 16, 0, 155, 173, 0, 36, 128, 17, 32, 0, 16],
        [4, 19, 38, 53, 48, 3, 0, 68, 152, 72, 0, 72, 0, 68, 136],
        [0, 132, 136, 0, 72, 0, 65]
      ]

{- Preproceesed Plutus Script
redeemerIs102'_0 :: PlutusTx.Builtins.Internal.BuiltinData ->
                    PlutusTx.Builtins.Internal.BuiltinData -> ()
redeemerIs102'_0 d1_1 _d3_2 = let n_3 = PlutusTx.Builtins.unsafeDataAsI d1_1
                               in if n_3 PlutusTx.Eq.== 10
                                   then GHC.Tuple.()
                                   else PlutusTx.Builtins.error GHC.Tuple.()
-}

redeemerIs102 :: AlonzoScript era
redeemerIs102 =
  PlutusScript PlutusV1 . pack $
    concat
      [ [88, 55, 1, 0, 0, 51, 50, 34, 51, 34, 34, 83, 53, 48, 5],
        [51, 34, 51, 53, 115, 70, 110, 28, 0, 128, 4, 2, 64, 32, 221],
        [104, 1, 36, 2, 130, 0, 130, 100, 198, 166, 0, 96, 8, 147, 9],
        [0, 9, 0, 8, 145, 0, 16, 145, 0, 9, 0, 9]
      ]

{- Preproceesed Plutus Script
guessTheNumber'2_0 :: PlutusTx.Builtins.Internal.BuiltinData ->
                      PlutusTx.Builtins.Internal.BuiltinData -> ()
guessTheNumber'2_0 d1_1 d2_2 = if d1_1 PlutusTx.Eq.== d2_2
                                then GHC.Tuple.()
                                else PlutusTx.Builtins.error GHC.Tuple.()
-}

guessTheNumber2V2 :: AlonzoScript era
guessTheNumber2V2 =
  PlutusScript PlutusV2 . pack $
    concat
      [ [88, 48, 1, 0, 0, 51, 50, 34, 51, 34, 34, 83, 53, 48, 5],
        [51, 53, 115, 70, 110, 188, 0, 128, 4, 1, 192, 24, 64, 16, 76],
        [152, 212, 192, 12, 1, 18, 97, 32, 1, 32, 1, 18, 32, 2, 18],
        [32, 1, 32, 1, 1]
      ]

{- Preproceesed Plutus Script
guessTheNumber'3_0 :: PlutusTx.Builtins.Internal.BuiltinData ->
                      PlutusTx.Builtins.Internal.BuiltinData ->
                      PlutusTx.Builtins.Internal.BuiltinData -> ()
guessTheNumber'3_0 d1_1 d2_2 _d3_3 = if d1_1 PlutusTx.Eq.== d2_2
                                      then GHC.Tuple.()
                                      else PlutusTx.Builtins.error GHC.Tuple.()
-}

guessTheNumber3V2 :: AlonzoScript era
guessTheNumber3V2 =
  PlutusScript PlutusV2 . pack $
    concat
      [ [88, 48, 1, 0, 0, 51, 50, 34, 51, 34, 34, 37, 51, 83, 0],
        [99, 51, 87, 52, 102, 235, 192, 12, 0, 128, 32, 1, 196, 1, 68],
        [201, 141, 76, 1, 0, 21, 38, 18, 0, 18, 0, 17, 34, 0, 33],
        [34, 0, 18, 0, 17]
      ]
