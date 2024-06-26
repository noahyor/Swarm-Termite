{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

-- |
-- SPDX-License-Identifier: BSD-3-Clause
-- Description: Goals of scenario
module Swarm.Game.Scenario.Objective (
  -- * Scenario objectives
  PrerequisiteConfig (..),
  Objective,
  objectiveGoal,
  objectiveTeaser,
  objectiveCondition,
  objectiveId,
  objectiveOptional,
  objectivePrerequisite,
  objectiveHidden,
  objectiveAchievement,
  Announcement (..),

  -- * Objective completion tracking
  ObjectiveCompletion,
  initCompletion,
  completedIDs,
  incompleteObjectives,
  completedObjectives,
  unwinnableObjectives,
  allObjectives,
  addCompleted,
  addUnwinnable,
  addIncomplete,
  extractIncomplete,
)
where

import Control.Applicative ((<|>))
import Control.Lens hiding (from, (<.>))
import Data.Aeson
import Data.Set qualified as Set
import Data.Text (Text)
import GHC.Generics (Generic)
import Servant.Docs (ToSample)
import Servant.Docs qualified as SD
import Swarm.Game.Achievement.Definitions qualified as AD
import Swarm.Game.Scenario.Objective.Logic as L
import Swarm.Language.JSON ()
import Swarm.Language.Syntax (Syntax, TSyntax)
import Swarm.Language.Text.Markdown qualified as Markdown
import Swarm.Util.Lens (concatFold, makeLensesExcluding, makeLensesNoSigs)

------------------------------------------------------------
-- Scenario objectives
------------------------------------------------------------

data PrerequisiteConfig = PrerequisiteConfig
  { previewable :: Bool
  -- ^ Typically, only the currently "active" objectives are
  -- displayed to the user in the Goals dialog. An objective
  -- is "active" if all of its prerequisites are met.
  --
  -- However, some objectives may be "high-level", in that they may
  -- explain the broader intention behind potentially multiple
  -- prerequisites.
  --
  -- Set this option to 'True' to display this goal in the "upcoming" section even
  -- if the objective has currently unmet prerequisites.
  , logic :: Prerequisite ObjectiveLabel
  -- ^ Boolean expression of dependencies upon other objectives. Variables in this expression
  -- are the "id"s of other objectives, and become "true" if the corresponding objective is completed.
  -- The "condition" of the objective at hand shall not be evaluated until its
  -- prerequisite expression evaluates as 'True'.
  --
  -- Note that the achievement of these objective dependencies is
  -- persistent; once achieved, they still count even if their "condition"
  -- might not still hold. The condition is never re-evaluated once true.
  }
  deriving (Eq, Show, Generic, ToJSON)

instance FromJSON PrerequisiteConfig where
  -- Parsing JSON/YAML 'PrerequisiteConfig' has a shorthand option
  -- in which the boolean expression can be written directly,
  -- bypassing the "logic" key.
  -- Furthermore, an "Id" in a boolean expressions can be written
  -- as a bare string without needing the "id" key.
  parseJSON val = preLogic val <|> preObject val
   where
    preObject = withObject "prerequisite" $ \v -> do
      previewable <- v .:? "previewable" .!= False
      logic <- v .: "logic"
      pure PrerequisiteConfig {..}
    preLogic = fmap (PrerequisiteConfig False) . parseJSON

-- | An objective is a condition to be achieved by a player in a
--   scenario.
data Objective = Objective
  { _objectiveGoal :: Markdown.Document Syntax
  , _objectiveTeaser :: Maybe Text
  , _objectiveCondition :: TSyntax
  , _objectiveId :: Maybe ObjectiveLabel
  , _objectiveOptional :: Bool
  , _objectivePrerequisite :: Maybe PrerequisiteConfig
  , _objectiveHidden :: Bool
  , _objectiveAchievement :: Maybe AD.AchievementInfo
  }
  deriving (Eq, Show, Generic, ToJSON)

makeLensesNoSigs ''Objective

instance ToSample Objective where
  toSamples _ = SD.noSamples

-- | An explanation of the goal of the objective, shown to the player
--   during play.  It is represented as a list of paragraphs.
objectiveGoal :: Lens' Objective (Markdown.Document Syntax)

-- | A very short (3-5 words) description of the goal for
-- displaying on the left side of the Objectives modal.
objectiveTeaser :: Lens' Objective (Maybe Text)

-- | A winning condition for the objective, expressed as a
--   program of type @cmd bool@.  By default, this program will be
--   run to completion every tick (the usual limits on the number
--   of CESK steps per tick do not apply).
objectiveCondition :: Lens' Objective TSyntax

-- | Optional name by which this objective may be referenced
-- as a prerequisite for other objectives.
objectiveId :: Lens' Objective (Maybe Text)

-- | Indicates whether the objective is not required in order
-- to "win" the scenario. Useful for (potentially hidden) achievements.
-- If the field is not supplied, it defaults to False (i.e. the
-- objective is mandatory to "win").
objectiveOptional :: Lens' Objective Bool

-- | Dependencies upon other objectives
objectivePrerequisite :: Lens' Objective (Maybe PrerequisiteConfig)

-- | Whether the goal is displayed in the UI before completion.
-- The goal will always be revealed after it is completed.
--
-- This attribute often goes along with an Achievement.
objectiveHidden :: Lens' Objective Bool

-- | An optional achievement that is to be registered globally
-- when this objective is completed.
objectiveAchievement :: Lens' Objective (Maybe AD.AchievementInfo)

instance FromJSON Objective where
  parseJSON = withObject "objective" $ \v -> do
    _objectiveGoal <- v .:? "goal" .!= mempty
    _objectiveTeaser <- v .:? "teaser"
    _objectiveCondition <- v .: "condition"
    _objectiveId <- v .:? "id"
    _objectiveOptional <- v .:? "optional" .!= False
    _objectivePrerequisite <- v .:? "prerequisite"
    _objectiveHidden <- v .:? "hidden" .!= False
    _objectiveAchievement <- v .:? "achievement"
    pure Objective {..}

-- | TODO: #1044 Could also add an "ObjectiveFailed" constructor...
newtype Announcement
  = ObjectiveCompleted Objective
  deriving (Show, Generic, ToJSON)

------------------------------------------------------------
-- Completion tracking
------------------------------------------------------------

-- | Gather together lists of objectives that are incomplete,
--   complete, or unwinnable.  This type is not exported from this
--   module.
data CompletionBuckets = CompletionBuckets
  { _incomplete :: [Objective]
  , _completed :: [Objective]
  , _unwinnable :: [Objective]
  }
  deriving (Show, Generic, FromJSON, ToJSON)

-- Note we derive these lenses for `CompletionBuckets` but we do NOT
-- export them; they are used only internally to this module.  In
-- fact, the `CompletionBuckets` type itself is not exported.
makeLensesNoSigs ''CompletionBuckets

-- | The incomplete objectives in a 'CompletionBuckets' record.
incomplete :: Lens' CompletionBuckets [Objective]

-- | The completed objectives in a 'CompletionBuckets' record.
completed :: Lens' CompletionBuckets [Objective]

-- | The unwinnable objectives in a 'CompletionBuckets' record.
unwinnable :: Lens' CompletionBuckets [Objective]

-- | A record to keep track of the completion status of all a
--   scenario's objectives.  We do not export the constructor or
--   record field labels of this type in order to ensure that its
--   internal invariants cannot be violated.
data ObjectiveCompletion = ObjectiveCompletion
  { _completionBuckets :: CompletionBuckets
  -- ^ This is the authoritative "completion status"
  -- for all objectives.
  -- Note that there is a separate Set to store the
  -- completion status of prerequisite objectives, which
  -- must be carefully kept in sync with this.
  -- Those prerequisite objectives are required to have
  -- labels, but other objectives are not.
  -- Therefore only prerequisites exist in the completion
  -- map keyed by label.
  , _completedIDs :: Set.Set ObjectiveLabel
  }
  deriving (Show, Generic, FromJSON, ToJSON)

makeLensesFor [("_completedIDs", "internalCompletedIDs")] ''ObjectiveCompletion
makeLensesExcluding ['_completedIDs] ''ObjectiveCompletion

-- | Initialize an objective completion tracking record from a list of
--   (initially incomplete) objectives.
initCompletion :: [Objective] -> ObjectiveCompletion
initCompletion objs = ObjectiveCompletion (CompletionBuckets objs [] []) mempty

-- | A lens onto the 'CompletionBuckets' member of an
--   'ObjectiveCompletion' record.  This lens is not exported.
completionBuckets :: Lens' ObjectiveCompletion CompletionBuckets

-- | A 'Getter' allowing one to read the set of completed objective
--   IDs for a given scenario.  Note that this is a 'Getter', not a
--   'Lens', to allow for read-only access without the possibility of
--   violating the internal invariants of 'ObjectiveCompletion'.
completedIDs :: Getter ObjectiveCompletion (Set.Set ObjectiveLabel)
completedIDs = to _completedIDs

-- | A 'Fold' giving read-only access to all the incomplete objectives
--   tracked by an 'ObjectiveCompletion' record.  Note that 'Fold' is
--   like a read-only 'Traversal', that is, it has multiple targets
--   but allows only reading them, not updating.  In other words
--   'Fold' is to 'Traversal' as 'Getter' is to 'Lens'.
--
--   To get an actual list of objectives, use the '(^..)' operator, as
--   in @objCompl ^.. incompleteObjectives@, where @objCompl ::
--   ObjectiveCompletion@.
incompleteObjectives :: Fold ObjectiveCompletion Objective
incompleteObjectives = completionBuckets . folding _incomplete

-- | A 'Fold' giving read-only access to all the completed objectives
--   tracked by an 'ObjectiveCompletion' record.  See the
--   documentation for 'incompleteObjectives' for more about 'Fold'.
completedObjectives :: Fold ObjectiveCompletion Objective
completedObjectives = completionBuckets . folding _completed

-- | A 'Fold' giving read-only access to all the unwinnable objectives
--   tracked by an 'ObjectiveCompletion' record.  See the
--   documentation for 'incompleteObjectives' for more about 'Fold'.
unwinnableObjectives :: Fold ObjectiveCompletion Objective
unwinnableObjectives = completionBuckets . folding _unwinnable

-- | A 'Fold' over /all/ objectives (whether incomplete, complete, or
--   unwinnable) tracked by an 'ObjectiveCompletion' record. See the
--   documentation for 'incompleteObjectives' for more about 'Fold'.
allObjectives :: Fold ObjectiveCompletion Objective
allObjectives = incompleteObjectives `concatFold` completedObjectives `concatFold` unwinnableObjectives

-- | Add a completed objective to an 'ObjectiveCompletion' record,
--   being careful to maintain its internal invariants.
addCompleted :: Objective -> ObjectiveCompletion -> ObjectiveCompletion
addCompleted obj =
  (completionBuckets . completed %~ (obj :))
    . (internalCompletedIDs %~ maybe id Set.insert (obj ^. objectiveId))

-- | Add an unwinnable objective to an 'ObjectiveCompletion' record,
--   being careful to maintain its internal invariants.
addUnwinnable :: Objective -> ObjectiveCompletion -> ObjectiveCompletion
addUnwinnable obj = completionBuckets . unwinnable %~ (obj :)

-- | Add an incomplete objective to an 'ObjectiveCompletion' record,
--   being careful to maintain its internal invariants.
addIncomplete :: Objective -> ObjectiveCompletion -> ObjectiveCompletion
addIncomplete obj = completionBuckets . incomplete %~ (obj :)

-- | Returns the 'ObjectiveCompletion' with the incomplete goals
--   extracted to a separate tuple member.  This is intended to be
--   used as input to a fold.
extractIncomplete :: ObjectiveCompletion -> (ObjectiveCompletion, [Objective])
extractIncomplete oc =
  (withoutIncomplete, incompleteGoals)
 where
  incompleteGoals = oc ^. completionBuckets . incomplete
  withoutIncomplete = oc & completionBuckets . incomplete .~ []
