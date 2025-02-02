{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- | A 'Spec' is a first order data structure that denotes a random generator
--   For example
--   (MapSpec era dom rng) denotes Gen(Map dom rng)
--   (RngSpec era t)       denotes Gen[t]  where the [t] has some Summing properties
--   (RelSep era t)        denotes Gen(Set t) where the set meets some relational properties
--   (Size)                denotes Gen Int, the size of some Map, Set, List etc.
module Test.Cardano.Ledger.Constrained.Spec where

import Cardano.Ledger.Coin (Coin (..), DeltaCoin (..))
import Cardano.Ledger.Core (Era (..))
import qualified Data.List as List
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Word (Word64)
import Debug.Trace (trace)
import Test.Cardano.Ledger.Constrained.Ast (Pred (..), Sum (..), Term (..), runPred)
import Test.Cardano.Ledger.Constrained.Classes (
  Adds (..),
  Sums (..),
  genFromAddsSpec,
  genFromNonNegAddsSpec,
  projAdds,
  sumAdds,
 )
import Test.Cardano.Ledger.Constrained.Combinators (
  addUntilSize,
  errorMess,
  fixSet,
  setSized,
  subsetFromSet,
  suchThatErr,
  superSetFromSet,
  superSetFromSetWithSize,
 )
import Test.Cardano.Ledger.Constrained.Env (Access (No), V (..), emptyEnv, storeVar)
import Test.Cardano.Ledger.Constrained.Monad
import Test.Cardano.Ledger.Constrained.Size (
  AddsSpec (..),
  OrdCond (..),
  Size (..),
  atLeastDelta,
  atMostAny,
  genFromIntRange,
  genFromNonNegIntRange,
  genFromSize,
  runSize,
  seps,
  sepsP,
  vLeft,
  vRight,
 )
import Test.Cardano.Ledger.Constrained.TypeRep (
  Rep (..),
  genRep,
  synopsis,
  testEql,
  (:~:) (Refl),
 )
import Test.Cardano.Ledger.Core.Arbitrary ()
import Test.Cardano.Ledger.Generic.Proof (BabbageEra, Standard)
import Test.Cardano.Ledger.Shelley.Serialisation.EraIndepGenerators ()
import Test.Tasty
import Test.Tasty.QuickCheck hiding (total)

-- ===========================================================
{- TODO, possible extensions and improvements, so we don't forget
1) Redo Size with: data Size = SzNever [String] | SzRange Int (Maybe Int) Move to own file
2) Add newtype Never = Never [String], then instead of (XXXNever xs) we use (XX (Never xs))
3) class Specify
4) A better story about fields in constraints. Maybe add FieldSpec type.
-}

-- =========================================================

-- | used when we run tests, and we have to pick some concrete Era
type TT = BabbageEra Standard

-- ============================================================
-- Operators for Size (Defined in TypeRep.hs)

maxSize :: Size -> Int
maxSize SzAny = atMostAny
maxSize (SzLeast i) = i + atLeastDelta
maxSize (SzMost n) = n
maxSize (SzRng _ j) = j
maxSize (SzNever xs) = errorMess "SzNever in maxSize" xs

minSize :: Size -> Int
minSize SzAny = 0
minSize (SzLeast n) = n
minSize (SzMost _) = 0
minSize (SzRng i _) = i
minSize (SzNever xs) = errorMess "SzNever in minSize" xs

-- | Generate a Size with all positive numbers, This is used where
--   we want Size to denote things that must be >= 0. Coin, Word64, Natural
genSize :: Gen Size
genSize =
  frequency
    [ (1, SzLeast <$> pos)
    , (1, SzMost <$> chooseInt (0, atMostAny))
    , (1, (\x -> SzRng x x) <$> pos)
    , (1, do lo <- chooseInt (0, atMostAny); hi <- choose (lo + 1, lo + 6); pure (SzRng lo hi))
    ]

-- | Generate a Size denoting an Int range, across both positive
--   and negative numbers. DeltaCoin, Int, Rational. This is used
--   when we use Size to denote OrdCond on types with negative values
genSizeRange :: Gen Size
genSizeRange =
  frequency
    [ (1, SzLeast <$> someInt)
    , (1, SzMost <$> someInt)
    , (1, (\x -> SzRng x x) <$> someInt)
    , (1, do lo <- someInt; hi <- choose (lo + 1, lo + atMostAny); pure (SzRng lo hi))
    ]
  where
    someInt = chooseInt (-atMostAny, atMostAny)

genBigSize :: Int -> Gen Size
genBigSize n =
  frequency
    [ (1, SzLeast <$> choose (n + 1, n + 30))
    , -- , (1, SzMost <$> choose (n+60,n+90)) -- Without context, it is impossible to tell how big is OK
      (1, (\x -> SzRng x x) <$> choose (n + 1, n + 30))
    , (1, do lo <- choose (n + 1, n + 30); hi <- choose (lo + 1, lo + 30); pure (SzRng lo hi))
    ]

testSoundSize :: Gen Bool
testSoundSize = do
  spec <- genSize
  ans <- genFromSize spec
  pure $ runSize ans spec

testNonNegSize :: Gen Bool
testNonNegSize = do
  spec <- genSize
  ans <- genFromSize spec
  pure $ ans >= 0

testMergeSize :: Gen Bool
testMergeSize = do
  spec1 <- genSize
  spec2 <- genSize
  case spec1 <> spec2 of
    SzNever _xs -> pure True
    SzAny -> pure True
    spec -> do
      ans <- genFromSize spec
      pure $ runSize ans spec && runSize ans spec1 && runSize ans spec2

-- ==============

genSizeByRep :: forall t era. Adds t => Rep era t -> Gen Size
genSizeByRep IntR = genSizeRange
genSizeByRep DeltaCoinR = genSizeRange
genSizeByRep RationalR = genSizeRange
genSizeByRep Word64R = genSize
genSizeByRep CoinR = genSize
genSizeByRep NaturalR = genSize
genSizeByRep r = error ("genSizeByRep " ++ show r ++ " does not have an Adds instance." ++ seq (zero @t) "")

genFromSizeByRep :: forall t era. Adds t => Rep era t -> Size -> Gen Int
genFromSizeByRep IntR = genFromIntRange
genFromSizeByRep DeltaCoinR = genFromIntRange
genFromSizeByRep RationalR = genFromIntRange
genFromSizeByRep Word64R = genFromNonNegIntRange
genFromSizeByRep CoinR = genFromNonNegIntRange
genFromSizeByRep NaturalR = genFromNonNegIntRange
genFromSizeByRep r = error ("genFromSizeByRep " ++ show r ++ ", does not have an Adds instance." ++ seq (zero @t) "")

data SomeAdd era where Some :: Adds t => Rep era t -> SomeAdd era

instance Show (SomeAdd era) where
  show (Some x) = show x

genAddsRep :: Gen (SomeAdd era)
genAddsRep = elements [Some IntR, Some DeltaCoinR, Some RationalR, Some Word64R, Some CoinR, Some NaturalR]

testMergeSize2 :: Gen Property
testMergeSize2 = do
  Some rep <- genAddsRep
  spec1 <- genSizeByRep rep
  spec2 <- genSizeByRep rep
  case spec1 <> spec2 of
    SzNever _xs -> pure $ property True
    SzAny -> pure $ property True
    spec -> do
      ans <- genFromSizeByRep rep spec
      pure $
        counterexample
          ( "at type="
              ++ show rep
              ++ ", spec1="
              ++ show spec1
              ++ ", spec2="
              ++ show spec2
              ++ ", spec1<>spec2="
              ++ show spec
              ++ ", ans="
              ++ show ans
          )
          (runSize ans spec && runSize ans spec1 && runSize ans spec2)

main2 :: IO ()
main2 =
  defaultMain $ testProperty "Size2" testMergeSize2

-- =====================================================
-- RelSpec

data RelSpec era dom where
  RelAny ::
    -- | There is no restriction on the set. Denotes the universe.
    RelSpec era dom
  RelNever ::
    -- | Something is inconsistent
    [String] ->
    RelSpec era dom
  -- | Denotes things like: (x == y) equality, (x ⊆ y) subset, ( x ∩ y = ∅) disjointness, (x ⊇ y) superset.
  --   Invariants of r@(RepOper must (Just may) cant)
  -- 1) must is a subset of may
  -- 2) must and may are disjoint from cant
  -- 3) (sizeFromRel r) is realizable E.g.  (SzRng 10 3) is NOT realizable
  RelOper ::
    Ord d =>
    Rep era d ->
    -- | Must set
    Set d ->
    -- | May set, Nothing denotes the universe
    Maybe (Set d) ->
    -- | Can't set
    Set d ->
    RelSpec era d

relSubset, relSuperset, relDisjoint, relEqual :: Ord t => Rep era t -> Set t -> RelSpec era t
relSubset r set = RelOper r Set.empty (Just set) Set.empty
relSuperset r set = RelOper r set Nothing Set.empty
relDisjoint r set = RelOper r Set.empty Nothing set
relEqual r set = RelOper r set (Just set) Set.empty

instance Monoid (RelSpec era dom) where
  mempty = RelAny

instance Semigroup (RelSpec era dom) where
  (<>) = mergeRelSpec

instance Show (RelSpec era dom) where
  show = showRelSpec

instance LiftT (RelSpec era a) where
  liftT (RelNever xs) = failT xs
  liftT x = pure x
  dropT (Typed (Left s)) = RelNever s
  dropT (Typed (Right x)) = x

showRelSpec :: RelSpec era dom -> String
showRelSpec RelAny = "RelAny"
showRelSpec (RelOper r x (Just s) y) | Set.null y && x == s = sepsP ["RelEqual", synopsis (SetR r) x]
showRelSpec (RelOper r x (Just s) y) | Set.null x && Set.null y = sepsP ["RelSubset", synopsis (SetR r) s]
showRelSpec (RelOper r x Nothing y) | Set.null y = sepsP ["RelSuperset", synopsis (SetR r) x]
showRelSpec (RelOper r x Nothing y) | Set.null x = sepsP ["RelDisjoint", synopsis (SetR r) y]
showRelSpec (RelOper r x Nothing y) = sepsP ["RelOper", synopsis (SetR r) x, "Univ", synopsis (SetR r) y]
showRelSpec (RelOper r x (Just y) z) = sepsP ["RelOper", synopsis (SetR r) x, synopsis (SetR r) y, synopsis (SetR r) z]
showRelSpec (RelNever _) = "RelNever"

mergeRelSpec :: RelSpec era d -> RelSpec era d -> RelSpec era d
mergeRelSpec (RelNever xs) (RelNever ys) = RelNever (xs ++ ys)
mergeRelSpec d@(RelNever _) _ = d
mergeRelSpec _ d@(RelNever _) = d
mergeRelSpec RelAny x = x
mergeRelSpec x RelAny = x
mergeRelSpec a@(RelOper r must1 may1 cant1) b@(RelOper _ must2 may2 cant2) =
  dropT $
    explain ("merging a=" ++ show a ++ "\n        b=" ++ show b) $
      requireAll
        [
          ( Set.disjoint must1 cant2
          ,
            [ "The 'must' set of a("
                ++ synSet r must1
                ++ ") is not disjoint from the 'cant' set of b("
                ++ synSet r cant2
            ]
          )
        ,
          ( Set.disjoint must2 cant1
          ,
            [ "The 'must' set of b("
                ++ synSet r must2
                ++ ") is not disjoint from the 'cant' set of a("
                ++ synSet r cant1
            ]
          )
        ]
        (relOper r must may cant)
  where
    must = Set.union must1 must2
    cant = Set.union cant1 cant2
    may = (`Set.difference` cant) <$> interSectM may1 may2

-- ==================
-- Helper functions for defining mergeRelSpec and
-- for testing and maintaining RelSpec invariants

-- | The interpretation of (Just set) is set, and of Nothing is the universe (all possible sets)
interSectM :: Ord a => Maybe (Set a) -> Maybe (Set a) -> Maybe (Set a)
interSectM Nothing Nothing = Nothing
interSectM Nothing x = x
interSectM x Nothing = x
interSectM (Just x) (Just y) = Just (Set.intersection x y)

-- | Test if 's1' is a subset of 's2'
--   Recall, if s2==Nothing, then it denotes the universe
--   and every set is a subset of the universe.
univSubset :: Ord a => Set a -> Maybe (Set a) -> Bool
univSubset _ Nothing = True
univSubset s1 (Just s2) = Set.isSubsetOf s1 s2

okSize :: RelSpec era d -> Bool
okSize (RelOper _ must (Just may) cant) =
  Set.size must <= Set.size (Set.difference may cant)
okSize _ = True

-- | Compute the Size that bounds the Size of a set generated from a RelSpec
sizeForRel :: RelSpec era dom -> Size
sizeForRel RelAny = SzAny
sizeForRel (RelNever _) = SzAny
sizeForRel (RelOper _ must Nothing _) = SzLeast (Set.size must)
sizeForRel (RelOper _ must (Just may) _) | Set.null must = SzMost (Set.size may)
sizeForRel (RelOper _ must (Just may) cant) = SzRng (Set.size must) (Set.size (Set.difference may cant))

maybeSynopsis :: Rep e t -> Maybe t -> String
maybeSynopsis r (Just x) = synopsis r x
maybeSynopsis _ _ = ""

synSet :: Ord t => Rep era t -> Set t -> String
synSet r s = synopsis (SetR r) s

-- | Check that RelSpec invariants on the constructor RelOper hold on: spec@(RelOper must may cant)
--   1)  must ⊆ may, checked by 'univSubset must may'
--   2)  (must ∩ cant = ∅), checked by 'Set.disjoint must cant'
--   3)  Set.size must <= Set.size (Set.difference may cant), checked by 'okSize spec'
relOper :: Ord d => Rep era d -> Set d -> Maybe (Set d) -> Set d -> Typed (RelSpec era d)
relOper r must may cant =
  let potential = RelOper r must may cant
   in explain
        ("Checking RelSpec self consistency\n   " ++ show (RelOper r must may cant))
        ( requireAll
            [
              ( univSubset must may
              ,
                [ "'must' "
                    ++ synopsis (SetR r) must
                    ++ " Is not a subset of: 'may' "
                    ++ maybeSynopsis (SetR r) may
                ]
              )
            ,
              ( Set.disjoint must cant
              ,
                [ "'must' "
                    ++ synopsis (SetR r) must
                    ++ "Is not disjoint from: 'cant' "
                    ++ synopsis (SetR r) cant
                ]
              )
            ,
              ( maybe True (\may' -> Set.disjoint may' cant) may
              ,
                [ "'may' "
                    ++ maybe "Nothing" (synopsis $ SetR r) may
                    ++ "Is not disjoint from: 'cant' "
                    ++ synopsis (SetR r) cant
                ]
              )
            ,
              ( okSize potential
              , case potential of
                  rel@(RelOper _ _ (Just mayJ) _) ->
                    [ show potential ++ " has unrealizable size " ++ show (sizeForRel rel)
                    , "size must("
                        ++ show (Set.size must)
                        ++ ") > size(mayJ - cant)("
                        ++ show (Set.size (Set.difference mayJ cant))
                        ++ ")"
                    ]
                  _ -> []
              )
            ]
            (pure potential)
        )

-- ==============================================
-- The standard operations on RelSpec
-- runRelSpec, genFromRelSpec, genRelSpec

-- | test that a set 's' meets the RelSpec
runRelSpec :: Ord t => Set t -> RelSpec era t -> Bool
runRelSpec _ RelAny = True
runRelSpec _ (RelNever xs) = errorMess "RelNever in call to runRelSpec" xs
runRelSpec s (RelOper _ must Nothing cant) = Set.isSubsetOf must s && Set.disjoint s cant
runRelSpec s (RelOper _ must (Just may) cant) = Set.isSubsetOf must s && Set.isSubsetOf s may && Set.disjoint s cant

-- | return a generator that always generates things that meet the RelSpec
genFromRelSpec :: forall era t. Ord t => [String] -> Gen t -> Int -> RelSpec era t -> Gen (Set t)
genFromRelSpec msgs g n spec =
  let msg = "genFromRelSpec " ++ show n ++ " " ++ show spec
   in case spec of
        RelNever xs -> errorMess "RelNever in genFromSpec" (msgs ++ xs)
        RelAny -> setSized (msg : msgs) n g
        RelOper _ must (Just may) cant | must == may && Set.null cant -> pure must -- The is the (relEqual r s) case
        RelOper _ must Nothing dis ->
          -- add things (not in cant) to 'must' until you get to size 'n'
          fixSet (msg : msgs) 1000 n (suchThatErr (msg : msgs) g (`Set.notMember` dis)) must
        RelOper _ must (Just may) dis ->
          let choices = Set.difference may dis
              m = Set.size choices
           in -- add things (from choices) to 'must' until you get to size 'n'
              case compare m n of
                EQ -> pure choices
                LT ->
                  errorMess
                    ( "Size inconsistency. We need "
                        ++ show n
                        ++ ". The most we can get from (may-cant) is "
                        ++ show m
                    )
                    (msg : msgs)
                GT -> addUntilSize (msg : msgs) must choices n

-- | Generate a random RelSpec
genRelSpec :: Ord dom => [String] -> Gen dom -> Rep era dom -> Int -> Gen (RelSpec era dom)
genRelSpec _ _ r 0 = pure $ relEqual r Set.empty
genRelSpec msg genD r n = do
  smaller <- choose (1, min 2 (n - 1))
  larger <- choose (n + 5, n + 7)
  let msgs = (sepsP ["genRelSpec ", show n, show r, " smaller=", show smaller, ", larger=", show larger]) : msg
  frequency
    [
      ( 1
      , do
          must <- setSized ("must of RelOper Nothing" : msgs) smaller genD
          dis <- someSet (suchThatErr (("dis of RelOper Nothing " ++ synSet r must) : msgs) genD (`Set.notMember` must))
          monadTyped (relOper r must Nothing dis)
      )
    ,
      ( 2
      , do
          must <- setSized ("must of RelOper Just" : msgs) smaller genD
          may <- superSetFromSetWithSize ("may of RelOper Just" : msgs) larger genD must
          dis <-
            setSized
              ("dis of RelOper Some" : msgs)
              3
              (suchThatErr (("dis of RelOper Some must=" ++ synSet r must ++ " may=" ++ synSet r may) : msgs) genD (`Set.notMember` may))
          monadTyped (relOper r must (Just may) dis)
      )
    , (1, pure RelAny)
    ]

-- | Generate another set which is disjoint from the input 'set'
--   Note that the empty set is always a solution.
--   These sets tend to be rather small (size <= atLeastDelta)
genDisjoint :: Ord a => Set a -> Gen a -> Gen (Set a)
genDisjoint set gen = help atLeastDelta Set.empty
  where
    help n !answer | n < 0 = pure answer
    help n !answer = do
      x <- gen
      help (n - 1) (if Set.member x set then answer else Set.insert x answer)

-- | Generate another RelSpec, guaranteed to be consistent with the input
--   Where (consistent a b) means:  (a <> b) =/= (RelNever _)
--   See the property test 'genConsistent'
genConsistentRelSpec :: [String] -> Gen dom -> RelSpec era dom -> Gen (RelSpec era dom)
genConsistentRelSpec msg g x = case x of
  RelOper r must Nothing cant ->
    frequency
      [ (1, pure RelAny)
      ,
        ( 1
        , do
            cant2 <- genDisjoint must g
            must2 <- genDisjoint (cant <> cant2) g
            pure $ RelOper r must2 Nothing cant2
        )
      ,
        ( 1
        , do
            may2 <- (`Set.difference` cant) <$> superSetFromSet g must
            must2 <- subsetFromSet ((show x ++ " gen may") : msgs) must
            cant2 <- genDisjoint may2 g
            pure $ RelOper r must2 (Just may2) cant2
        )
      ]
  RelOper r must (Just may) cant ->
    frequency
      [ (1, pure RelAny)
      ,
        ( 1
        , do
            cant2 <- genDisjoint may g
            must2 <- subsetFromSet ((show x ++ " gen must") : msgs) may
            pure $ RelOper r must2 Nothing cant2
        )
      ,
        ( 1
        , do
            may2 <- (`Set.difference` cant) <$> superSetFromSet g must
            must2 <- subsetFromSet ((show x ++ " gen must") : msgs) must
            cant2 <- genDisjoint (may <> may2) g
            pure $ RelOper r must2 (Just (may <> may2)) cant2
        )
      ]
  RelAny -> pure RelAny
  RelNever _ -> error "RelNever in genConsistentRelSpec"
  where
    msgs = ("genConsistentRelSpec " ++ show x) : msg

-- ==================
-- Actual property tests for Relpec

testConsistentRel :: Gen Property
testConsistentRel = do
  n <- chooseInt (3, 10)
  s1 <- genRelSpec ["testConsistentRel " ++ show n] (choose (1, 10000)) IntR n
  s2 <- genConsistentRelSpec ["testConsistentRel " ++ show n ++ " " ++ show s1] (choose (1, 1000)) s1
  case s1 <> s2 of
    RelNever ms -> pure $ counterexample (unlines (["genConsistent fails", show s1, show s2] ++ ms)) False
    _ -> pure $ property True

testSoundRelSpec :: Gen Property
testSoundRelSpec = do
  n <- chooseInt (3, 10)
  s1 <- genRelSpec ["from testSoundRelSpec " ++ show n] (choose (1, 10000)) Word64R n
  ans <- genFromRelSpec @TT ["from testSoundRelSpec " ++ show n] (choose (1, 100000)) n s1
  pure $ counterexample ("spec=" ++ show s1 ++ "\nans=" ++ show ans) (runRelSpec ans s1)

testMergeRelSpec :: Gen Property
testMergeRelSpec = do
  let msg = ["testMergeRelSpec"]
  n <- chooseInt (0, 10)
  s1 <- genRelSpec (("genRelSpec") : msg) (choose (1, 10000)) Word64R n
  s2 <- genConsistentRelSpec (("genConsistentRepSpec " ++ show s1) : msg) (choose (1, 1000)) s1
  case s1 <> s2 of
    RelNever _ -> pure (property True) -- This test is an implication (consistent (s1 <> s2) => ...)
    s4 -> do
      let size = sizeForRel s4
      m <- genFromSize size
      ans <- genFromRelSpec ["testMergeRelSpec " ++ show s1 ++ " " ++ show s2] (choose (1, 1000)) m s4
      pure $
        counterexample
          ( "s1="
              ++ show s1
              ++ "\ns2="
              ++ show s2
              ++ "\ns1<>s2="
              ++ show s4
              ++ "\nans="
              ++ show ans
              ++ "\nrun s1="
              ++ show (runRelSpec ans s1)
              ++ "\nrun s2="
              ++ show (runRelSpec ans s2)
              ++ "\nrun s4="
              ++ show (runRelSpec ans s4)
          )
          (runRelSpec ans s4 && runRelSpec ans s2 && runRelSpec ans s1)

consistent :: (LiftT a, Semigroup a) => a -> a -> Maybe a
consistent x y = case runTyped (liftT (x <> y)) of
  Left _ -> Nothing
  Right spec -> Just spec

manyMergeRelSpec :: Gen (Int, Int, [String])
manyMergeRelSpec = do
  n <- chooseInt (3, 10)
  xs <- vectorOf 60 (genRelSpec ["manyMergeRelSpec xs"] (choose (1, 100)) IntR n)
  ys <- vectorOf 60 (genRelSpec ["manyMergeRelSpec ys"] (choose (1, 100)) IntR n)
  let ok RelAny = False
      ok _ = True
      check (x, y, m) = do
        let size = sizeForRel m
        i <- genFromSize size
        let wordsX =
              [ "s1<>s2 Size = " ++ show (sizeForRel m)
              , "s1<>s2 = " ++ show m
              , "s2 Size = " ++ show (sizeForRel x)
              , "s2 = " ++ show x
              , "s1 Size = " ++ show (sizeForRel y)
              , "s1 = " ++ show y
              , "GenFromRelSpec " ++ show i ++ " n=" ++ show n
              ]
        z <- genFromRelSpec @TT wordsX (choose (1, 100)) i m
        pure (x, runRelSpec z x, y, runRelSpec z y, z, runRelSpec z m, m)
      showAns (s1, run1, s2, run2, v, run3, s3) =
        unlines
          [ "\ns1 = " ++ show s1
          , "s1 Size = " ++ show (sizeForRel s1)
          , "s2 = " ++ show s2
          , "s2 Size = " ++ show (sizeForRel s2)
          , "s1 <> s2 = " ++ show s3
          , "s1<>s2 Size = " ++ show (sizeForRel s3)
          , "v = genFromRelSpec (s1 <> s2) = " ++ show v
          , "runRelSpec v s1 = " ++ show run1
          , "runRelSpec v s2 = " ++ show run2
          , "runRelSpec v (s1 <> s2) = " ++ show run3
          ]
      pr x@(_, a, _, b, _, c, _) = if not (a && b && c) then Just (showAns x) else Nothing
  let trips = [(x, y, m) | x <- xs, y <- ys, ok x && ok y, Just m <- [consistent x y]]
  ts <- mapM check trips
  pure $ (n, length trips, Maybe.mapMaybe pr ts)

reportManyMergeRelSpec :: IO ()
reportManyMergeRelSpec = do
  (n, passed, bad) <- generate manyMergeRelSpec
  if null bad
    then putStrLn ("passed " ++ show passed ++ " tests. Spec size " ++ show n)
    else do mapM_ putStrLn bad; error "TestFails"

-- ==========================================================

-- | Indicates which constraints (if any) the range of a Map must adhere to
--   There are 3 cases RngSum, RngProj, and RngRel. They are all mutually inconsistent.
--   So while any Map may constrain its range, it can only choose ONE of the cases.
data RngSpec era rng where
  -- | The set must have Adds instance and add up to 'rng'
  RngSum ::
    Adds rng =>
    rng -> -- the smallest element in the partition (usually 0 or 1)
    Size -> -- the sum of all the elements must fall in the range denoted by the Size
    RngSpec era rng
  -- | The range must sum upto 'c' through the projection witnessed by the (Sums t c) class
  RngProj ::
    (Sums x c) =>
    c -> -- the smallest element in the partition (usually 0 or 1)
    Rep era c ->
    Size -> -- the sum of all the elements must fall in the range denoted by the Size
    RngSpec era x
  -- | The range has exactly these elements
  RngElem :: Eq r => Rep era r -> [r] -> RngSpec era r
  -- | The range must hold on the relation specified
  RngRel :: Ord x => RelSpec era x -> RngSpec era x
  -- | There are no constraints on the range (random generator will do)
  RngAny :: RngSpec era rng
  -- | Something was inconsistent
  RngNever :: [String] -> RngSpec era rng

instance Show (RngSpec era t) where
  show = showRngSpec

instance Monoid (RngSpec era rng) where
  mempty = RngAny

instance Semigroup (RngSpec era rng) where
  (<>) = mergeRngSpec

instance LiftT (RngSpec era a) where
  liftT (RngNever xs) = failT xs
  liftT x = pure x
  dropT (Typed (Left s)) = RngNever s
  dropT (Typed (Right x)) = x

showRngSpec :: RngSpec era t -> String
showRngSpec (RngSum small sz) = sepsP ["RngSum", show small, show sz]
showRngSpec (RngProj small r sz) = sepsP ["RngProj", show small, show r, show sz]
showRngSpec (RngElem r cs) = sepsP ["RngElem", show r, synopsis (ListR r) cs]
showRngSpec (RngRel x) = sepsP ["RngRel", show x]
showRngSpec RngAny = "RngAny"
showRngSpec (RngNever _) = "RngNever"

mergeRngSpec :: forall r era. RngSpec era r -> RngSpec era r -> RngSpec era r
mergeRngSpec RngAny x = x
mergeRngSpec x RngAny = x
mergeRngSpec (RngRel RelAny) x = x
mergeRngSpec x (RngRel RelAny) = x
mergeRngSpec _ (RngNever xs) = RngNever xs
mergeRngSpec (RngNever xs) _ = RngNever xs
mergeRngSpec a@(RngElem _ xs) b
  | runRngSpec xs b = a
  | otherwise = RngNever ["The RngSpec's are inconsistent.\n  " ++ show a ++ "\n  " ++ show b]
mergeRngSpec a b@(RngElem _ xs)
  | runRngSpec xs a = b
  | otherwise = RngNever ["The RngSpec's are inconsistent.\n  " ++ show a ++ "\n  " ++ show b]
mergeRngSpec a@(RngSum small1 sz1) b@(RngSum small2 sz2) =
  case sz1 <> sz2 of
    SzNever xs -> RngNever (["The RngSpec's are inconsistent.\n  " ++ show a ++ "\n  " ++ show b] ++ xs)
    sz3 -> RngSum (min small1 small2) sz3
mergeRngSpec a@(RngProj sm1 r1 s1) b@(RngProj sm2 r2 s2) =
  case testEql r1 r2 of
    Just Refl -> case s1 <> s2 of
      SzNever xs -> RngNever (["The RngSpec's are inconsistent.\n  " ++ show a ++ "\n  " ++ show b] ++ xs)
      s3 -> RngProj (min sm1 sm2) r1 s3
    Nothing -> RngNever [show a, show b, "The RngSpec's are inconsistent.", show r1 ++ " =/= " ++ show r2]
mergeRngSpec a@(RngRel r1) b@(RngRel r2) =
  case r1 <> r2 of
    RelNever xs -> RngNever (["The RngSpec's are inconsistent.\n  " ++ show a ++ "\n  " ++ show b] ++ xs)
    r3 -> RngRel r3
mergeRngSpec a b = RngNever ["The RngSpec's are inconsistent.\n  " ++ show a ++ "\n  " ++ show b]

-- ===================================================================

-- | Compute the Size that is appropriate for a RngSpec
sizeForRng :: forall dom era. RngSpec era dom -> Size
sizeForRng (RngRel x) = sizeForRel x
sizeForRng (RngSum small sz) =
  if toI small > 0
    then SzRng 1 (minSize sz `div` toI small)
    else SzLeast 1
sizeForRng (RngProj small (_r :: (Rep era c)) sz) =
  if toI small > 0
    then SzRng 1 (minSize sz `div` toI small)
    else SzLeast 1
sizeForRng (RngElem _ xs) = SzExact (length xs)
sizeForRng RngAny = SzAny
sizeForRng (RngNever _) = SzAny

-- ------------------------------------------
-- generators for test functions.

-- | Generate an arbitrary size [r] for a particular size 'n'
--   The generated list is consistent with the RngSpec given as input.
genFromRngSpec :: forall era r. [String] -> Gen r -> Int -> RngSpec era r -> Gen [r]
genFromRngSpec msgs genr n x = case x of
  (RngNever xs) -> errorMess "RngNever in genFromRngSpec" (xs ++ (msg : msgs))
  RngAny -> vectorOf n genr
  (RngSum small sz) -> do
    tot <- genFromIntRange sz
    partition small (msg : msgs) n (fromI (msg : msgs) tot)
  (RngProj small _ sz) -> do
    tot <- genFromIntRange sz
    rs <- partition small (("partition " ++ show tot) : msg : msgs) n (fromI (msg : msgs) tot)
    mapM (genT msgs) rs
  (RngRel relspec) -> Set.toList <$> genFromRelSpec (msg : msgs) genr n relspec
  (RngElem _ xs) -> pure xs
  where
    msg = "genFromRngSpec " ++ show n ++ " " ++ show x

-- | Generate a random RngSpec, appropriate for a given size. In order to accomodate any OrdCond
--   (EQL, LTH, LTE, GTE, GTH) in RngSum and RngProj, we make the total a bit larger than 'n'
genRngSpec ::
  forall w c era.
  ( Adds w
  , Sums w c
  ) =>
  Gen w ->
  Rep era w ->
  Rep era c ->
  Int ->
  Gen (RngSpec era w)
genRngSpec _ repw _ 0 = pure $ RngRel (relEqual repw Set.empty)
genRngSpec g repw repc n = do
  frequency
    [
      ( 3
      , do
          smallest <- genSmall @w -- Chooses smallest appropriate for type 'w'
          sz <- genBigSize (max 1 (smallest * n))
          pure (RngSum (fromI ["genRngSpec " ++ show n] smallest) sz)
      )
    ,
      ( 2
      , do
          smallest <- genSmall @c
          sz <- genBigSize (max 1 (smallest * n))
          pure (RngProj (fromI ["genRngSpec " ++ show n] smallest) repc sz)
      )
    , (4, RngRel <$> genRelSpec @w ["genRngSpec "] g repw n)
    , (1, pure RngAny)
    , (2, RngElem repw <$> vectorOf n g)
    ]

runRngSpec :: [r] -> RngSpec era r -> Bool
runRngSpec _ (RngNever _) = False
runRngSpec _ RngAny = True
runRngSpec ll (RngElem _ xs) = ll == xs
runRngSpec ll (RngSum _ sz) = runSize (toI (sumAdds ll)) sz
runRngSpec ll (RngProj _ _ sz) = runSize (toI (projAdds ll)) sz
runRngSpec ll (RngRel rspec) = runRelSpec (Set.fromList ll) rspec

-- ------------------------------------------
-- generators for RngSpec

instance Sums Word64 Coin where
  getSum n = Coin $ fromIntegral n
  genT _ (Coin n) = pure (fromIntegral n)

instance Sums Int DeltaCoin where
  getSum n = DeltaCoin $ fromIntegral n
  genT _ (DeltaCoin n) = pure (fromIntegral n)

instance Sums Coin Word64 where
  getSum (Coin n) = fromIntegral n
  genT _ n = pure (Coin (fromIntegral n))

genConsistentRngSpec ::
  ( Adds w
  , Sums w c
  ) =>
  Int ->
  Gen w ->
  Rep era w ->
  Rep era c ->
  Gen (RngSpec era w, RngSpec era w)
genConsistentRngSpec n g repw repc = do
  x1 <- genRngSpec g repw repc n
  x2 <- case x1 of
    RngAny -> genRngSpec g repw repc n
    RngRel RelAny -> genRngSpec g repw repc n
    RngRel x -> RngRel <$> genConsistentRelSpec msgs g x
    RngSum sm sz -> do
      sz2 <- suchThat genSize (Maybe.isJust . consistent sz)
      pure $ RngSum (add sm (fromI msgs 2)) sz2 -- Make the smaller bigger
    RngProj sm rep sz -> do
      sz2 <- suchThat genSize (Maybe.isJust . consistent sz)
      pure $ RngProj (add sm (fromI msgs 2)) rep sz2
    RngElem _ xs ->
      frequency
        [ (1, pure $ RngSum (fromI msgs 1) (SzExact (toI (sumAdds xs))))
        , (1, pure $ RngProj (fromI msgs 1) repc (SzExact (toI (projAdds xs))))
        ]
    RngNever xs -> errorMess "RngNever in genConsistentRngSpec" xs
  pure (x1, x2)
  where
    msgs = [seps ["genConsistentRngSpec", show repw, show repc]]

-- Tests

testConsistentRng :: Gen Property
testConsistentRng = do
  n <- chooseInt (3, 10)
  (s1, s2) <- genConsistentRngSpec @_ @_ @TT n (choose (1, 1000)) Word64R CoinR
  case s1 <> s2 of
    RngNever ms -> pure $ counterexample (unlines (["genConsistentRng fails", show s1, show s2] ++ ms)) False
    _ -> pure $ counterexample "" True

testSoundRngSpec :: Gen Property
testSoundRngSpec = do
  n <- choose (2, 8)
  spec <- genRngSpec (choose (1, 1000)) Word64R CoinR n
  let msgs = ["testSoundRngSpec " ++ show n ++ " " ++ show spec]
  list <- genFromRngSpec @TT msgs (choose (1, 1000)) n spec
  pure $
    counterexample
      ("spec=" ++ show spec ++ "\nlist=" ++ show list)
      (runRngSpec list spec)

testMergeRngSpec :: Gen Property
testMergeRngSpec = do
  (s1, s2) <- genConsistentRngSpec 3 (choose (1, 1000)) Word64R CoinR
  case s1 <> s2 of
    RngNever _ -> trace ("inconsistent RngSpec " ++ show s1 ++ " " ++ show s2) (pure (counterexample "" True))
    s3 -> do
      let size = sizeForRng s3
      n <- genFromSize size
      let wordsX =
            [ "s1=" ++ show s1
            , "s2=" ++ show s2
            , "s3=" ++ show s3
            , "size=" ++ show size
            , "n=" ++ show n
            , "testMergeRngSpec"
            ]
      list <- genFromRngSpec @TT wordsX (choose (1, 1000)) n s3
      pure $
        counterexample
          ( "s1="
              ++ show s1
              ++ "\n  s2="
              ++ show s2
              ++ "\n  s3="
              ++ show s3
              ++ "\n  size="
              ++ show size
              ++ "\n  n="
              ++ show n
              ++ "\n  list="
              ++ synopsis (ListR Word64R) list
              ++ "\n  run1="
              ++ show (runRngSpec list s1)
              ++ "\n run2="
              ++ show (runRngSpec list s2)
          )
          (runRngSpec list s1 && runRngSpec list s2)

manyMergeRngSpec :: Gen (Int, Int, [String])
manyMergeRngSpec = do
  n <- chooseInt (3, 10)
  xs <- vectorOf 50 (genRngSpec (choose (1, 100)) IntR DeltaCoinR n)
  ys <- vectorOf 50 (genRngSpec (choose (1, 100)) IntR DeltaCoinR n)
  let check (x, y, m) = do
        let size = sizeForRng m
        i <- genFromSize size
        let wordsX =
              [ "s1<>s2 Size = " ++ show (sizeForRng m)
              , "s1<>s2 = " ++ show m
              , "s2 Size = " ++ show (sizeForRng x)
              , "s2 = " ++ show x
              , "s1 Size = " ++ show (sizeForRng y)
              , "s1 = " ++ show y
              , "GenFromRngSpec " ++ show i ++ " n=" ++ show n
              ]
        z <- genFromRngSpec @TT wordsX (choose (1, 100)) i m
        pure (x, runRngSpec z x, y, runRngSpec z y, z, runRngSpec z m, m)
      showAns (s1, run1, s2, run2, v, run3, s3) =
        unlines
          [ "\ns1 = " ++ show s1
          , "s1 Size = " ++ show (sizeForRng s1)
          , "s2 = " ++ show s2
          , "s2 Size = " ++ show (sizeForRng s2)
          , "s1 <> s2 = " ++ show s3
          , "s1<>s2 Size = " ++ show (sizeForRng s3)
          , "v = genFromRngSpec (s1 <> s2) = " ++ show v
          , "runRngSpec v s1 = " ++ show run1
          , "runRngSpec v s2 = " ++ show run2
          , "runRngSpec v (s1 <> s2) = " ++ show run3
          ]
      pr x@(_, a, _, b, _, c, _) = if not (a && b && c) then Just (showAns x) else Nothing
  let trips = [(x, y, m) | x <- xs, y <- ys, Just m <- [consistent x y]]
  ts <- mapM check trips
  pure $ (n, length trips, Maybe.mapMaybe pr ts)

reportManyMergeRngSpec :: IO ()
reportManyMergeRngSpec = do
  (n, passed, bad) <- generate manyMergeRngSpec
  if null bad
    then putStrLn ("passed " ++ show passed ++ " tests. Spec size " ++ show n)
    else do mapM_ putStrLn bad; error "TestFails"

-- =====================================================

data Unique dom rng = Unique String (Gen (Map dom rng))

instance Show (Unique dom rng) where
  show (Unique s _) = s

-- | Indicates which constraints (if any) a Map must adhere to
data MapSpec era dom rng where
  -- | The map may be constrained 3 ways. 1) Its size(Size) 2) its domain(RelSpec) 3) its range(RngSpec)
  MapSpec ::
    Size ->
    RelSpec era dom ->
    RngSpec era rng ->
    MapSpec era dom rng
  -- | Currently used to generate from (Component x fields) Pred. The plan
  --   is to replace it with some sort of FieldSpec soon.
  MapUnique :: Rep era (Map dom rng) -> Unique dom rng -> MapSpec era dom rng
  -- | Something is inconsistent
  MapNever :: [String] -> MapSpec era dom rng

instance Ord d => Show (MapSpec w d r) where
  show = showMapSpec

instance (Ord dom) => Semigroup (MapSpec era dom rng) where
  (<>) = mergeMapSpec

instance (Ord dom) => Monoid (MapSpec era dom rng) where
  mempty = MapSpec SzAny RelAny RngAny

instance LiftT (MapSpec era a b) where
  liftT (MapNever xs) = failT xs
  liftT x = pure x
  dropT (Typed (Left s)) = MapNever s
  dropT (Typed (Right x)) = x

showMapSpec :: MapSpec era dom rng -> String
showMapSpec (MapSpec w d r) = sepsP ["MapSpec", show w, showRelSpec d, showRngSpec r]
showMapSpec (MapUnique _ (Unique nm _)) = "(MapUnique " ++ nm ++ ")"
showMapSpec (MapNever _) = "MapNever"

mergeMapSpec :: Ord dom => MapSpec era dom rng -> MapSpec era dom rng -> MapSpec era dom rng
mergeMapSpec spec1 spec2 = case (spec1, spec2) of
  (MapNever s, MapNever t) -> MapNever (s ++ t)
  (MapNever _, y) -> y
  (x, MapNever _) -> x
  (MapSpec SzAny RelAny RngAny, x) -> x
  (x, MapSpec SzAny RelAny RngAny) -> x
  (MapSpec s1 d1 r1, MapSpec s2 d2 r2) -> case mergeRngSpec r1 r2 of
    RngNever msgs -> MapNever (["The MapSpec's are inconsistent.", "  " ++ show spec1, "  " ++ show spec2] ++ msgs)
    r -> case mergeRelSpec d1 d2 of
      RelNever msgs -> MapNever (["The MapSpec's are inconsistent.", "  " ++ show spec1, "  " ++ show spec2] ++ msgs)
      d -> dropT (explain ("While merging\n   " ++ show spec1 ++ "\n   " ++ show spec2) (mapSpec (s1 <> s2) d r))
  (MapUnique _ x, y) ->
    MapNever
      [ "(Unique " ++ show x
      , "is never mergeable which another MapSpec such as"
      , showMapSpec y
      ]
  (y, MapUnique _ x) ->
    MapNever
      [ "(Unique " ++ show x
      , "is never mergeable which another MapSpec such as"
      , showMapSpec y
      ]

-- | Use 'mapSpec' instead of 'MapSpec' to check size consistency at creation time.
--   Runs in the type monad, so errors are caught and reported as Solver-time errors.
--   This should avoid many Gen-time errors, as many of those are cause by size
--   inconsistencies. We can also use this in mergeMapSpec, to catch size
--   inconsistencies there as well as (\ a b c -> dropT (mapSpec a b c)) has the same
--   type as MapSpec, but pushes the reports of inconsistencies into MapNever.
mapSpec :: Ord dom => Size -> RelSpec era dom -> RngSpec era rng -> Typed (MapSpec era dom rng)
mapSpec sz1 rel rng = case sz1 <> sz2 <> sz3 of
  SzNever xs ->
    failT
      ( [ "Creating " ++ show (MapSpec sz1 rel rng) ++ " fails."
        , "It has size inconsistencies."
        , "  " ++ show rel ++ " has size " ++ show sz2
        , "  " ++ show rng ++ " has size " ++ show sz3
        ]
          ++ xs
      )
  size -> pure (MapSpec size rel rng)
  where
    sz2 = sizeForRel rel
    sz3 = sizeForRng rng

-- ------------------------------------------
-- MapSpec test functions

-- | test a Map against a MapSpec
runMapSpec :: Ord d => Map d r -> MapSpec era d r -> Bool
runMapSpec _ (MapNever xs) = errorMess "MapNever in runMapSpec" xs
runMapSpec _ (MapSpec SzAny RelAny RngAny) = True
runMapSpec m (MapSpec sz dom rng) =
  runSize (Map.size m) sz
    && runRelSpec (Map.keysSet m) dom
    && runRngSpec (Map.elems m) rng
runMapSpec _ (MapUnique _ _) = error "Remove MapUnique, replace with RelSpec (relEqual)"

-- | compute a Size that bounds a MapSpec
sizeForMapSpec :: MapSpec era d r -> Size
sizeForMapSpec (MapSpec sz _ _) = sz
sizeForMapSpec (MapNever _) = SzAny
sizeForMapSpec (MapUnique _ _) = SzAny

-- ----------------------------------------
-- MapSpec generators

-- | Generate a random MapSpec
genMapSpec ::
  forall era dom w c.
  (Ord dom, Era era, Adds w, Sums w c) =>
  Gen dom ->
  Rep era dom ->
  Rep era w ->
  Rep era c ->
  Int ->
  Gen (MapSpec era dom w)
genMapSpec genD repd repw repc n = frequency [(1, pure mempty), (6, genmapspec)]
  where
    genmapspec = do
      relspec <- genRelSpec ["genMapSpec " ++ show n ++ " " ++ show repd] genD repd n
      rngspec <- genRngSpec (genRep @era repw) repw repc n
      pure (MapSpec (SzExact n) relspec rngspec)

-- | Generate a (Map d t) from a (MapSpec era d r)
genFromMapSpec :: forall era w dom. Ord dom => (V era (Map dom w)) -> [String] -> Gen dom -> Gen w -> MapSpec era dom w -> Gen (Map dom w)
genFromMapSpec nm _ _ _ (MapNever xs) = errorMess ("genFromMapSpec " ++ (show nm) ++ " (MapNever _) fails") xs
genFromMapSpec _ _ _ _ (MapUnique _ (Unique _ gen)) = gen
genFromMapSpec nm msgs genD genR ms@(MapSpec size rel rng) = do
  n <- genFromSize size
  dom <-
    genFromRelSpec
      (("GenFromMapSpec " ++ (show nm) ++ "\n   " ++ show ms) : msgs)
      genD
      n
      rel
  rangelist <-
    genFromRngSpec
      (("genFromMapSpec " ++ (show nm) ++ "\n   " ++ show ms) : msgs)
      genR
      n
      rng
  pure (Map.fromList (zip (Set.toList dom) rangelist))

genMapSpecIsSound :: Gen Property
genMapSpecIsSound = do
  n <- chooseInt (1, 15)
  spec <- genMapSpec (chooseInt (1, 10000)) IntR Word64R CoinR n
  mp <- genFromMapSpec @TT (V "mapSpecIsSound" (MapR IntR Word64R) No) [] (choose (1, 10000)) (choose (1, 10000)) spec
  pure $ counterexample ("spec = " ++ show spec ++ "\nmp = " ++ show mp) (runMapSpec mp spec)

manyMergeMapSpec :: Gen (Int, Int, [String])
manyMergeMapSpec = do
  n <- chooseInt (1, 10)
  xs <- vectorOf 50 (genMapSpec (choose (1, 100)) IntR Word64R CoinR n)
  ys <- vectorOf 50 (genMapSpec (choose (1, 100)) IntR Word64R CoinR n)
  let check (x, y, m) = do
        let msize = sizeForMapSpec m
        i <- genFromSize msize
        let wordsX =
              [ "s1<>s2 Size = " ++ show msize
              , "s1<>s2 = " ++ show m
              , "s2 Size = " ++ show (sizeForMapSpec x)
              , "s2 = " ++ show x
              , "s1 Size = " ++ show (sizeForMapSpec y)
              , "s1 = " ++ show y
              , "GenFromMapSpec " ++ show i ++ " n=" ++ show n
              ]
        z <- genFromMapSpec @TT (V "manyMergeMap" (MapR IntR Word64R) No) wordsX (choose (1, 100)) (choose (1, 100)) m
        pure (x, runMapSpec z x, y, runMapSpec z y, z, runMapSpec z m, m)
      showAns (s1, run1, s2, run2, v, run3, s3) =
        unlines
          [ "\ns1 = " ++ show s1
          , "s1 Size = " ++ show (sizeForMapSpec s1)
          , "s2 = " ++ show s2
          , "s2 Size = " ++ show (sizeForMapSpec s2)
          , "s1 <> s2 = " ++ show s3
          , "s1<>s2 Size = " ++ show (sizeForMapSpec s3)
          , "v = genFromMapSpec (s1 <> s2) = " ++ show v
          , "runMapSpec v s1 = " ++ show run1
          , "runMapSpec v s2 = " ++ show run2
          , "runMapSpec v (s1 <> s2) = " ++ show run3
          ]
      pr x@(_, a, _, b, _, c, _) = if not (a && b && c) then Just (showAns x) else Nothing
  let trips = [(x, y, m) | x <- xs, y <- ys, Just m <- [consistent x y]]
  ts <- mapM check trips
  pure $ (n, length trips, Maybe.catMaybes (map pr ts))

reportManyMergeMapSpec :: IO ()
reportManyMergeMapSpec = do
  (n, passed, bad) <- generate manyMergeMapSpec
  if null bad
    then putStrLn ("passed " ++ show passed ++ " tests. Spec size " ++ show n)
    else do mapM_ putStrLn bad; error "TestFails"

-- ===================================================================================

data SetSpec era a where
  SetSpec :: (Ord a) => Size -> RelSpec era a -> SetSpec era a
  SetNever :: [String] -> SetSpec era a

instance Show (SetSpec era a) where show = showSetSpec

instance Ord a => Semigroup (SetSpec era a) where
  (<>) = mergeSetSpec

instance (Ord a) => Monoid (SetSpec era a) where
  mempty = SetSpec SzAny RelAny

instance LiftT (SetSpec era t) where
  liftT (SetNever xs) = failT xs
  liftT x = pure x
  dropT (Typed (Left s)) = SetNever s
  dropT (Typed (Right x)) = x

showSetSpec :: SetSpec era a -> String
showSetSpec (SetSpec s r) = sepsP ["SetSpec", show s, show r]
showSetSpec (SetNever _) = "SetNever"

mergeSetSpec :: Ord a => SetSpec era a -> SetSpec era a -> SetSpec era a
mergeSetSpec s1 s2 = case (s1, s2) of
  (SetNever xs, SetNever ys) -> SetNever (xs ++ ys)
  (SetNever xs, _) -> SetNever xs
  (_, SetNever ys) -> SetNever ys
  (SetSpec SzAny RelAny, x) -> x
  (x, SetSpec SzAny RelAny) -> x
  (SetSpec s11 r1, SetSpec s22 r2) -> case r1 <> r2 of
    RelNever xs -> SetNever (["The SetSpec's are inconsistent.", "  " ++ show s1, "  " ++ show s2] ++ xs)
    r3 -> dropT (explain ("While merging\n  " ++ show s1 ++ "\n  " ++ show s2) $ setSpec (s11 <> s22) r3)

-- | Test the size consistency while building a SetSpec
setSpec :: Ord t => Size -> RelSpec era t -> Typed (SetSpec era t)
setSpec sz1 rel = case (sz1 <> sz2) of
  SzNever xs ->
    failT
      ( [ "Creating " ++ show (SetSpec sz1 rel) ++ " fails."
        , "It has size inconsistencies."
        , "  " ++ show rel ++ " has size " ++ show sz2
        , "  " ++ "the expected size is " ++ show sz1
        ]
          ++ xs
      )
  size -> pure (SetSpec size rel)
  where
    sz2 = sizeForRel rel

runSetSpec :: Set a -> SetSpec era a -> Bool
runSetSpec s (SetSpec sz rel) = runSize (Set.size s) sz && runRelSpec s rel
runSetSpec _ (SetNever msgs) = errorMess "runSetSpec applied to SetNever" msgs

sizeForSetSpec :: SetSpec era a -> Size
sizeForSetSpec (SetSpec sz _) = sz
sizeForSetSpec (SetNever _) = SzAny

genSetSpec :: Ord s => [String] -> Gen s -> Rep era s -> Int -> Gen (SetSpec era s)
genSetSpec msgs genS repS size = do
  r <- genRelSpec ("from genSetSpec" : msgs) genS repS size
  pure (SetSpec (SzExact size) r)

genFromSetSpec :: forall era a. [String] -> Gen a -> SetSpec era a -> Gen (Set a)
genFromSetSpec msgs genS (SetSpec sz rp) = do
  n <- genFromSize sz
  genFromRelSpec ("genFromSetSpec" : msgs) genS n rp
genFromSetSpec _ _ (SetNever msgs) = errorMess "genFromSetSpec applied to SetNever" msgs

genSetSpecIsSound :: Gen Property
genSetSpecIsSound = do
  size <- chooseInt (0, 10)
  spec <- genSetSpec msgs (chooseInt (1, 1000)) IntR size
  mp <- genFromSetSpec @TT msgs (choose (1, 10000)) spec
  pure $ counterexample ("spec = " ++ show spec ++ "\nmp = " ++ show mp) (runSetSpec mp spec)
  where
    msgs = ["genSetSpecIsSound"]

manyMergeSetSpec :: Gen (Int, Int, [String])
manyMergeSetSpec = do
  n <- chooseInt (1, 10)
  xs <- vectorOf 50 (genSetSpec [] (choose (1, 100)) IntR n)
  ys <- vectorOf 50 (genSetSpec [] (choose (1, 100)) IntR n)
  let check (x, y, m) = do
        let msize = sizeForSetSpec m
        i <- genFromSize msize
        let wordsX =
              [ "s1<>s2 Size = " ++ show msize
              , "s1<>s2 = " ++ show m
              , "s2 Size = " ++ show (sizeForSetSpec x)
              , "s2 = " ++ show x
              , "s1 Size = " ++ show (sizeForSetSpec y)
              , "s1 = " ++ show y
              , "GenFromSetSpec " ++ show i ++ " n=" ++ show n
              ]
        z <- genFromSetSpec @TT wordsX (choose (1, 100)) m
        pure (x, runSetSpec z x, y, runSetSpec z y, z, runSetSpec z m, m)
      showAns (s1, run1, s2, run2, v, run3, s3) =
        unlines
          [ "\ns1 = " ++ show s1
          , "s1 Size = " ++ show (sizeForSetSpec s1)
          , "s2 = " ++ show s2
          , "s2 Size = " ++ show (sizeForSetSpec s2)
          , "s1 <> s2 = " ++ show s3
          , "s1<>s2 Size = " ++ show (sizeForSetSpec s3)
          , "v = genFromSetSpec (s1 <> s2) = " ++ show v
          , "runSetSpec v s1 = " ++ show run1
          , "runSetSpec v s2 = " ++ show run2
          , "runSetSpec v (s1 <> s2) = " ++ show run3
          ]
      pr x@(_, a, _, b, _, c, _) = if not (a && b && c) then Just (showAns x) else Nothing
  let trips = [(x, y, m) | x <- xs, y <- ys, Just m <- [consistent x y]]
  ts <- mapM check trips
  pure $ (n, length trips, Maybe.catMaybes (map pr ts))

reportManyMergeSetSpec :: IO ()
reportManyMergeSetSpec = do
  (n, passed, bad) <- generate manyMergeSetSpec
  if null bad
    then putStrLn ("passed " ++ show passed ++ " tests. Spec size " ++ show n)
    else do mapM_ putStrLn bad; error "TestFails"

-- =======================================================
-- Specifications for Lists

data ElemSpec era t where
  -- | The set must add up to 'tot', which is any number in the scope of Size
  ElemSum ::
    Adds t =>
    t -> -- The smallest allowed
    Size ->
    ElemSpec era t
  -- | The range must sum upto 'c', which is any number in the scope of Size,
  --   through the projection witnessed by the (Sums t c) class
  ElemProj ::
    Sums x c =>
    c -> -- The smallest allowed
    Rep era c ->
    Size ->
    ElemSpec era x
  -- | The range has exactly these elements
  ElemEqual :: Eq t => Rep era t -> [t] -> ElemSpec era t
  -- In the future we will want to add somethig like:
  -- ElemOrd :: Ord t => Rep era t -> t -> OrdCond -> t -> ElemSpec era tS
  ElemNever :: [String] -> ElemSpec era t
  ElemAny :: ElemSpec era t

instance Show (ElemSpec era a) where
  show = showElemSpec

instance Semigroup (ElemSpec era a) where
  (<>) = mergeElemSpec

instance Monoid (ElemSpec era a) where
  mempty = ElemAny

instance LiftT (ElemSpec era t) where
  liftT (ElemNever xs) = failT xs
  liftT x = pure x
  dropT (Typed (Left s)) = ElemNever s
  dropT (Typed (Right x)) = x

showElemSpec :: ElemSpec era a -> String
showElemSpec (ElemSum small sz) = sepsP ["ElemSum", show small, show sz]
showElemSpec (ElemProj small r sz) = sepsP ["ElemProj", show small, show r, show sz]
showElemSpec (ElemEqual r xs) = sepsP ["ElemEqual", show r, synopsis (ListR r) xs]
showElemSpec (ElemNever _) = "ElemNever"
showElemSpec ElemAny = "ElemAny"

mergeElemSpec :: ElemSpec era a -> ElemSpec era a -> ElemSpec era a
mergeElemSpec (ElemNever xs) (ElemNever ys) = ElemNever (xs ++ ys)
mergeElemSpec (ElemNever xs) _ = ElemNever xs
mergeElemSpec _ (ElemNever ys) = ElemNever ys
mergeElemSpec ElemAny x = x
mergeElemSpec x ElemAny = x
mergeElemSpec a@(ElemEqual r xs) b@(ElemEqual _ ys) =
  if xs == ys
    then ElemEqual r xs
    else
      ElemNever
        [ "The ElemSpec's are inconsistent."
        , "  " ++ show a
        , "  " ++ show b
        , synopsis (ListR r) xs ++ " =/= " ++ synopsis (ListR r) ys
        ]
mergeElemSpec a@(ElemEqual _ xs) b@(ElemSum _ sz) =
  let computed = sumAdds xs
   in if runSize (toI computed) sz
        then a
        else
          ElemNever
            [ "The ElemSpec's are inconsistent."
            , "  " ++ show a
            , "  " ++ show b
            , "The computed sum("
                ++ show computed
                ++ ") is not in the allowed range of the Size("
                ++ show sz
                ++ ")"
            ]
mergeElemSpec b@(ElemSum _ _) a@(ElemEqual _ _) = mergeElemSpec a b
mergeElemSpec a@(ElemSum sm1 sz1) b@(ElemSum sm2 sz2) =
  case sz1 <> sz2 of
    SzNever xs -> ElemNever ((sepsP ["The ElemSpec's are inconsistent.", show a, show b]) : xs)
    sz3 -> ElemSum (min sm1 sm2) sz3
mergeElemSpec a@(ElemProj sm1 r1 sz1) b@(ElemProj sm2 r2 sz2) =
  case testEql r1 r2 of
    Just Refl ->
      case sz1 <> sz2 of
        SzNever xs -> ElemNever ((sepsP ["The ElemSpec's are inconsistent.", show a, show b]) : xs)
        sz3 -> ElemProj (min sm1 sm2) r1 sz3
    Nothing -> ElemNever ["The ElemSpec's are inconsistent.", "  " ++ show a, "  " ++ show b]
mergeElemSpec a b = ElemNever ["The ElemSpec's are inconsistent.", "  " ++ show a, "  " ++ show b]

sizeForElemSpec :: forall a era. ElemSpec era a -> Size
sizeForElemSpec (ElemNever _) = SzAny
sizeForElemSpec ElemAny = SzAny
sizeForElemSpec (ElemEqual _ x) = SzExact (length x)
sizeForElemSpec (ElemSum smallest sz) =
  if toI smallest > 0
    then SzRng 1 (minSize sz `div` toI smallest)
    else SzLeast 1
sizeForElemSpec (ElemProj smallest (_r :: (Rep era c)) sz) =
  if toI smallest > 0
    then SzRng 1 (minSize sz `div` toI smallest)
    else SzLeast 1

runElemSpec :: [a] -> ElemSpec era a -> Bool
runElemSpec xs spec = case spec of
  ElemNever _ -> False -- ErrorMess "ElemNever in runElemSpec" []
  ElemAny -> True
  ElemEqual _ ys -> xs == ys
  ElemSum _ sz -> runSize (toI (sumAdds xs)) sz
  ElemProj _ _ sz -> runSize (toI (projAdds xs)) sz

genElemSpec ::
  forall w c era.
  (Adds w, Sums w c, Era era) =>
  Rep era w ->
  Rep era c ->
  Size ->
  Gen (ElemSpec era w)
genElemSpec repw repc siz = do
  let lo = minSize siz
      hi = maxSize siz
  if lo >= 1
    then
      frequency -- Can't really generate Sums, when size (n) is 0.
        [
          ( 2
          , do
              smallest <- genSmall @w -- Chooses smallest appropriate for type 'w'
              sz <- genBigSize (max 1 (smallest * hi))
              pure (ElemSum (fromI ["genRngSpec " ++ show siz] smallest) sz)
          )
        ,
          ( 2
          , do
              smallest <- genSmall @c
              sz <- genBigSize (max 1 (smallest * hi))
              pure (ElemProj (fromI ["genRngSpec " ++ show siz] smallest) repc sz)
          )
        , (2, ElemEqual repw <$> do n <- genFromSize siz; vectorOf n (genRep repw))
        , (1, pure ElemAny)
        ]
    else
      frequency
        [ (3, ElemEqual repw <$> do n <- genFromSize siz; vectorOf n (genRep repw))
        , (1, pure ElemAny)
        ]

genFromElemSpec ::
  forall era r.
  [String] ->
  Gen r ->
  Int ->
  ElemSpec era r ->
  Gen [r]
genFromElemSpec msgs genr n x = case x of
  (ElemNever xs) -> errorMess "RngNever in genFromElemSpec" xs
  ElemAny -> vectorOf n genr
  (ElemEqual _ xs) -> pure xs
  (ElemSum small sz) -> do
    tot <- genFromIntRange sz
    partition small msgs n (fromI (msg : msgs) tot)
  (ElemProj small _ sz) -> do
    tot <- genFromIntRange sz
    rs <- partition small msgs n (fromI (msg : msgs) tot)
    mapM (genT msgs) rs
  where
    msg = "genFromElemSpec " ++ show n ++ " " ++ show x

manyMergeElemSpec :: Gen (Size, Int, [String])
manyMergeElemSpec = do
  size <- genSize
  xs <- vectorOf 40 (genElemSpec Word64R CoinR size)
  ys <- vectorOf 40 (genElemSpec Word64R CoinR size)
  let check (x, y, m) = do
        let msize = sizeForElemSpec m
        i <- genFromSize msize
        let wordsX =
              [ "s1<>s2 Size = " ++ show msize
              , "s1<>s2 = " ++ show m
              , "s2 Size = " ++ show (sizeForElemSpec x)
              , "s2 = " ++ show x
              , "s1 Size = " ++ show (sizeForElemSpec y)
              , "s1 = " ++ show y
              , "GenFromElemSpec " ++ show i ++ " size=" ++ show size
              ]
        z <- genFromElemSpec @TT wordsX (choose (1, 100)) i m
        pure (x, runElemSpec z x, y, runElemSpec z y, z, runElemSpec z m, m)
      showAns (s1, run1, s2, run2, v, run3, s3) =
        unlines
          [ "\ns1 = " ++ show s1
          , "s1 Size = " ++ show (sizeForElemSpec s1)
          , "s2 = " ++ show s2
          , "s2 Size = " ++ show (sizeForElemSpec s2)
          , "s1 <> s2 = " ++ show s3
          , "s1<>s2 Size = " ++ show (sizeForElemSpec s3)
          , "v = genFromElemSpec (s1 <> s2) = " ++ show v
          , "runElemSpec v s1 = " ++ show run1
          , "runElemSpec v s2 = " ++ show run2
          , "runElemSpec v (s1 <> s2) = " ++ show run3
          ]
      pr x@(_, a, _, b, _, c, _) = if not (a && b && c) then Just (showAns x) else Nothing
  let trips = [(x, y, m) | x <- xs, y <- ys, Just m <- [consistent x y]]
  ts <- mapM check trips
  pure $ (size, length trips, Maybe.catMaybes (map pr ts))

reportManyMergeElemSpec :: IO ()
reportManyMergeElemSpec = do
  (size, passed, bad) <- generate manyMergeElemSpec
  if null bad
    then putStrLn ("passed " ++ show passed ++ " tests. Spec size " ++ show size)
    else do mapM_ putStrLn bad; error "TestFails"

-- ========================================

-- | Specs for lists have two parts, the Size, and the elements
data ListSpec era t where
  ListSpec :: Size -> ElemSpec era t -> ListSpec era t
  ListNever :: [String] -> ListSpec era t

instance Show (ListSpec era a) where
  show = showListSpec

instance Semigroup (ListSpec era a) where
  (<>) = mergeListSpec

instance Monoid (ListSpec era a) where
  mempty = ListSpec SzAny ElemAny

instance LiftT (ListSpec era t) where
  liftT (ListNever xs) = failT xs
  liftT x = pure x
  dropT (Typed (Left s)) = ListNever s
  dropT (Typed (Right x)) = x

showListSpec :: ListSpec era a -> String
showListSpec (ListSpec s xs) = sepsP ["ListSpec", show s, show xs]
showListSpec (ListNever _) = "ListNever"

mergeListSpec :: ListSpec era a -> ListSpec era a -> ListSpec era a
mergeListSpec (ListNever xs) (ListNever ys) = ListNever (xs ++ ys)
mergeListSpec (ListNever xs) (ListSpec _ _) = ListNever xs
mergeListSpec (ListSpec _ _) (ListNever xs) = ListNever xs
mergeListSpec a@(ListSpec s1 e1) b@(ListSpec s2 e2) =
  case e1 <> e2 of
    ElemNever xs ->
      ListNever (["The ListSpec's are inconsistent.", "  " ++ show a, "  " ++ show b] ++ xs)
    e3 -> dropT (explain ("While merging\n  " ++ show a ++ "\n  " ++ show b) $ listSpec (s1 <> s2) e3)

-- | Test the size consistency while building a ListSpec
listSpec :: Size -> ElemSpec era t -> Typed (ListSpec era t)
listSpec sz1 el = case (sz1 <> sz2) of
  SzNever xs ->
    failT
      ( [ "Creating " ++ show (ListSpec sz1 el) ++ " fails."
        , "It has size inconsistencies."
        , "  " ++ show el ++ " has size " ++ show sz2
        , "  " ++ "the expected size is " ++ show sz1
        ]
          ++ xs
      )
  size -> pure (ListSpec size el)
  where
    sz2 = sizeForElemSpec el

sizeForListSpec :: ListSpec era t -> Size
sizeForListSpec (ListSpec sz _) = sz
sizeForListSpec (ListNever _) = SzAny

runListSpec :: [a] -> ListSpec era a -> Bool
runListSpec xs spec = case spec of
  ListNever _ -> False
  ListSpec sx es -> runSize (length xs) sx && runElemSpec xs es

genListSpec ::
  forall w c era.
  (Adds w, Sums w c, Era era) =>
  Rep era w ->
  Rep era c ->
  Size ->
  Gen (ListSpec era w)
genListSpec repw repc size = do
  e <- genElemSpec repw repc size
  pure (ListSpec size e)

genFromListSpec ::
  forall era r.
  [String] ->
  Gen r ->
  ListSpec era r ->
  Gen [r]
genFromListSpec _ _ (ListNever xs) = errorMess "ListNever in genFromListSpec" xs
genFromListSpec msgs genr (ListSpec size e) = do
  n <- genFromSize size
  genFromElemSpec ("genFromListSpec" : msgs) genr n e

-- List and Elem tests

testSoundElemSpec :: Gen Property
testSoundElemSpec = do
  size <- genSize
  spec <- genElemSpec Word64R CoinR size
  n <- genFromSize size
  list <- genFromElemSpec @TT ["testSoundElemSpec " ++ show spec ++ " " ++ show n] (choose (1, 1000)) n spec
  pure $
    counterexample
      ("size=" ++ show size ++ "\nspec=" ++ show spec ++ "\nlist=" ++ synopsis (ListR Word64R) list)
      (runElemSpec list spec)

testSoundListSpec :: Gen Property
testSoundListSpec = do
  size <- genSize
  spec <- genListSpec Word64R CoinR size
  list <- genFromListSpec @TT ["testSoundListSpec"] (choose (1, 1000)) spec
  pure $
    counterexample
      ("spec=" ++ show spec ++ "\nlist=" ++ synopsis (ListR Word64R) list)
      (runListSpec list spec)

manyMergeListSpec :: Gen (Size, Int, [String])
manyMergeListSpec = do
  size <- genSize
  xs <- vectorOf 40 (genListSpec Word64R CoinR size)
  ys <- vectorOf 40 (genListSpec Word64R CoinR size)
  let check (x, y, m) = do
        let msize = sizeForListSpec m
        i <- genFromSize msize
        let wordsX =
              [ "s1<>s2 Size = " ++ show msize
              , "s1<>s2 = " ++ show m
              , "s2 Size = " ++ show (sizeForListSpec x)
              , "s2 = " ++ show x
              , "s1 Size = " ++ show (sizeForListSpec y)
              , "s1 = " ++ show y
              , "GenFromListSpec " ++ show i ++ " size=" ++ show size
              ]
        z <- genFromListSpec @TT wordsX (choose (1, 100)) m
        pure (x, runListSpec z x, y, runListSpec z y, z, runListSpec z m, m)
      showAns (s1, run1, s2, run2, v, run3, s3) =
        unlines
          [ "\ns1 = " ++ show s1
          , "s1 Size = " ++ show (sizeForListSpec s1)
          , "s2 = " ++ show s2
          , "s2 Size = " ++ show (sizeForListSpec s2)
          , "s1 <> s2 = " ++ show s3
          , "s1<>s2 Size = " ++ show (sizeForListSpec s3)
          , "v = genFromListSpec (s1 <> s2) = " ++ show v
          , "runListSpec v s1 = " ++ show run1
          , "runListSpec v s2 = " ++ show run2
          , "runListSpec v (s1 <> s2) = " ++ show run3
          ]
      pr x@(_, a, _, b, _, c, _) = if not (a && b && c) then Just (showAns x) else Nothing
  let trips = [(x, y, m) | x <- xs, y <- ys, Just m <- [consistent x y]]
  ts <- mapM check trips
  pure $ (size, length trips, Maybe.catMaybes (map pr ts))

reportManyMergeListSpec :: IO ()
reportManyMergeListSpec = do
  (size, passed, bad) <- generate manyMergeListSpec
  if null bad
    then putStrLn ("passed " ++ show passed ++ " tests. Spec size " ++ show size)
    else do mapM_ putStrLn bad; error "TestFails"

-- ================================================
-- Synthetic classes used to control the size of
-- things in the tests.

class (Arbitrary t, Adds t) => TestAdd t where
  anyAdds :: Gen t
  pos :: Gen t

instance TestAdd Word64 where
  anyAdds = choose (0, 12)
  pos = choose (1, 12)

instance TestAdd Coin where
  anyAdds = Coin <$> choose (0, 8)
  pos = Coin <$> choose (1, 8)

instance TestAdd Int where
  anyAdds = chooseInt (0, atMostAny)
  pos = chooseInt (1, atMostAny)

-- =============================================
-- Some simple generators tied to TestAdd class

-- | Only the size of the set uses TestAdd
genSet :: Ord t => Int -> Gen t -> Gen (Set t)
genSet n gen = do
  xs <- vectorOf 20 gen
  pure (Set.fromList (take n (List.nub xs)))

testSet :: TestAdd t => Gen (Set t)
testSet = do
  n <- pos @Int
  Set.fromList <$> vectorOf n anyAdds

someSet :: Ord t => Gen t -> Gen (Set t)
someSet g = do
  n <- pos @Int
  Set.fromList <$> vectorOf n g

someMap :: forall era t d. (Ord d, TestAdd t, Era era) => Rep era d -> Gen (Map d t)
someMap r = do
  n <- pos @Int
  rs <- vectorOf n anyAdds
  ds <- vectorOf n (genRep r)
  pure $ Map.fromList (zip ds rs)

-- ===================================
-- Some proto-tests, to be fixed soon

aMap :: Era era => Gen (MapSpec era Int Word64)
aMap = genMapSpec (chooseInt (1, 1000)) IntR Word64R CoinR 4

testm :: Gen (MapSpec TT Int Word64)
testm = do
  a <- aMap @TT
  b <- aMap
  monadTyped (liftT (a <> b))

aList :: Era era => Gen (ListSpec era Word64)
aList = genSize >>= genListSpec Word64R CoinR

testl :: Gen (ListSpec TT Word64)
testl = do
  a <- aList @TT
  b <- aList
  monadTyped (liftT (a <> b))

-- =======================================================================
-- Operations on AddsSpec (defined in Types.hs)

testV :: V era DeltaCoin
testV = (V "x" DeltaCoinR No)

genSumsTo :: Gen (Pred era)
genSumsTo = do
  c <- genOrdCond
  let v = Var testV
  rhs <- (Lit DeltaCoinR . DeltaCoin) <$> choose (-10, 10)
  lhs <- (Lit DeltaCoinR . DeltaCoin) <$> choose (-10, 10)
  elements [SumsTo (DeltaCoin 1) v c [One rhs], SumsTo (DeltaCoin 1) lhs c [One rhs, One v]]

solveSumsTo :: Pred era -> AddsSpec c
solveSumsTo (SumsTo _ (Lit DeltaCoinR n) cond [One (Lit DeltaCoinR m), One (Var (V nam _ _))]) =
  vRight (toI n) cond (toI m) nam
solveSumsTo (SumsTo _ (Var (V nam DeltaCoinR _)) cond [One (Lit DeltaCoinR m)]) =
  vLeft nam cond (toI m)
solveSumsTo x = AddsSpecNever ["solveSumsTo " ++ show x]

condReverse :: Gen Property
condReverse = do
  predicate <- genSumsTo
  let addsSpec = solveSumsTo predicate
  let msgs = ["condFlip", show predicate, show addsSpec]
  n <- genFromAddsSpec msgs addsSpec
  let env = storeVar testV (fromI (show n : msgs) n) emptyEnv
  case runTyped (runPred env predicate) of
    Right x -> pure (counterexample (unlines (show n : msgs)) x)
    Left xs -> errorMess "runTyped in condFlip fails" (xs ++ (show n : msgs))

genAddsSpec :: Gen (AddsSpec c)
genAddsSpec = do
  v <- elements ["x", "y"]
  c <- genOrdCond
  rhs <- choose (-25, 25)
  lhs <- choose (-25, 25)
  elements [vLeft v c rhs, vRight lhs c rhs v]

genNonNegAddsSpec :: Gen (AddsSpec c)
genNonNegAddsSpec = do
  v <- elements ["x", "y"]
  c <- genOrdCond
  lhs <- choose (10, 30)
  rhs <- choose (1, lhs - 1)
  let lhs' = case c of
        LTH -> lhs + 1
        _ -> lhs
  elements [vLeft v c rhs, vRight lhs' c rhs v]

genOrdCond :: Gen OrdCond
genOrdCond = elements [EQL, LTH, LTE, GTH, GTE]

runAddsSpec :: forall c. Adds c => c -> AddsSpec c -> Bool
runAddsSpec c (AddsSpecSize _ size) = runSize (toI c) size
runAddsSpec _ AddsSpecAny = True
runAddsSpec _ (AddsSpecNever _) = False

-- | Not sure how to interpret this? As the possible totals that make the implicit OrdCond True?
sizeForAddsSpec :: AddsSpec c -> Size
sizeForAddsSpec (AddsSpecSize _ s) = s
sizeForAddsSpec AddsSpecAny = SzAny
sizeForAddsSpec (AddsSpecNever xs) = SzNever xs

tryManyAddsSpec :: Gen (AddsSpec Int) -> ([String] -> AddsSpec Int -> Gen Int) -> Gen (Int, [String])
tryManyAddsSpec genSum genFromSum = do
  xs <- vectorOf 25 genSum
  ys <- vectorOf 25 genSum
  let check (x, y, m) = do
        z <- genFromSum ["test tryManyAddsSpec"] m
        pure (x, runAddsSpec z x, y, runAddsSpec z y, z, runAddsSpec z m, m)
      showAns :: (AddsSpec c, Bool, AddsSpec c, Bool, Int, Bool, AddsSpec c) -> String
      showAns (s1, run1, s2, run2, v, run3, s3) =
        unlines
          [ "s1 = " ++ show s1
          , "s2 = " ++ show s2
          , "s1 <> s2 = " ++ show s3
          , "v = genFromAdsSpec (s1 <> s2) = " ++ show v
          , "runAddsSpec s1 v = " ++ show run1
          , "runAddsSpec s2 v = " ++ show run2
          , "runAddsSpec (s1 <> s2) v = " ++ show run3
          ]
      pr x@(_, a, _, b, _, c, _) = if not (a && b && c) then Just (showAns x) else Nothing
  let trips = [(x, y, m) | x <- xs, y <- ys, Just m <- [consistent x y]]
  ts <- mapM check trips
  pure $ (length trips, Maybe.catMaybes (map pr ts))

reportManyAddsSpec :: IO ()
reportManyAddsSpec = do
  (passed, bad) <- generate (tryManyAddsSpec genAddsSpec genFromAddsSpec)
  if null bad
    then putStrLn ("passed " ++ show passed ++ " tests.")
    else do mapM_ putStrLn bad; error "TestFails"

reportManyNonNegAddsSpec :: IO ()
reportManyNonNegAddsSpec = do
  (passed, bad) <- generate (tryManyAddsSpec genNonNegAddsSpec genFromNonNegAddsSpec)
  if null bad
    then putStrLn ("passed " ++ show passed ++ " tests.")
    else do mapM_ putStrLn bad; error "TestFails"

testSoundNonNegAddsSpec :: Gen Property
testSoundNonNegAddsSpec = do
  spec <- genNonNegAddsSpec @Int
  c <- genFromNonNegAddsSpec ["testSoundAddsSpec " ++ show spec] spec
  pure $
    counterexample
      ("AddsSpec=" ++ show spec ++ "\ngenerated value " ++ show c)
      (runAddsSpec c spec)

testSoundAddsSpec :: Gen Property
testSoundAddsSpec = do
  spec <- genAddsSpec @DeltaCoin
  c <- genFromAddsSpec ["testSoundAddsSpec " ++ show spec] spec
  pure $
    counterexample
      ("AddsSpec=" ++ show spec ++ "\ngenerated value " ++ show c)
      (runAddsSpec (fromI ["testSoundAddsSpec"] c) spec)

-- ========================================================

main :: IO ()
main =
  defaultMain $
    testGroup
      "Spec tests"
      [ testProperty "reversing OrdCond" condReverse
      , testGroup
          "Size test"
          [ testProperty "test Size sound" testSoundSize
          , testProperty "test genFromSize is non-negative" testNonNegSize
          , testProperty "test merging Size" testMergeSize
          ]
      , testGroup
          "RelSpec tests"
          [ testProperty "we generate consistent RelSpecs" testConsistentRel
          , testProperty "test RelSpec sound" testSoundRelSpec
          , testProperty "test mergeRelSpec" testMergeRelSpec
          , testProperty "test More consistent RelSpec" reportManyMergeRelSpec
          ]
      , testGroup
          "RngSpec tests"
          [ testProperty "we generate consistent RngSpec" testConsistentRng
          , testProperty "test RngSpec sound" testSoundRngSpec
          , testProperty "test mergeRngSpec" testMergeRngSpec
          , testProperty "test More consistent RngSpec" reportManyMergeRngSpec
          ]
      , testGroup
          "MapSpec tests"
          [ testProperty "test MapSpec sound" genMapSpecIsSound
          , testProperty "test More consistent MapSpec" reportManyMergeMapSpec
          ]
      , testGroup
          "SetSpec tests"
          [ testProperty "test SetSpec sound" genSetSpecIsSound
          , testProperty "test More consistent SetSpec" reportManyMergeSetSpec
          ]
      , testGroup
          "ListSpec tests"
          [ testProperty "test ElemSpec sound" testSoundElemSpec
          , testProperty "test consistent ElemSpec" reportManyMergeElemSpec
          , testProperty "test ListSpec sound" testSoundListSpec
          , testProperty "test consistent ListSpec" reportManyMergeListSpec
          ]
      , testGroup
          "AddsSpec tests"
          [ testProperty "test Sound MergeAddsSpec" reportManyAddsSpec
          , testProperty "test Sound non-negative MergeAddsSpec" reportManyNonNegAddsSpec
          , testProperty "test Sound non-negative AddsSpec" testSoundNonNegAddsSpec
          , testProperty "test Sound any AddsSpec" testSoundAddsSpec
          ]
      ]

-- :main --quickcheck-replay=740521

{-
Notes for making a class

class Specification spec t where
  type Count Size = ()
       Count RelSpec = Int
       Count RngSpec = Int
       Count MapSpec = Int
       Count SetSpec = Int
       Count ElemSpec = Size
       Count ListSpec = Size
       Count AddsSpec = ()
  runS :: t -> spec -> Bool
  genS :: Count spec -> Gen spec
  sizeForS :: spec -> Size
  genFromS :: Int -> spec -> t  -- Some genFromS can be written in the instances to ignore the Int

runSize :: Int -> Size -> Bool
genSize :: Gen Size  --- isomprphic to () -> Gen Size
genFromSize :: Size -> Gen Int

runRelSpec :: Ord t => Set t -> RelSpec era t -> Bool
genRelSpec :: Ord dom => [String] -> Gen dom -> Rep era dom -> Int -> Gen (RelSpec era dom)
genFromRelSpec :: forall era t. Ord t => [String] -> Gen t -> Int -> RelSpec era t -> Gen (Set t)
sizeForRel :: RelSpec era dom -> Size

runRngSpec :: [r] -> RngSpec era r -> Bool
genRngSpec :: Gen w -> Rep era w -> Rep era c -> Int -> Gen (RngSpec era w)
genFromRngSpec :: forall era r. [String] -> Gen r -> Int -> RngSpec era r -> Gen [r]

runMapSpec :: Ord d => Map d r -> MapSpec era d r -> Bool
genMapSpec :: Gen dom -> Rep era dom -> Rep era w -> Rep era c -> Int -> Gen (MapSpec era dom w)
genFromMapSpec :: V era (Map dom w) -> [String] -> Gen dom -> Gen w -> MapSpec era dom w -> Gen (Map dom w)
sizeForMapSpec :: MapSpec era d r -> Size

runSetSpec :: Set a -> SetSpec era a -> Bool
genSetSpec :: Ord s => [String] -> Gen s -> Rep era s -> Int -> Gen (SetSpec era s)
genFromSetSpec :: forall era a. [String] -> Gen a -> SetSpec era a -> Gen (Set a)
sizeForSetSpec :: SetSpec era a -> Size

runElemSpec :: [a] -> ElemSpec era a -> Bool
genElemSpec :: Rep era w -> Rep era c -> Size -> Gen (ElemSpec era w)
genFromElemSpec :: [String] -> Gen r -> Int -> ElemSpec era r -> Gen [r]
sizeForElemSpec :: ElemSpec era a -> Size

runListSpec :: [a] -> ListSpec era a -> Bool
genListSpec :: Rep era w -> Rep era c -> Size -> Gen (ListSpec era w)
genFromListSpec :: [String] -> Gen r -> ListSpec era r -> Gen [r]
sizeForListSpec :: ListSpec era t -> Size

runAddsSpec :: forall c. Adds c => c -> AddsSpec c -> Bool
genAddsSpec :: Gen (AddsSpec c)
genFromAddsSpec :: [String] -> AddsSpec c -> Gen Int
sizeForAddsSpec :: AddsSpec c -> Size
-}
