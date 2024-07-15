{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

-- |
-- SPDX-License-Identifier: BSD-3-Clause
--
-- Descriptions of the orientation and offset by
-- which a structure should be placed.
module Swarm.Game.Scenario.Topography.Placement where

import Data.List.NonEmpty qualified as NE
import Data.Text (Text)
import Data.Yaml as Y
import GHC.Generics (Generic)
import Swarm.Game.Location
import Swarm.Game.Scenario.Topography.Area
import Swarm.Game.Scenario.Topography.Grid
import Swarm.Language.Syntax.Direction (AbsoluteDir (..))

newtype StructureName = StructureName Text
  deriving (Eq, Ord, Show, Generic, FromJSON, ToJSON)

getStructureName :: StructureName -> Text
getStructureName (StructureName sn) = sn

-- | Orientation transformations are applied before translation.
data Orientation = Orientation
  { up :: AbsoluteDir
  -- ^ e.g. For "East", rotates 270 degrees.
  , flipped :: Bool
  -- ^ vertical flip, applied before rotation
  }
  deriving (Eq, Show)

instance FromJSON Orientation where
  parseJSON = withObject "structure orientation" $ \v -> do
    up <- v .:? "up" .!= DNorth
    flipped <- v .:? "flip" .!= False
    pure Orientation {..}

defaultOrientation :: Orientation
defaultOrientation = Orientation DNorth False

-- | This is the point-wise equivalent of "applyOrientationTransform"
reorientLandmark :: Orientation -> AreaDimensions -> Location -> Location
reorientLandmark (Orientation upDir shouldFlip) (AreaDimensions width height) =
  rotational . flipping
 where
  transposeLoc (Location x y) = Location (-y) (-x)
  flipV (Location x y) = Location x $ -(height - 1) - y
  flipH (Location x y) = Location (width - 1 - x) y
  flipping = if shouldFlip then flipV else id
  rotational = case upDir of
    DNorth -> id
    DSouth -> flipH . flipV
    DEast -> transposeLoc . flipV
    DWest -> transposeLoc . flipH

-- | affine transformation
applyOrientationTransform :: Orientation -> Grid a -> Grid a
applyOrientationTransform (Orientation upDir shouldFlip) =
  mapRows f
 where
  f = rotational . flipping
  flipV = NE.reverse
  flipping = if shouldFlip then flipV else id
  rotational = case upDir of
    DNorth -> id
    DSouth -> NE.transpose . flipV . NE.transpose . flipV
    DEast -> NE.transpose . flipV
    DWest -> flipV . NE.transpose

data Pose = Pose
  { offset :: Location
  , orient :: Orientation
  }
  deriving (Eq, Show)

data Placement = Placement
  { src :: StructureName
  , structurePose :: Pose
  }
  deriving (Eq, Show)

instance FromJSON Placement where
  parseJSON = withObject "structure placement" $ \v -> do
    src <- v .: "src"
    offset <- v .:? "offset" .!= origin
    orient <- v .:? "orient" .!= defaultOrientation
    let structurePose = Pose offset orient
    pure Placement {..}
