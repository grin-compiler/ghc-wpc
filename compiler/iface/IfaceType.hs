{-
(c) The University of Glasgow 2006
(c) The GRASP/AQUA Project, Glasgow University, 1993-1998


This module defines interface types and binders
-}

{-# LANGUAGE CPP, FlexibleInstances, BangPatterns #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE LambdaCase #-}
    -- FlexibleInstances for Binary (DefMethSpec IfaceType)

module IfaceType (
        IfExtName, IfLclName,

        IfaceType(..), IfacePredType, IfaceKind, IfaceCoercion(..),
        IfaceMCoercion(..),
        IfaceUnivCoProv(..),
        IfaceTyCon(..), IfaceTyConInfo(..), IfaceTyConSort(..),
        IfaceTyLit(..), IfaceAppArgs(..),
        IfaceContext, IfaceBndr(..), IfaceOneShot(..), IfaceLamBndr,
        IfaceTvBndr, IfaceIdBndr, IfaceTyConBinder,
        IfaceForAllBndr, ArgFlag(..), AnonArgFlag(..),
        ForallVisFlag(..), ShowForAllFlag(..),
        mkIfaceForAllTvBndr,
        mkIfaceTyConKind,

        ifForAllBndrVar, ifForAllBndrName, ifaceBndrName,
        ifTyConBinderVar, ifTyConBinderName,

        -- Equality testing
        isIfaceLiftedTypeKind,

        -- Conversion from IfaceAppArgs to IfaceTypes/ArgFlags
        appArgsIfaceTypes, appArgsIfaceTypesArgFlags,

        -- Printing
        SuppressBndrSig(..),
        UseBndrParens(..),
        pprIfaceType, pprParendIfaceType, pprPrecIfaceType,
        pprIfaceContext, pprIfaceContextArr,
        pprIfaceIdBndr, pprIfaceLamBndr, pprIfaceTvBndr, pprIfaceTyConBinders,
        pprIfaceBndrs, pprIfaceAppArgs, pprParendIfaceAppArgs,
        pprIfaceForAllPart, pprIfaceForAllPartMust, pprIfaceForAll,
        pprIfaceSigmaType, pprIfaceTyLit,
        pprIfaceCoercion, pprParendIfaceCoercion,
        splitIfaceSigmaTy, pprIfaceTypeApp, pprUserIfaceForAll,
        pprIfaceCoTcApp, pprTyTcApp, pprIfacePrefixApp,
        isIfaceTauType,

        suppressIfaceInvisibles,
        stripIfaceInvisVars,
        stripInvisArgs,

        mkIfaceTySubst, substIfaceTyVar, substIfaceAppArgs, inDomIfaceTySubst
    ) where

#include "HsVersions.h"

import GhcPrelude

import {-# SOURCE #-} TysWiredIn ( coercibleTyCon, heqTyCon
                                 , liftedRepDataConTyCon, tupleTyConName )
import {-# SOURCE #-} Type       ( isRuntimeRepTy )

import DynFlags
import TyCon hiding ( pprPromotionQuote )
import CoAxiom
import Var
import PrelNames
import Name
import BasicTypes
import Binary
import Outputable
import FastString
import FastStringEnv
import Util

import Data.Maybe( isJust )
import qualified Data.Semigroup as Semi
import Control.DeepSeq

{-
************************************************************************
*                                                                      *
                Local (nested) binders
*                                                                      *
************************************************************************
-}

type IfLclName = FastString     -- A local name in iface syntax

type IfExtName = Name   -- An External or WiredIn Name can appear in IfaceSyn
                        -- (However Internal or System Names never should)

data IfaceBndr          -- Local (non-top-level) binders
  = IfaceIdBndr {-# UNPACK #-} !IfaceIdBndr
  | IfaceTvBndr {-# UNPACK #-} !IfaceTvBndr

type IfaceIdBndr  = (IfLclName, IfaceType)
type IfaceTvBndr  = (IfLclName, IfaceKind)

ifaceTvBndrName :: IfaceTvBndr -> IfLclName
ifaceTvBndrName (n,_) = n

ifaceIdBndrName :: IfaceIdBndr -> IfLclName
ifaceIdBndrName (n,_) = n

ifaceBndrName :: IfaceBndr -> IfLclName
ifaceBndrName (IfaceTvBndr bndr) = ifaceTvBndrName bndr
ifaceBndrName (IfaceIdBndr bndr) = ifaceIdBndrName bndr

ifaceBndrType :: IfaceBndr -> IfaceType
ifaceBndrType (IfaceIdBndr (_, t)) = t
ifaceBndrType (IfaceTvBndr (_, t)) = t

type IfaceLamBndr = (IfaceBndr, IfaceOneShot)

data IfaceOneShot    -- See Note [Preserve OneShotInfo] in CoreTicy
  = IfaceNoOneShot   -- and Note [The oneShot function] in MkId
  | IfaceOneShot


{-
%************************************************************************
%*                                                                      *
                IfaceType
%*                                                                      *
%************************************************************************
-}

-------------------------------
type IfaceKind     = IfaceType

-- | A kind of universal type, used for types and kinds.
--
-- Any time a 'Type' is pretty-printed, it is first converted to an 'IfaceType'
-- before being printed. See Note [Pretty printing via IfaceSyn] in PprTyThing
data IfaceType
  = IfaceFreeTyVar TyVar                -- See Note [Free tyvars in IfaceType]
  | IfaceTyVar     IfLclName            -- Type/coercion variable only, not tycon
  | IfaceLitTy     IfaceTyLit
  | IfaceAppTy     IfaceType IfaceAppArgs
                             -- See Note [Suppressing invisible arguments] for
                             -- an explanation of why the second field isn't
                             -- IfaceType, analogous to AppTy.
  | IfaceFunTy     AnonArgFlag IfaceType IfaceType
  | IfaceForAllTy  IfaceForAllBndr IfaceType
  | IfaceTyConApp  IfaceTyCon IfaceAppArgs  -- Not necessarily saturated
                                            -- Includes newtypes, synonyms, tuples
  | IfaceCastTy     IfaceType IfaceCoercion
  | IfaceCoercionTy IfaceCoercion

  | IfaceTupleTy                  -- Saturated tuples (unsaturated ones use IfaceTyConApp)
       TupleSort                  -- What sort of tuple?
       PromotionFlag                 -- A bit like IfaceTyCon
       IfaceAppArgs               -- arity = length args
          -- For promoted data cons, the kind args are omitted

type IfacePredType = IfaceType
type IfaceContext = [IfacePredType]

data IfaceTyLit
  = IfaceNumTyLit Integer
  | IfaceStrTyLit FastString
  deriving (Eq)

type IfaceTyConBinder = VarBndr IfaceBndr TyConBndrVis
type IfaceForAllBndr  = VarBndr IfaceBndr ArgFlag

-- | Make an 'IfaceForAllBndr' from an 'IfaceTvBndr'.
mkIfaceForAllTvBndr :: ArgFlag -> IfaceTvBndr -> IfaceForAllBndr
mkIfaceForAllTvBndr vis var = Bndr (IfaceTvBndr var) vis

-- | Build the 'tyConKind' from the binders and the result kind.
-- Keep in sync with 'mkTyConKind' in types/TyCon.
mkIfaceTyConKind :: [IfaceTyConBinder] -> IfaceKind -> IfaceKind
mkIfaceTyConKind bndrs res_kind = foldr mk res_kind bndrs
  where
    mk :: IfaceTyConBinder -> IfaceKind -> IfaceKind
    mk (Bndr tv (AnonTCB af))   k = IfaceFunTy af (ifaceBndrType tv) k
    mk (Bndr tv (NamedTCB vis)) k = IfaceForAllTy (Bndr tv vis) k

-- | Stores the arguments in a type application as a list.
-- See @Note [Suppressing invisible arguments]@.
data IfaceAppArgs
  = IA_Nil
  | IA_Arg IfaceType    -- The type argument

           ArgFlag      -- The argument's visibility. We store this here so
                        -- that we can:
                        --
                        -- 1. Avoid pretty-printing invisible (i.e., specified
                        --    or inferred) arguments when
                        --    -fprint-explicit-kinds isn't enabled, or
                        -- 2. When -fprint-explicit-kinds *is*, enabled, print
                        --    specified arguments in @(...) and inferred
                        --    arguments in @{...}.

           IfaceAppArgs -- The rest of the arguments

instance Semi.Semigroup IfaceAppArgs where
  IA_Nil <> xs              = xs
  IA_Arg ty argf rest <> xs = IA_Arg ty argf (rest Semi.<> xs)

instance Monoid IfaceAppArgs where
  mempty = IA_Nil
  mappend = (Semi.<>)

-- Encodes type constructors, kind constructors,
-- coercion constructors, the lot.
-- We have to tag them in order to pretty print them
-- properly.
data IfaceTyCon = IfaceTyCon { ifaceTyConName :: IfExtName
                             , ifaceTyConInfo :: IfaceTyConInfo }
    deriving (Eq)

-- | The various types of TyCons which have special, built-in syntax.
data IfaceTyConSort = IfaceNormalTyCon          -- ^ a regular tycon

                    | IfaceTupleTyCon !Arity !TupleSort
                      -- ^ e.g. @(a, b, c)@ or @(#a, b, c#)@.
                      -- The arity is the tuple width, not the tycon arity
                      -- (which is twice the width in the case of unboxed
                      -- tuples).

                    | IfaceSumTyCon !Arity
                      -- ^ e.g. @(a | b | c)@

                    | IfaceEqualityTyCon
                      -- ^ A heterogeneous equality TyCon
                      --   (i.e. eqPrimTyCon, eqReprPrimTyCon, heqTyCon)
                      -- that is actually being applied to two types
                      -- of the same kind.  This affects pretty-printing
                      -- only: see Note [Equality predicates in IfaceType]
                    deriving (Eq)

{- Note [Free tyvars in IfaceType]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Nowadays (since Nov 16, 2016) we pretty-print a Type by converting to
an IfaceType and pretty printing that.  This eliminates a lot of
pretty-print duplication, and it matches what we do with pretty-
printing TyThings. See Note [Pretty printing via IfaceSyn] in PprTyThing.

It works fine for closed types, but when printing debug traces (e.g.
when using -ddump-tc-trace) we print a lot of /open/ types.  These
types are full of TcTyVars, and it's absolutely crucial to print them
in their full glory, with their unique, TcTyVarDetails etc.

So we simply embed a TyVar in IfaceType with the IfaceFreeTyVar constructor.
Note that:

* We never expect to serialise an IfaceFreeTyVar into an interface file, nor
  to deserialise one.  IfaceFreeTyVar is used only in the "convert to IfaceType
  and then pretty-print" pipeline.

We do the same for covars, naturally.

Note [Equality predicates in IfaceType]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
GHC has several varieties of type equality (see Note [The equality types story]
in TysPrim for details).  In an effort to avoid confusing users, we suppress
the differences during pretty printing unless certain flags are enabled.
Here is how each equality predicate* is printed in homogeneous and
heterogeneous contexts, depending on which combination of the
-fprint-explicit-kinds and -fprint-equality-relations flags is used:

--------------------------------------------------------------------------------------------
|         Predicate             |        Neither flag        |    -fprint-explicit-kinds   |
|-------------------------------|----------------------------|-----------------------------|
| a ~ b         (homogeneous)   |        a ~ b               | (a :: Type) ~  (b :: Type)  |
| a ~~ b,       homogeneously   |        a ~ b               | (a :: Type) ~  (b :: Type)  |
| a ~~ b,       heterogeneously |        a ~~ c              | (a :: Type) ~~ (c :: k)     |
| a ~# b,       homogeneously   |        a ~ b               | (a :: Type) ~  (b :: Type)  |
| a ~# b,       heterogeneously |        a ~~ c              | (a :: Type) ~~ (c :: k)     |
| Coercible a b (homogeneous)   |        Coercible a b       | Coercible @Type a b         |
| a ~R# b,      homogeneously   |        Coercible a b       | Coercible @Type a b         |
| a ~R# b,      heterogeneously |        a ~R# b             | (a :: Type) ~R# (c :: k)    |
|-------------------------------|----------------------------|-----------------------------|
|         Predicate             | -fprint-equality-relations |          Both flags         |
|-------------------------------|----------------------------|-----------------------------|
| a ~ b         (homogeneous)   |        a ~  b              | (a :: Type) ~  (b :: Type)  |
| a ~~ b,       homogeneously   |        a ~~ b              | (a :: Type) ~~ (b :: Type)  |
| a ~~ b,       heterogeneously |        a ~~ c              | (a :: Type) ~~ (c :: k)     |
| a ~# b,       homogeneously   |        a ~# b              | (a :: Type) ~# (b :: Type)  |
| a ~# b,       heterogeneously |        a ~# c              | (a :: Type) ~# (c :: k)     |
| Coercible a b (homogeneous)   |        Coercible a b       | Coercible @Type a b         |
| a ~R# b,      homogeneously   |        a ~R# b             | (a :: Type) ~R# (b :: Type) |
| a ~R# b,      heterogeneously |        a ~R# b             | (a :: Type) ~R# (c :: k)    |
--------------------------------------------------------------------------------------------

(* There is no heterogeneous, representational, lifted equality counterpart
to (~~). There could be, but there seems to be no use for it.)

This table adheres to the following rules:

A. With -fprint-equality-relations, print the true equality relation.
B. Without -fprint-equality-relations:
     i. If the equality is representational and homogeneous, use Coercible.
    ii. Otherwise, if the equality is representational, use ~R#.
   iii. If the equality is nominal and homogeneous, use ~.
    iv. Otherwise, if the equality is nominal, use ~~.
C. With -fprint-explicit-kinds, print kinds on both sides of an infix operator,
   as above; or print the kind with Coercible.
D. Without -fprint-explicit-kinds, don't print kinds.

A hetero-kinded equality is used homogeneously when it is applied to two
identical kinds. Unfortunately, determining this from an IfaceType isn't
possible since we can't see through type synonyms. Consequently, we need to
record whether this particular application is homogeneous in IfaceTyConSort
for the purposes of pretty-printing.

See Note [The equality types story] in TysPrim.
-}

data IfaceTyConInfo   -- Used to guide pretty-printing
                      -- and to disambiguate D from 'D (they share a name)
  = IfaceTyConInfo { ifaceTyConIsPromoted :: PromotionFlag
                   , ifaceTyConSort       :: IfaceTyConSort }
    deriving (Eq)

data IfaceMCoercion
  = IfaceMRefl
  | IfaceMCo IfaceCoercion

data IfaceCoercion
  = IfaceReflCo       IfaceType
  | IfaceGReflCo      Role IfaceType (IfaceMCoercion)
  | IfaceFunCo        Role IfaceCoercion IfaceCoercion
  | IfaceTyConAppCo   Role IfaceTyCon [IfaceCoercion]
  | IfaceAppCo        IfaceCoercion IfaceCoercion
  | IfaceForAllCo     IfaceBndr IfaceCoercion IfaceCoercion
  | IfaceCoVarCo      IfLclName
  | IfaceAxiomInstCo  IfExtName BranchIndex [IfaceCoercion]
  | IfaceAxiomRuleCo  IfLclName [IfaceCoercion]
       -- There are only a fixed number of CoAxiomRules, so it suffices
       -- to use an IfaceLclName to distinguish them.
       -- See Note [Adding built-in type families] in TcTypeNats
  | IfaceUnivCo       IfaceUnivCoProv Role IfaceType IfaceType
  | IfaceSymCo        IfaceCoercion
  | IfaceTransCo      IfaceCoercion IfaceCoercion
  | IfaceNthCo        Int IfaceCoercion
  | IfaceLRCo         LeftOrRight IfaceCoercion
  | IfaceInstCo       IfaceCoercion IfaceCoercion
  | IfaceKindCo       IfaceCoercion
  | IfaceSubCo        IfaceCoercion
  | IfaceFreeCoVar    CoVar    -- See Note [Free tyvars in IfaceType]
  | IfaceHoleCo       CoVar    -- ^ See Note [Holes in IfaceCoercion]

data IfaceUnivCoProv
  = IfaceUnsafeCoerceProv
  | IfacePhantomProv IfaceCoercion
  | IfaceProofIrrelProv IfaceCoercion
  | IfacePluginProv String

{- Note [Holes in IfaceCoercion]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
When typechecking fails the typechecker will produce a HoleCo to stand
in place of the unproven assertion. While we generally don't want to
let these unproven assertions leak into interface files, we still need
to be able to pretty-print them as we use IfaceType's pretty-printer
to render Types. For this reason IfaceCoercion has a IfaceHoleCo
constructor; however, we fails when asked to serialize to a
IfaceHoleCo to ensure that they don't end up in an interface file.


%************************************************************************
%*                                                                      *
                Functions over IFaceTypes
*                                                                      *
************************************************************************
-}

ifaceTyConHasKey :: IfaceTyCon -> Unique -> Bool
ifaceTyConHasKey tc key = ifaceTyConName tc `hasKey` key

isIfaceLiftedTypeKind :: IfaceKind -> Bool
isIfaceLiftedTypeKind (IfaceTyConApp tc IA_Nil)
  = isLiftedTypeKindTyConName (ifaceTyConName tc)
isIfaceLiftedTypeKind (IfaceTyConApp tc
                       (IA_Arg (IfaceTyConApp ptr_rep_lifted IA_Nil)
                               Required IA_Nil))
  =  tc `ifaceTyConHasKey` tYPETyConKey
  && ptr_rep_lifted `ifaceTyConHasKey` liftedRepDataConKey
isIfaceLiftedTypeKind _ = False

splitIfaceSigmaTy :: IfaceType -> ([IfaceForAllBndr], [IfacePredType], IfaceType)
-- Mainly for printing purposes
--
-- Here we split nested IfaceSigmaTy properly.
--
-- @
-- forall t. T t => forall m a b. M m => (a -> m b) -> t a -> m (t b)
-- @
--
-- If you called @splitIfaceSigmaTy@ on this type:
--
-- @
-- ([t, m, a, b], [T t, M m], (a -> m b) -> t a -> m (t b))
-- @
splitIfaceSigmaTy ty
  = case (bndrs, theta) of
      ([], []) -> (bndrs, theta, tau)
      _        -> let (bndrs', theta', tau') = splitIfaceSigmaTy tau
                   in (bndrs ++ bndrs', theta ++ theta', tau')
  where
    (bndrs, rho)   = split_foralls ty
    (theta, tau)   = split_rho rho

    split_foralls (IfaceForAllTy bndr ty)
        = case split_foralls ty of { (bndrs, rho) -> (bndr:bndrs, rho) }
    split_foralls rho = ([], rho)

    split_rho (IfaceFunTy InvisArg ty1 ty2)
        = case split_rho ty2 of { (ps, tau) -> (ty1:ps, tau) }
    split_rho tau = ([], tau)

suppressIfaceInvisibles :: DynFlags -> [IfaceTyConBinder] -> [a] -> [a]
suppressIfaceInvisibles dflags tys xs
  | gopt Opt_PrintExplicitKinds dflags = xs
  | otherwise = suppress tys xs
    where
      suppress _       []      = []
      suppress []      a       = a
      suppress (k:ks) (x:xs)
        | isInvisibleTyConBinder k =     suppress ks xs
        | otherwise                = x : suppress ks xs

stripIfaceInvisVars :: DynFlags -> [IfaceTyConBinder] -> [IfaceTyConBinder]
stripIfaceInvisVars dflags tyvars
  | gopt Opt_PrintExplicitKinds dflags = tyvars
  | otherwise = filterOut isInvisibleTyConBinder tyvars

-- | Extract an 'IfaceBndr' from an 'IfaceForAllBndr'.
ifForAllBndrVar :: IfaceForAllBndr -> IfaceBndr
ifForAllBndrVar = binderVar

-- | Extract the variable name from an 'IfaceForAllBndr'.
ifForAllBndrName :: IfaceForAllBndr -> IfLclName
ifForAllBndrName fab = ifaceBndrName (ifForAllBndrVar fab)

-- | Extract an 'IfaceBndr' from an 'IfaceTyConBinder'.
ifTyConBinderVar :: IfaceTyConBinder -> IfaceBndr
ifTyConBinderVar = binderVar

-- | Extract the variable name from an 'IfaceTyConBinder'.
ifTyConBinderName :: IfaceTyConBinder -> IfLclName
ifTyConBinderName tcb = ifaceBndrName (ifTyConBinderVar tcb)

ifTypeIsVarFree :: IfaceType -> Bool
-- Returns True if the type definitely has no variables at all
-- Just used to control pretty printing
ifTypeIsVarFree ty = go ty
  where
    go (IfaceTyVar {})         = False
    go (IfaceFreeTyVar {})     = False
    go (IfaceAppTy fun args)   = go fun && go_args args
    go (IfaceFunTy _ arg res)  = go arg && go res
    go (IfaceForAllTy {})      = False
    go (IfaceTyConApp _ args)  = go_args args
    go (IfaceTupleTy _ _ args) = go_args args
    go (IfaceLitTy _)          = True
    go (IfaceCastTy {})        = False -- Safe
    go (IfaceCoercionTy {})    = False -- Safe

    go_args IA_Nil = True
    go_args (IA_Arg arg _ args) = go arg && go_args args

{- Note [Substitution on IfaceType]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Substitutions on IfaceType are done only during pretty-printing to
construct the result type of a GADT, and does not deal with binders
(eg IfaceForAll), so it doesn't need fancy capture stuff.  -}

type IfaceTySubst = FastStringEnv IfaceType -- Note [Substitution on IfaceType]

mkIfaceTySubst :: [(IfLclName,IfaceType)] -> IfaceTySubst
-- See Note [Substitution on IfaceType]
mkIfaceTySubst eq_spec = mkFsEnv eq_spec

inDomIfaceTySubst :: IfaceTySubst -> IfaceTvBndr -> Bool
-- See Note [Substitution on IfaceType]
inDomIfaceTySubst subst (fs, _) = isJust (lookupFsEnv subst fs)

substIfaceType :: IfaceTySubst -> IfaceType -> IfaceType
-- See Note [Substitution on IfaceType]
substIfaceType env ty
  = go ty
  where
    go (IfaceFreeTyVar tv)    = IfaceFreeTyVar tv
    go (IfaceTyVar tv)        = substIfaceTyVar env tv
    go (IfaceAppTy  t ts)     = IfaceAppTy  (go t) (substIfaceAppArgs env ts)
    go (IfaceFunTy af t1 t2)  = IfaceFunTy af (go t1) (go t2)
    go ty@(IfaceLitTy {})     = ty
    go (IfaceTyConApp tc tys) = IfaceTyConApp tc (substIfaceAppArgs env tys)
    go (IfaceTupleTy s i tys) = IfaceTupleTy s i (substIfaceAppArgs env tys)
    go (IfaceForAllTy {})     = pprPanic "substIfaceType" (ppr ty)
    go (IfaceCastTy ty co)    = IfaceCastTy (go ty) (go_co co)
    go (IfaceCoercionTy co)   = IfaceCoercionTy (go_co co)

    go_mco IfaceMRefl    = IfaceMRefl
    go_mco (IfaceMCo co) = IfaceMCo $ go_co co

    go_co (IfaceReflCo ty)           = IfaceReflCo (go ty)
    go_co (IfaceGReflCo r ty mco)    = IfaceGReflCo r (go ty) (go_mco mco)
    go_co (IfaceFunCo r c1 c2)       = IfaceFunCo r (go_co c1) (go_co c2)
    go_co (IfaceTyConAppCo r tc cos) = IfaceTyConAppCo r tc (go_cos cos)
    go_co (IfaceAppCo c1 c2)         = IfaceAppCo (go_co c1) (go_co c2)
    go_co (IfaceForAllCo {})         = pprPanic "substIfaceCoercion" (ppr ty)
    go_co (IfaceFreeCoVar cv)        = IfaceFreeCoVar cv
    go_co (IfaceCoVarCo cv)          = IfaceCoVarCo cv
    go_co (IfaceHoleCo cv)           = IfaceHoleCo cv
    go_co (IfaceAxiomInstCo a i cos) = IfaceAxiomInstCo a i (go_cos cos)
    go_co (IfaceUnivCo prov r t1 t2) = IfaceUnivCo (go_prov prov) r (go t1) (go t2)
    go_co (IfaceSymCo co)            = IfaceSymCo (go_co co)
    go_co (IfaceTransCo co1 co2)     = IfaceTransCo (go_co co1) (go_co co2)
    go_co (IfaceNthCo n co)          = IfaceNthCo n (go_co co)
    go_co (IfaceLRCo lr co)          = IfaceLRCo lr (go_co co)
    go_co (IfaceInstCo c1 c2)        = IfaceInstCo (go_co c1) (go_co c2)
    go_co (IfaceKindCo co)           = IfaceKindCo (go_co co)
    go_co (IfaceSubCo co)            = IfaceSubCo (go_co co)
    go_co (IfaceAxiomRuleCo n cos)   = IfaceAxiomRuleCo n (go_cos cos)

    go_cos = map go_co

    go_prov IfaceUnsafeCoerceProv    = IfaceUnsafeCoerceProv
    go_prov (IfacePhantomProv co)    = IfacePhantomProv (go_co co)
    go_prov (IfaceProofIrrelProv co) = IfaceProofIrrelProv (go_co co)
    go_prov (IfacePluginProv str)    = IfacePluginProv str

substIfaceAppArgs :: IfaceTySubst -> IfaceAppArgs -> IfaceAppArgs
substIfaceAppArgs env args
  = go args
  where
    go IA_Nil              = IA_Nil
    go (IA_Arg ty arg tys) = IA_Arg (substIfaceType env ty) arg (go tys)

substIfaceTyVar :: IfaceTySubst -> IfLclName -> IfaceType
substIfaceTyVar env tv
  | Just ty <- lookupFsEnv env tv = ty
  | otherwise                     = IfaceTyVar tv


{-
************************************************************************
*                                                                      *
                Functions over IfaceAppArgs
*                                                                      *
************************************************************************
-}

stripInvisArgs :: DynFlags -> IfaceAppArgs -> IfaceAppArgs
stripInvisArgs dflags tys
  | gopt Opt_PrintExplicitKinds dflags = tys
  | otherwise = suppress_invis tys
    where
      suppress_invis c
        = case c of
            IA_Nil -> IA_Nil
            IA_Arg t argf ts
              |  isVisibleArgFlag argf
              -> IA_Arg t argf $ suppress_invis ts
              -- Keep recursing through the remainder of the arguments, as it's
              -- possible that there are remaining invisible ones.
              -- See the "In type declarations" section of Note [VarBndrs,
              -- TyCoVarBinders, TyConBinders, and visibility] in TyCoRep.
              |  otherwise
              -> suppress_invis ts

appArgsIfaceTypes :: IfaceAppArgs -> [IfaceType]
appArgsIfaceTypes IA_Nil = []
appArgsIfaceTypes (IA_Arg t _ ts) = t : appArgsIfaceTypes ts

appArgsIfaceTypesArgFlags :: IfaceAppArgs -> [(IfaceType, ArgFlag)]
appArgsIfaceTypesArgFlags IA_Nil = []
appArgsIfaceTypesArgFlags (IA_Arg t a ts)
                                 = (t, a) : appArgsIfaceTypesArgFlags ts

ifaceVisAppArgsLength :: IfaceAppArgs -> Int
ifaceVisAppArgsLength = go 0
  where
    go !n IA_Nil = n
    go n  (IA_Arg _ argf rest)
      | isVisibleArgFlag argf = go (n+1) rest
      | otherwise             = go n rest

{-
Note [Suppressing invisible arguments]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
We use the IfaceAppArgs data type to specify which of the arguments to a type
should be displayed when pretty-printing, under the control of
-fprint-explicit-kinds.
See also Type.filterOutInvisibleTypes.
For example, given

    T :: forall k. (k->*) -> k -> *    -- Ordinary kind polymorphism
    'Just :: forall k. k -> 'Maybe k   -- Promoted

we want

    T * Tree Int    prints as    T Tree Int
    'Just *         prints as    Just *

For type constructors (IfaceTyConApp), IfaceAppArgs is a quite natural fit,
since the corresponding Core constructor:

    data Type
      = ...
      | TyConApp TyCon [Type]

Already puts all of its arguments into a list. So when converting a Type to an
IfaceType (see toIfaceAppArgsX in ToIface), we simply use the kind of the TyCon
(which is cached) to guide the process of converting the argument Types into an
IfaceAppArgs list.

We also want this behavior for IfaceAppTy, since given:

    data Proxy (a :: k)
    f :: forall (t :: forall a. a -> Type). Proxy Type (t Bool True)

We want to print the return type as `Proxy (t True)` without the use of
-fprint-explicit-kinds (#15330). Accomplishing this is trickier than in the
tycon case, because the corresponding Core constructor for IfaceAppTy:

    data Type
      = ...
      | AppTy Type Type

Only stores one argument at a time. Therefore, when converting an AppTy to an
IfaceAppTy (in toIfaceTypeX in ToIface), we:

1. Flatten the chain of AppTys down as much as possible
2. Use typeKind to determine the function Type's kind
3. Use this kind to guide the process of converting the argument Types into an
   IfaceAppArgs list.

By flattening the arguments like this, we obtain two benefits:

(a) We can reuse the same machinery to pretty-print IfaceTyConApp arguments as
    we do IfaceTyApp arguments, which means that we only need to implement the
    logic to filter out invisible arguments once.
(b) Unlike for tycons, finding the kind of a type in general (through typeKind)
    is not a constant-time operation, so by flattening the arguments first, we
    decrease the number of times we have to call typeKind.

Note [Pretty-printing invisible arguments]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Note [Suppressing invisible arguments] is all about how to avoid printing
invisible arguments when the -fprint-explicit-kinds flag is disables. Well,
what about when it's enabled? Then we can and should print invisible kind
arguments, and this Note explains how we do it.

As two running examples, consider the following code:

  {-# LANGUAGE PolyKinds #-}
  data T1 a
  data T2 (a :: k)

When displaying these types (with -fprint-explicit-kinds on), we could just
do the following:

  T1 k a
  T2 k a

That certainly gets the job done. But it lacks a crucial piece of information:
is the `k` argument inferred or specified? To communicate this, we use visible
kind application syntax to distinguish the two cases:

  T1 @{k} a
  T2 @k   a

Here, @{k} indicates that `k` is an inferred argument, and @k indicates that
`k` is a specified argument. (See
Note [VarBndrs, TyCoVarBinders, TyConBinders, and visibility] in TyCoRep for
a lengthier explanation on what "inferred" and "specified" mean.)

************************************************************************
*                                                                      *
                Pretty-printing
*                                                                      *
************************************************************************
-}

if_print_coercions :: SDoc  -- ^ if printing coercions
                   -> SDoc  -- ^ otherwise
                   -> SDoc
if_print_coercions yes no
  = sdocWithDynFlags $ \dflags ->
    getPprStyle $ \style ->
    if gopt Opt_PrintExplicitCoercions dflags
         || dumpStyle style || debugStyle style
    then yes
    else no

pprIfaceInfixApp :: PprPrec -> SDoc -> SDoc -> SDoc -> SDoc
pprIfaceInfixApp ctxt_prec pp_tc pp_ty1 pp_ty2
  = maybeParen ctxt_prec opPrec $
    sep [pp_ty1, pp_tc <+> pp_ty2]

pprIfacePrefixApp :: PprPrec -> SDoc -> [SDoc] -> SDoc
pprIfacePrefixApp ctxt_prec pp_fun pp_tys
  | null pp_tys = pp_fun
  | otherwise   = maybeParen ctxt_prec appPrec $
                  hang pp_fun 2 (sep pp_tys)

isIfaceTauType :: IfaceType -> Bool
isIfaceTauType (IfaceForAllTy _ _) = False
isIfaceTauType (IfaceFunTy InvisArg _ _) = False
isIfaceTauType _ = True

-- ----------------------------- Printing binders ------------------------------------

instance Outputable IfaceBndr where
    ppr (IfaceIdBndr bndr) = pprIfaceIdBndr bndr
    ppr (IfaceTvBndr bndr) = char '@' <+> pprIfaceTvBndr bndr (SuppressBndrSig False)
                                                              (UseBndrParens False)

pprIfaceBndrs :: [IfaceBndr] -> SDoc
pprIfaceBndrs bs = sep (map ppr bs)

pprIfaceLamBndr :: IfaceLamBndr -> SDoc
pprIfaceLamBndr (b, IfaceNoOneShot) = ppr b
pprIfaceLamBndr (b, IfaceOneShot)   = ppr b <> text "[OneShot]"

pprIfaceIdBndr :: IfaceIdBndr -> SDoc
pprIfaceIdBndr (name, ty) = parens (ppr name <+> dcolon <+> ppr ty)

{- Note [Suppressing binder signatures]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
When printing the binders in a 'forall', we want to keep the kind annotations:

    forall (a :: k). blah
              ^^^^
              good

On the other hand, when we print the binders of a data declaration in :info,
the kind information would be redundant due to the standalone kind signature:

   type F :: Symbol -> Type
   type F (s :: Symbol) = blah
             ^^^^^^^^^
             redundant

Here we'd like to omit the kind annotation:

   type F :: Symbol -> Type
   type F s = blah
-}

-- | Do we want to suppress kind annotations on binders?
-- See Note [Suppressing binder signatures]
newtype SuppressBndrSig = SuppressBndrSig Bool

newtype UseBndrParens = UseBndrParens Bool

pprIfaceTvBndr :: IfaceTvBndr -> SuppressBndrSig -> UseBndrParens -> SDoc
pprIfaceTvBndr (tv, ki) (SuppressBndrSig suppress_sig) (UseBndrParens use_parens)
  | suppress_sig             = ppr tv
  | isIfaceLiftedTypeKind ki = ppr tv
  | otherwise                = maybe_parens (ppr tv <+> dcolon <+> ppr ki)
  where
    maybe_parens | use_parens = parens
                 | otherwise  = id

pprIfaceTyConBinders :: SuppressBndrSig -> [IfaceTyConBinder] -> SDoc
pprIfaceTyConBinders suppress_sig = sep . map go
  where
    go :: IfaceTyConBinder -> SDoc
    go (Bndr (IfaceIdBndr bndr) _) = pprIfaceIdBndr bndr
    go (Bndr (IfaceTvBndr bndr) vis) =
      -- See Note [Pretty-printing invisible arguments]
      case vis of
        AnonTCB  VisArg    -> ppr_bndr (UseBndrParens True)
        AnonTCB  InvisArg  -> char '@' <> braces (ppr_bndr (UseBndrParens False))
          -- The above case is rare. (See Note [AnonTCB InvisArg] in TyCon.)
          -- Should we print these differently?
        NamedTCB Required  -> ppr_bndr (UseBndrParens True)
        NamedTCB Specified -> char '@' <> ppr_bndr (UseBndrParens True)
        NamedTCB Inferred  -> char '@' <> braces (ppr_bndr (UseBndrParens False))
      where
        ppr_bndr = pprIfaceTvBndr bndr suppress_sig

instance Binary IfaceBndr where
    put (IfaceIdBndr aa) = do
            putByte 0
            put aa
    put (IfaceTvBndr ab) = do
            putByte 1
            put ab
    get = do
            h <- getByte
            case h of
              0 -> IfaceIdBndr <$> get
              _ -> IfaceTvBndr <$> get

instance Binary IfaceOneShot where
    put IfaceNoOneShot = putByte 0
    put IfaceOneShot   = putByte 1
    get = do
            h <- getByte
            case h of
              0 -> do return IfaceNoOneShot
              _ -> do return IfaceOneShot

-- ----------------------------- Printing IfaceType ------------------------------------

---------------------------------
instance Outputable IfaceType where
  ppr ty = pprIfaceType ty

pprIfaceType, pprParendIfaceType :: IfaceType -> SDoc
pprIfaceType       = pprPrecIfaceType topPrec
pprParendIfaceType = pprPrecIfaceType appPrec

pprPrecIfaceType :: PprPrec -> IfaceType -> SDoc
-- We still need `eliminateRuntimeRep`, since the `pprPrecIfaceType` maybe
-- called from other places, besides `:type` and `:info`.
pprPrecIfaceType prec ty = eliminateRuntimeRep (ppr_ty prec) ty

ppr_sigma :: PprPrec -> IfaceType -> SDoc
ppr_sigma ctxt_prec ty
  = maybeParen ctxt_prec funPrec (pprIfaceSigmaType ShowForAllMust ty)

ppr_ty :: PprPrec -> IfaceType -> SDoc
ppr_ty ctxt_prec ty@(IfaceForAllTy {})        = ppr_sigma ctxt_prec ty
ppr_ty ctxt_prec ty@(IfaceFunTy InvisArg _ _) = ppr_sigma ctxt_prec ty

ppr_ty _         (IfaceFreeTyVar tyvar) = ppr tyvar  -- This is the main reason for IfaceFreeTyVar!
ppr_ty _         (IfaceTyVar tyvar)     = ppr tyvar  -- See Note [TcTyVars in IfaceType]
ppr_ty ctxt_prec (IfaceTyConApp tc tys) = pprTyTcApp ctxt_prec tc tys
ppr_ty ctxt_prec (IfaceTupleTy i p tys) = pprTuple ctxt_prec i p tys
ppr_ty _         (IfaceLitTy n)         = pprIfaceTyLit n
        -- Function types
ppr_ty ctxt_prec (IfaceFunTy _ ty1 ty2)  -- Should be VisArg
  = -- We don't want to lose synonyms, so we mustn't use splitFunTys here.
    maybeParen ctxt_prec funPrec $
    sep [ppr_ty funPrec ty1, sep (ppr_fun_tail ty2)]
  where
    ppr_fun_tail (IfaceFunTy VisArg ty1 ty2)
      = (arrow <+> ppr_ty funPrec ty1) : ppr_fun_tail ty2
    ppr_fun_tail other_ty
      = [arrow <+> pprIfaceType other_ty]

ppr_ty ctxt_prec (IfaceAppTy t ts)
  = if_print_coercions
      ppr_app_ty
      ppr_app_ty_no_casts
  where
    ppr_app_ty =
        sdocWithDynFlags $ \dflags ->
        pprIfacePrefixApp ctxt_prec
                          (ppr_ty funPrec t)
                          (map (ppr_app_arg appPrec) (tys_wo_kinds dflags))

    tys_wo_kinds dflags = appArgsIfaceTypesArgFlags $ stripInvisArgs dflags ts

    -- Strip any casts from the head of the application
    ppr_app_ty_no_casts =
        case t of
          IfaceCastTy head _ -> ppr_ty ctxt_prec (mk_app_tys head ts)
          _                  -> ppr_app_ty

    mk_app_tys :: IfaceType -> IfaceAppArgs -> IfaceType
    mk_app_tys (IfaceTyConApp tc tys1) tys2 =
        IfaceTyConApp tc (tys1 `mappend` tys2)
    mk_app_tys t1 tys2 = IfaceAppTy t1 tys2

ppr_ty ctxt_prec (IfaceCastTy ty co)
  = if_print_coercions
      (parens (ppr_ty topPrec ty <+> text "|>" <+> ppr co))
      (ppr_ty ctxt_prec ty)

ppr_ty ctxt_prec (IfaceCoercionTy co)
  = if_print_coercions
      (ppr_co ctxt_prec co)
      (text "<>")

{- Note [Defaulting RuntimeRep variables]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
RuntimeRep variables are considered by many (most?) users to be little
more than syntactic noise. When the notion was introduced there was a
significant and understandable push-back from those with pedagogy in
mind, which argued that RuntimeRep variables would throw a wrench into
nearly any teach approach since they appear in even the lowly ($)
function's type,

    ($) :: forall (w :: RuntimeRep) a (b :: TYPE w). (a -> b) -> a -> b

which is significantly less readable than its non RuntimeRep-polymorphic type of

    ($) :: (a -> b) -> a -> b

Moreover, unboxed types don't appear all that often in run-of-the-mill
Haskell programs, so it makes little sense to make all users pay this
syntactic overhead.

For this reason it was decided that we would hide RuntimeRep variables
for now (see #11549). We do this by defaulting all type variables of
kind RuntimeRep to LiftedRep. This is done in a pass right before
pretty-printing (defaultRuntimeRepVars, controlled by
-fprint-explicit-runtime-reps)

This applies to /quantified/ variables like 'w' above.  What about
variables that are /free/ in the type being printed, which certainly
happens in error messages.  Suppose (#16074) we are reporting a
mismatch between two skolems
          (a :: RuntimeRep) ~ (b :: RuntimeRep)
We certainly don't want to say "Can't match LiftedRep ~ LiftedRep"!

But if we are printing the type
    (forall (a :: Type r). blah
we do want to turn that (free) r into LiftedRep, so it prints as
    (forall a. blah)

Conclusion: keep track of whether we we are in the kind of a
binder; ohly if so, convert free RuntimeRep variables to LiftedRep.
-}

-- | Default 'RuntimeRep' variables to 'LiftedPtr'. e.g.
--
-- @
-- ($) :: forall (r :: GHC.Types.RuntimeRep) a (b :: TYPE r).
--        (a -> b) -> a -> b
-- @
--
-- turns in to,
--
-- @ ($) :: forall a (b :: *). (a -> b) -> a -> b @
--
-- We do this to prevent RuntimeRep variables from incurring a significant
-- syntactic overhead in otherwise simple type signatures (e.g. ($)). See
-- Note [Defaulting RuntimeRep variables] and #11549 for further discussion.
--
defaultRuntimeRepVars :: IfaceType -> IfaceType
defaultRuntimeRepVars ty = go False emptyFsEnv ty
  where
    go :: Bool              -- True <=> Inside the kind of a binder
       -> FastStringEnv ()  -- Set of enclosing forall-ed RuntimeRep variables
       -> IfaceType         --  (replace them with LiftedRep)
       -> IfaceType
    go ink subs (IfaceForAllTy (Bndr (IfaceTvBndr (var, var_kind)) argf) ty)
     | isRuntimeRep var_kind
      , isInvisibleArgFlag argf -- Don't default *visible* quantification
                                -- or we get the mess in #13963
      = let subs' = extendFsEnv subs var ()
            -- Record that we should replace it with LiftedRep,
            -- and recurse, discarding the forall
        in go ink subs' ty

    go ink subs (IfaceForAllTy bndr ty)
      = IfaceForAllTy (go_ifacebndr subs bndr) (go ink subs ty)

    go _ subs ty@(IfaceTyVar tv)
      | tv `elemFsEnv` subs
      = IfaceTyConApp liftedRep IA_Nil
      | otherwise
      = ty

    go in_kind _ ty@(IfaceFreeTyVar tv)
      -- See Note [Defaulting RuntimeRep variables], about free vars
      | in_kind && Type.isRuntimeRepTy (tyVarKind tv)
      = IfaceTyConApp liftedRep IA_Nil
      | otherwise
      = ty

    go ink subs (IfaceTyConApp tc tc_args)
      = IfaceTyConApp tc (go_args ink subs tc_args)

    go ink subs (IfaceTupleTy sort is_prom tc_args)
      = IfaceTupleTy sort is_prom (go_args ink subs tc_args)

    go ink subs (IfaceFunTy af arg res)
      = IfaceFunTy af (go ink subs arg) (go ink subs res)

    go ink subs (IfaceAppTy t ts)
      = IfaceAppTy (go ink subs t) (go_args ink subs ts)

    go ink subs (IfaceCastTy x co)
      = IfaceCastTy (go ink subs x) co

    go _ _ ty@(IfaceLitTy {}) = ty
    go _ _ ty@(IfaceCoercionTy {}) = ty

    go_ifacebndr :: FastStringEnv () -> IfaceForAllBndr -> IfaceForAllBndr
    go_ifacebndr subs (Bndr (IfaceIdBndr (n, t)) argf)
      = Bndr (IfaceIdBndr (n, go True subs t)) argf
    go_ifacebndr subs (Bndr (IfaceTvBndr (n, t)) argf)
      = Bndr (IfaceTvBndr (n, go True subs t)) argf

    go_args :: Bool -> FastStringEnv () -> IfaceAppArgs -> IfaceAppArgs
    go_args _ _ IA_Nil = IA_Nil
    go_args ink subs (IA_Arg ty argf args)
      = IA_Arg (go ink subs ty) argf (go_args ink subs args)

    liftedRep :: IfaceTyCon
    liftedRep = IfaceTyCon dc_name (IfaceTyConInfo IsPromoted IfaceNormalTyCon)
      where dc_name = getName liftedRepDataConTyCon

    isRuntimeRep :: IfaceType -> Bool
    isRuntimeRep (IfaceTyConApp tc _) =
        tc `ifaceTyConHasKey` runtimeRepTyConKey
    isRuntimeRep _ = False

eliminateRuntimeRep :: (IfaceType -> SDoc) -> IfaceType -> SDoc
eliminateRuntimeRep f ty
  = sdocWithDynFlags $ \dflags ->
    getPprStyle      $ \sty    ->
    if userStyle sty && not (gopt Opt_PrintExplicitRuntimeReps dflags)
      then f (defaultRuntimeRepVars ty)
      else f ty

instance Outputable IfaceAppArgs where
  ppr tca = pprIfaceAppArgs tca

pprIfaceAppArgs, pprParendIfaceAppArgs :: IfaceAppArgs -> SDoc
pprIfaceAppArgs  = ppr_app_args topPrec
pprParendIfaceAppArgs = ppr_app_args appPrec

ppr_app_args :: PprPrec -> IfaceAppArgs -> SDoc
ppr_app_args ctx_prec = go
  where
    go :: IfaceAppArgs -> SDoc
    go IA_Nil             = empty
    go (IA_Arg t argf ts) = ppr_app_arg ctx_prec (t, argf) <+> go ts

-- See Note [Pretty-printing invisible arguments]
ppr_app_arg :: PprPrec -> (IfaceType, ArgFlag) -> SDoc
ppr_app_arg ctx_prec (t, argf) =
  sdocWithDynFlags $ \dflags ->
  let print_kinds = gopt Opt_PrintExplicitKinds dflags
  in case argf of
       Required  -> ppr_ty ctx_prec t
       Specified |  print_kinds
                 -> char '@' <> ppr_ty appPrec t
       Inferred  |  print_kinds
                 -> char '@' <> braces (ppr_ty topPrec t)
       _         -> empty

-------------------
pprIfaceForAllPart :: [IfaceForAllBndr] -> [IfacePredType] -> SDoc -> SDoc
pprIfaceForAllPart tvs ctxt sdoc
  = ppr_iface_forall_part ShowForAllWhen tvs ctxt sdoc

-- | Like 'pprIfaceForAllPart', but always uses an explicit @forall@.
pprIfaceForAllPartMust :: [IfaceForAllBndr] -> [IfacePredType] -> SDoc -> SDoc
pprIfaceForAllPartMust tvs ctxt sdoc
  = ppr_iface_forall_part ShowForAllMust tvs ctxt sdoc

pprIfaceForAllCoPart :: [(IfLclName, IfaceCoercion)] -> SDoc -> SDoc
pprIfaceForAllCoPart tvs sdoc
  = sep [ pprIfaceForAllCo tvs, sdoc ]

ppr_iface_forall_part :: ShowForAllFlag
                      -> [IfaceForAllBndr] -> [IfacePredType] -> SDoc -> SDoc
ppr_iface_forall_part show_forall tvs ctxt sdoc
  = sep [ case show_forall of
            ShowForAllMust -> pprIfaceForAll tvs
            ShowForAllWhen -> pprUserIfaceForAll tvs
        , pprIfaceContextArr ctxt
        , sdoc]

-- | Render the "forall ... ." or "forall ... ->" bit of a type.
pprIfaceForAll :: [IfaceForAllBndr] -> SDoc
pprIfaceForAll [] = empty
pprIfaceForAll bndrs@(Bndr _ vis : _)
  = sep [ add_separator (forAllLit <+> fsep docs)
        , pprIfaceForAll bndrs' ]
  where
    (bndrs', docs) = ppr_itv_bndrs bndrs vis

    add_separator stuff = case vis of
                            Required -> stuff <+> arrow
                            _inv     -> stuff <>  dot


-- | Render the ... in @(forall ... .)@ or @(forall ... ->)@.
-- Returns both the list of not-yet-rendered binders and the doc.
-- No anonymous binders here!
ppr_itv_bndrs :: [IfaceForAllBndr]
             -> ArgFlag  -- ^ visibility of the first binder in the list
             -> ([IfaceForAllBndr], [SDoc])
ppr_itv_bndrs all_bndrs@(bndr@(Bndr _ vis) : bndrs) vis1
  | vis `sameVis` vis1 = let (bndrs', doc) = ppr_itv_bndrs bndrs vis1 in
                         (bndrs', pprIfaceForAllBndr bndr : doc)
  | otherwise   = (all_bndrs, [])
ppr_itv_bndrs [] _ = ([], [])

pprIfaceForAllCo :: [(IfLclName, IfaceCoercion)] -> SDoc
pprIfaceForAllCo []  = empty
pprIfaceForAllCo tvs = text "forall" <+> pprIfaceForAllCoBndrs tvs <> dot

pprIfaceForAllCoBndrs :: [(IfLclName, IfaceCoercion)] -> SDoc
pprIfaceForAllCoBndrs bndrs = hsep $ map pprIfaceForAllCoBndr bndrs

pprIfaceForAllBndr :: IfaceForAllBndr -> SDoc
pprIfaceForAllBndr bndr =
  case bndr of
    Bndr (IfaceTvBndr tv) Inferred ->
      sdocWithDynFlags $ \dflags ->
        if gopt Opt_PrintExplicitForalls dflags
        then braces $ pprIfaceTvBndr tv suppress_sig (UseBndrParens False)
        else pprIfaceTvBndr tv suppress_sig (UseBndrParens True)
    Bndr (IfaceTvBndr tv) _ ->
      pprIfaceTvBndr tv suppress_sig (UseBndrParens True)
    Bndr (IfaceIdBndr idv) _ -> pprIfaceIdBndr idv
  where
    -- See Note [Suppressing binder signatures] in IfaceType
    suppress_sig = SuppressBndrSig False

pprIfaceForAllCoBndr :: (IfLclName, IfaceCoercion) -> SDoc
pprIfaceForAllCoBndr (tv, kind_co)
  = parens (ppr tv <+> dcolon <+> pprIfaceCoercion kind_co)

-- | Show forall flag
--
-- Unconditionally show the forall quantifier with ('ShowForAllMust')
-- or when ('ShowForAllWhen') the names used are free in the binder
-- or when compiling with -fprint-explicit-foralls.
data ShowForAllFlag = ShowForAllMust | ShowForAllWhen

pprIfaceSigmaType :: ShowForAllFlag -> IfaceType -> SDoc
pprIfaceSigmaType show_forall ty
  = eliminateRuntimeRep ppr_fn ty
  where
    ppr_fn iface_ty =
      let (tvs, theta, tau) = splitIfaceSigmaTy iface_ty
       in ppr_iface_forall_part show_forall tvs theta (ppr tau)

pprUserIfaceForAll :: [IfaceForAllBndr] -> SDoc
pprUserIfaceForAll tvs
   = sdocWithDynFlags $ \dflags ->
     -- See Note [When to print foralls] in this module.
     ppWhen (any tv_has_kind_var tvs
             || any tv_is_required tvs
             || gopt Opt_PrintExplicitForalls dflags) $
     pprIfaceForAll tvs
   where
     tv_has_kind_var (Bndr (IfaceTvBndr (_,kind)) _)
       = not (ifTypeIsVarFree kind)
     tv_has_kind_var _ = False

     tv_is_required = isVisibleArgFlag . binderArgFlag

{-
Note [When to print foralls]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~
We opt to explicitly pretty-print `forall`s if any of the following
criteria are met:

1. -fprint-explicit-foralls is on.

2. A bound type variable has a polymorphic kind. E.g.,

     forall k (a::k). Proxy a -> Proxy a

   Since a's kind mentions a variable k, we print the foralls.

3. A bound type variable is a visible argument (#14238).
   Suppose we are printing the kind of:

     T :: forall k -> k -> Type

   The "forall k ->" notation means that this kind argument is required.
   That is, it must be supplied at uses of T. E.g.,

     f :: T (Type->Type)  Monad -> Int

   So we print an explicit "T :: forall k -> k -> Type",
   because omitting it and printing "T :: k -> Type" would be
   utterly misleading.

   See Note [VarBndrs, TyCoVarBinders, TyConBinders, and visibility]
   in TyCoRep.

N.B. Until now (Aug 2018) we didn't check anything for coercion variables.

Note [Printing foralls in type family instances]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
We use the same criteria as in Note [When to print foralls] to determine
whether a type family instance should be pretty-printed with an explicit
`forall`. Example:

  type family Foo (a :: k) :: k where
    Foo Maybe       = []
    Foo (a :: Type) = Int
    Foo a           = a

Without -fprint-explicit-foralls enabled, this will be pretty-printed as:

type family Foo (a :: k) :: k where
  Foo Maybe = []
  Foo a = Int
  forall k (a :: k). Foo a = a

Note that only the third equation has an explicit forall, since it has a type
variable with a non-Type kind. (If -fprint-explicit-foralls were enabled, then
the second equation would be preceded with `forall a.`.)

There is one tricky point in the implementation: what visibility
do we give the type variables in a type family instance? Type family instances
only store type *variables*, not type variable *binders*, and only the latter
has visibility information. We opt to default the visibility of each of these
type variables to Specified because users can't ever instantiate these
variables manually, so the choice of visibility is only relevant to
pretty-printing. (This is why the `k` in `forall k (a :: k). ...` above is
printed the way it is, even though it wasn't written explicitly in the
original source code.)

We adopt the same strategy for data family instances. Example:

  data family DF (a :: k)
  data instance DF '[a, b] = DFList

That data family instance is pretty-printed as:

  data instance forall j (a :: j) (b :: j). DF '[a, b] = DFList

This is despite that the representation tycon for this data instance (call it
$DF:List) actually has different visibilities for its binders.
However, the visibilities of these binders are utterly irrelevant to the
programmer, who cares only about the specificity of variables in `DF`'s type,
not $DF:List's type. Therefore, we opt to pretty-print all variables in data
family instances as Specified.

Note [Printing promoted type constructors]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Consider this GHCi session (#14343)
    > _ :: Proxy '[ 'True ]
    error:
      Found hole: _ :: Proxy '['True]

This would be bad, because the '[' looks like a character literal.
Solution: in type-level lists and tuples, add a leading space
if the first type is itself promoted.  See pprSpaceIfPromotedTyCon.
-}


-------------------

-- | Prefix a space if the given 'IfaceType' is a promoted 'TyCon'.
-- See Note [Printing promoted type constructors]
pprSpaceIfPromotedTyCon :: IfaceType -> SDoc -> SDoc
pprSpaceIfPromotedTyCon (IfaceTyConApp tyCon _)
  = case ifaceTyConIsPromoted (ifaceTyConInfo tyCon) of
      IsPromoted -> (space <>)
      _ -> id
pprSpaceIfPromotedTyCon _
  = id

-- See equivalent function in TyCoRep.hs
pprIfaceTyList :: PprPrec -> IfaceType -> IfaceType -> SDoc
-- Given a type-level list (t1 ': t2), see if we can print
-- it in list notation [t1, ...].
-- Precondition: Opt_PrintExplicitKinds is off
pprIfaceTyList ctxt_prec ty1 ty2
  = case gather ty2 of
      (arg_tys, Nothing)
        -> char '\'' <> brackets (pprSpaceIfPromotedTyCon ty1 (fsep
                        (punctuate comma (map (ppr_ty topPrec) (ty1:arg_tys)))))
      (arg_tys, Just tl)
        -> maybeParen ctxt_prec funPrec $ hang (ppr_ty funPrec ty1)
           2 (fsep [ colon <+> ppr_ty funPrec ty | ty <- arg_tys ++ [tl]])
  where
    gather :: IfaceType -> ([IfaceType], Maybe IfaceType)
     -- (gather ty) = (tys, Nothing) means ty is a list [t1, .., tn]
     --             = (tys, Just tl) means ty is of form t1:t2:...tn:tl
    gather (IfaceTyConApp tc tys)
      | tc `ifaceTyConHasKey` consDataConKey
      , IA_Arg _ argf (IA_Arg ty1 Required (IA_Arg ty2 Required IA_Nil)) <- tys
      , isInvisibleArgFlag argf
      , (args, tl) <- gather ty2
      = (ty1:args, tl)
      | tc `ifaceTyConHasKey` nilDataConKey
      = ([], Nothing)
    gather ty = ([], Just ty)

pprIfaceTypeApp :: PprPrec -> IfaceTyCon -> IfaceAppArgs -> SDoc
pprIfaceTypeApp prec tc args = pprTyTcApp prec tc args

pprTyTcApp :: PprPrec -> IfaceTyCon -> IfaceAppArgs -> SDoc
pprTyTcApp ctxt_prec tc tys =
    sdocWithDynFlags $ \dflags ->
    getPprStyle $ \style ->
    pprTyTcApp' ctxt_prec tc tys dflags style

pprTyTcApp' :: PprPrec -> IfaceTyCon -> IfaceAppArgs
            -> DynFlags -> PprStyle -> SDoc
pprTyTcApp' ctxt_prec tc tys dflags style
  | ifaceTyConName tc `hasKey` ipClassKey
  , IA_Arg (IfaceLitTy (IfaceStrTyLit n))
           Required (IA_Arg ty Required IA_Nil) <- tys
  = maybeParen ctxt_prec funPrec
    $ char '?' <> ftext n <> text "::" <> ppr_ty topPrec ty

  | IfaceTupleTyCon arity sort <- ifaceTyConSort info
  , not (debugStyle style)
  , arity == ifaceVisAppArgsLength tys
  = pprTuple ctxt_prec sort (ifaceTyConIsPromoted info) tys

  | IfaceSumTyCon arity <- ifaceTyConSort info
  = pprSum arity (ifaceTyConIsPromoted info) tys

  | tc `ifaceTyConHasKey` consDataConKey
  , not (gopt Opt_PrintExplicitKinds dflags)
  , IA_Arg _ argf (IA_Arg ty1 Required (IA_Arg ty2 Required IA_Nil)) <- tys
  , isInvisibleArgFlag argf
  = pprIfaceTyList ctxt_prec ty1 ty2

  | tc `ifaceTyConHasKey` tYPETyConKey
  , IA_Arg (IfaceTyConApp rep IA_Nil) Required IA_Nil <- tys
  , rep `ifaceTyConHasKey` liftedRepDataConKey
  = kindType

  | otherwise
  = getPprDebug $ \dbg ->
    if | not dbg && tc `ifaceTyConHasKey` errorMessageTypeErrorFamKey
         -- Suppress detail unles you _really_ want to see
         -> text "(TypeError ...)"

       | Just doc <- ppr_equality ctxt_prec tc (appArgsIfaceTypes tys)
         -> doc

       | otherwise
         -> ppr_iface_tc_app ppr_app_arg ctxt_prec tc tys_wo_kinds
  where
    info = ifaceTyConInfo tc
    tys_wo_kinds = appArgsIfaceTypesArgFlags $ stripInvisArgs dflags tys

-- | Pretty-print a type-level equality.
-- Returns (Just doc) if the argument is a /saturated/ application
-- of   eqTyCon          (~)
--      eqPrimTyCon      (~#)
--      eqReprPrimTyCon  (~R#)
--      heqTyCon         (~~)
--
-- See Note [Equality predicates in IfaceType]
-- and Note [The equality types story] in TysPrim
ppr_equality :: PprPrec -> IfaceTyCon -> [IfaceType] -> Maybe SDoc
ppr_equality ctxt_prec tc args
  | hetero_eq_tc
  , [k1, k2, t1, t2] <- args
  = Just $ print_equality (k1, k2, t1, t2)

  | hom_eq_tc
  , [k, t1, t2] <- args
  = Just $ print_equality (k, k, t1, t2)

  | otherwise
  = Nothing
  where
    homogeneous = tc_name `hasKey` eqTyConKey -- (~)
               || hetero_tc_used_homogeneously
      where
        hetero_tc_used_homogeneously
          = case ifaceTyConSort $ ifaceTyConInfo tc of
                          IfaceEqualityTyCon -> True
                          _other             -> False
             -- True <=> a heterogeneous equality whose arguments
             --          are (in this case) of the same kind

    tc_name = ifaceTyConName tc
    pp = ppr_ty
    hom_eq_tc = tc_name `hasKey` eqTyConKey            -- (~)
    hetero_eq_tc = tc_name `hasKey` eqPrimTyConKey     -- (~#)
                || tc_name `hasKey` eqReprPrimTyConKey -- (~R#)
                || tc_name `hasKey` heqTyConKey        -- (~~)
    nominal_eq_tc = tc_name `hasKey` heqTyConKey       -- (~~)
                 || tc_name `hasKey` eqPrimTyConKey    -- (~#)
    print_equality args =
        sdocWithDynFlags $ \dflags ->
        getPprStyle      $ \style  ->
        print_equality' args style dflags

    print_equality' (ki1, ki2, ty1, ty2) style dflags
      | -- If -fprint-equality-relations is on, just print the original TyCon
        print_eqs
      = ppr_infix_eq (ppr tc)

      | -- Homogeneous use of heterogeneous equality (ty1 ~~ ty2)
        --                 or unlifted equality      (ty1 ~# ty2)
        nominal_eq_tc, homogeneous
      = ppr_infix_eq (text "~")

      | -- Heterogeneous use of unlifted equality (ty1 ~# ty2)
        not homogeneous
      = ppr_infix_eq (ppr heqTyCon)

      | -- Homogeneous use of representational unlifted equality (ty1 ~R# ty2)
        tc_name `hasKey` eqReprPrimTyConKey, homogeneous
      = let ki | print_kinds = [pp appPrec ki1]
               | otherwise   = []
        in pprIfacePrefixApp ctxt_prec (ppr coercibleTyCon)
                            (ki ++ [pp appPrec ty1, pp appPrec ty2])

        -- The other cases work as you'd expect
      | otherwise
      = ppr_infix_eq (ppr tc)
      where
        ppr_infix_eq :: SDoc -> SDoc
        ppr_infix_eq eq_op = pprIfaceInfixApp ctxt_prec eq_op
                               (pp_ty_ki ty1 ki1) (pp_ty_ki ty2 ki2)
          where
            pp_ty_ki ty ki
              | print_kinds
              = parens (pp topPrec ty <+> dcolon <+> pp opPrec ki)
              | otherwise
              = pp opPrec ty

        print_kinds = gopt Opt_PrintExplicitKinds dflags
        print_eqs   = gopt Opt_PrintEqualityRelations dflags ||
                      dumpStyle style || debugStyle style


pprIfaceCoTcApp :: PprPrec -> IfaceTyCon -> [IfaceCoercion] -> SDoc
pprIfaceCoTcApp ctxt_prec tc tys =
  ppr_iface_tc_app (\prec (co, _) -> ppr_co prec co) ctxt_prec tc
    (map (, Required) tys)
    -- We are trying to re-use ppr_iface_tc_app here, which requires its
    -- arguments to be accompanied by visibilities. But visibility is
    -- irrelevant when printing coercions, so just default everything to
    -- Required.

-- | Pretty-prints an application of a type constructor to some arguments
-- (whose visibilities are known). This is polymorphic (over @a@) since we use
-- this function to pretty-print two different things:
--
-- 1. Types (from `pprTyTcApp'`)
--
-- 2. Coercions (from 'pprIfaceCoTcApp')
ppr_iface_tc_app :: (PprPrec -> (a, ArgFlag) -> SDoc)
                 -> PprPrec -> IfaceTyCon -> [(a, ArgFlag)] -> SDoc
ppr_iface_tc_app pp _ tc [ty]
  | tc `ifaceTyConHasKey` listTyConKey = pprPromotionQuote tc <> brackets (pp topPrec ty)

ppr_iface_tc_app pp ctxt_prec tc tys
  | tc `ifaceTyConHasKey` liftedTypeKindTyConKey
  = kindType

  | not (isSymOcc (nameOccName (ifaceTyConName tc)))
  = pprIfacePrefixApp ctxt_prec (ppr tc) (map (pp appPrec) tys)

  | [ ty1@(_, Required)
    , ty2@(_, Required) ] <- tys
      -- Infix, two visible arguments (we know nothing of precedence though).
      -- Don't apply this special case if one of the arguments is invisible,
      -- lest we print something like (@LiftedRep -> @LiftedRep) (#15941).
  = pprIfaceInfixApp ctxt_prec (ppr tc)
                     (pp opPrec ty1) (pp opPrec ty2)

  | otherwise
  = pprIfacePrefixApp ctxt_prec (parens (ppr tc)) (map (pp appPrec) tys)

pprSum :: Arity -> PromotionFlag -> IfaceAppArgs -> SDoc
pprSum _arity is_promoted args
  =   -- drop the RuntimeRep vars.
      -- See Note [Unboxed tuple RuntimeRep vars] in TyCon
    let tys   = appArgsIfaceTypes args
        args' = drop (length tys `div` 2) tys
    in pprPromotionQuoteI is_promoted
       <> sumParens (pprWithBars (ppr_ty topPrec) args')

pprTuple :: PprPrec -> TupleSort -> PromotionFlag -> IfaceAppArgs -> SDoc
pprTuple ctxt_prec sort promoted args =
  case promoted of
    IsPromoted
      -> let tys = appArgsIfaceTypes args
             args' = drop (length tys `div` 2) tys
             spaceIfPromoted = case args' of
               arg0:_ -> pprSpaceIfPromotedTyCon arg0
               _ -> id
         in ppr_tuple_app args' $
            pprPromotionQuoteI IsPromoted <>
            tupleParens sort (spaceIfPromoted (pprWithCommas pprIfaceType args'))

    NotPromoted
      |  ConstraintTuple <- sort
      ,  IA_Nil <- args
      -> maybeParen ctxt_prec sigPrec $
         text "() :: Constraint"

      | otherwise
      ->   -- drop the RuntimeRep vars.
           -- See Note [Unboxed tuple RuntimeRep vars] in TyCon
         let tys   = appArgsIfaceTypes args
             args' = case sort of
                       UnboxedTuple -> drop (length tys `div` 2) tys
                       _            -> tys
         in
         ppr_tuple_app args' $
         pprPromotionQuoteI promoted <>
         tupleParens sort (pprWithCommas pprIfaceType args')
  where
    ppr_tuple_app :: [IfaceType] -> SDoc -> SDoc
    ppr_tuple_app args_wo_runtime_reps ppr_args_w_parens
        -- Special-case unary boxed tuples so that they are pretty-printed as
        -- `Unit x`, not `(x)`
      | [_] <- args_wo_runtime_reps
      , BoxedTuple <- sort
      = let unit_tc_info = IfaceTyConInfo promoted IfaceNormalTyCon
            unit_tc = IfaceTyCon (tupleTyConName sort 1) unit_tc_info in
        pprPrecIfaceType ctxt_prec $ IfaceTyConApp unit_tc args
      | otherwise
      = ppr_args_w_parens

pprIfaceTyLit :: IfaceTyLit -> SDoc
pprIfaceTyLit (IfaceNumTyLit n) = integer n
pprIfaceTyLit (IfaceStrTyLit n) = text (show n)

pprIfaceCoercion, pprParendIfaceCoercion :: IfaceCoercion -> SDoc
pprIfaceCoercion = ppr_co topPrec
pprParendIfaceCoercion = ppr_co appPrec

ppr_co :: PprPrec -> IfaceCoercion -> SDoc
ppr_co _         (IfaceReflCo ty) = angleBrackets (ppr ty) <> ppr_role Nominal
ppr_co _         (IfaceGReflCo r ty IfaceMRefl)
  = angleBrackets (ppr ty) <> ppr_role r
ppr_co ctxt_prec (IfaceGReflCo r ty (IfaceMCo co))
  = ppr_special_co ctxt_prec
    (text "GRefl" <+> ppr r <+> pprParendIfaceType ty) [co]
ppr_co ctxt_prec (IfaceFunCo r co1 co2)
  = maybeParen ctxt_prec funPrec $
    sep (ppr_co funPrec co1 : ppr_fun_tail co2)
  where
    ppr_fun_tail (IfaceFunCo r co1 co2)
      = (arrow <> ppr_role r <+> ppr_co funPrec co1) : ppr_fun_tail co2
    ppr_fun_tail other_co
      = [arrow <> ppr_role r <+> pprIfaceCoercion other_co]

ppr_co _         (IfaceTyConAppCo r tc cos)
  = parens (pprIfaceCoTcApp topPrec tc cos) <> ppr_role r
ppr_co ctxt_prec (IfaceAppCo co1 co2)
  = maybeParen ctxt_prec appPrec $
    ppr_co funPrec co1 <+> pprParendIfaceCoercion co2
ppr_co ctxt_prec co@(IfaceForAllCo {})
  = maybeParen ctxt_prec funPrec $
    pprIfaceForAllCoPart tvs (pprIfaceCoercion inner_co)
  where
    (tvs, inner_co) = split_co co

    split_co (IfaceForAllCo (IfaceTvBndr (name, _)) kind_co co')
      = let (tvs, co'') = split_co co' in ((name,kind_co):tvs,co'')
    split_co (IfaceForAllCo (IfaceIdBndr (name, _)) kind_co co')
      = let (tvs, co'') = split_co co' in ((name,kind_co):tvs,co'')
    split_co co' = ([], co')

-- Why these three? See Note [TcTyVars in IfaceType]
ppr_co _ (IfaceFreeCoVar covar) = ppr covar
ppr_co _ (IfaceCoVarCo covar)   = ppr covar
ppr_co _ (IfaceHoleCo covar)    = braces (ppr covar)

ppr_co ctxt_prec (IfaceUnivCo IfaceUnsafeCoerceProv r ty1 ty2)
  = maybeParen ctxt_prec appPrec $
    text "UnsafeCo" <+> ppr r <+>
    pprParendIfaceType ty1 <+> pprParendIfaceType ty2

ppr_co _ (IfaceUnivCo prov role ty1 ty2)
  = text "Univ" <> (parens $
      sep [ ppr role <+> pprIfaceUnivCoProv prov
          , dcolon <+>  ppr ty1 <> comma <+> ppr ty2 ])

ppr_co ctxt_prec (IfaceInstCo co ty)
  = maybeParen ctxt_prec appPrec $
    text "Inst" <+> pprParendIfaceCoercion co
                        <+> pprParendIfaceCoercion ty

ppr_co ctxt_prec (IfaceAxiomRuleCo tc cos)
  = maybeParen ctxt_prec appPrec $ ppr tc <+> parens (interpp'SP cos)

ppr_co ctxt_prec (IfaceAxiomInstCo n i cos)
  = ppr_special_co ctxt_prec (ppr n <> brackets (ppr i)) cos
ppr_co ctxt_prec (IfaceSymCo co)
  = ppr_special_co ctxt_prec (text "Sym") [co]
ppr_co ctxt_prec (IfaceTransCo co1 co2)
  = maybeParen ctxt_prec opPrec $
    ppr_co opPrec co1 <+> semi <+> ppr_co opPrec co2
ppr_co ctxt_prec (IfaceNthCo d co)
  = ppr_special_co ctxt_prec (text "Nth:" <> int d) [co]
ppr_co ctxt_prec (IfaceLRCo lr co)
  = ppr_special_co ctxt_prec (ppr lr) [co]
ppr_co ctxt_prec (IfaceSubCo co)
  = ppr_special_co ctxt_prec (text "Sub") [co]
ppr_co ctxt_prec (IfaceKindCo co)
  = ppr_special_co ctxt_prec (text "Kind") [co]

ppr_special_co :: PprPrec -> SDoc -> [IfaceCoercion] -> SDoc
ppr_special_co ctxt_prec doc cos
  = maybeParen ctxt_prec appPrec
               (sep [doc, nest 4 (sep (map pprParendIfaceCoercion cos))])

ppr_role :: Role -> SDoc
ppr_role r = underscore <> pp_role
  where pp_role = case r of
                    Nominal          -> char 'N'
                    Representational -> char 'R'
                    Phantom          -> char 'P'

------------------
pprIfaceUnivCoProv :: IfaceUnivCoProv -> SDoc
pprIfaceUnivCoProv IfaceUnsafeCoerceProv
  = text "unsafe"
pprIfaceUnivCoProv (IfacePhantomProv co)
  = text "phantom" <+> pprParendIfaceCoercion co
pprIfaceUnivCoProv (IfaceProofIrrelProv co)
  = text "irrel" <+> pprParendIfaceCoercion co
pprIfaceUnivCoProv (IfacePluginProv s)
  = text "plugin" <+> doubleQuotes (text s)

-------------------
instance Outputable IfaceTyCon where
  ppr tc = pprPromotionQuote tc <> ppr (ifaceTyConName tc)

pprPromotionQuote :: IfaceTyCon -> SDoc
pprPromotionQuote tc =
    pprPromotionQuoteI $ ifaceTyConIsPromoted $ ifaceTyConInfo tc

pprPromotionQuoteI  :: PromotionFlag -> SDoc
pprPromotionQuoteI NotPromoted = empty
pprPromotionQuoteI IsPromoted    = char '\''

instance Outputable IfaceCoercion where
  ppr = pprIfaceCoercion

instance Binary IfaceTyCon where
   put (IfaceTyCon n i) = put n >> put i
   get = IfaceTyCon <$> get <*> get

instance Binary IfaceTyConSort where
   put IfaceNormalTyCon             = putByte 0
   put (IfaceTupleTyCon arity sort) = putByte 1 >> put arity >> put sort
   put (IfaceSumTyCon arity)        = putByte 2 >> put arity
   put IfaceEqualityTyCon           = putByte 3

   get = do
       n <- getByte
       case n of
         0 -> return IfaceNormalTyCon
         1 -> IfaceTupleTyCon <$> get <*> get
         2 -> IfaceSumTyCon <$> get
         _ -> return IfaceEqualityTyCon

instance Binary IfaceTyConInfo where
   put (IfaceTyConInfo i s) = put i >> put s

   get = IfaceTyConInfo <$> get <*> get

instance Outputable IfaceTyLit where
  ppr = pprIfaceTyLit

instance Binary IfaceTyLit where
  put (IfaceNumTyLit n) = putByte 1 >> put n
  put (IfaceStrTyLit n) = putByte 2 >> put n

  get =
    do tag <- getByte
       case tag of
         1 -> IfaceNumTyLit <$> get
         2 -> IfaceStrTyLit <$> get
         _ -> panic ("get IfaceTyLit " ++ show tag)

instance Binary IfaceAppArgs where
  put tk =
    case tk of
      IA_Arg t a ts -> putByte 0 >> put t >> put a >> put ts
      IA_Nil        -> putByte 1

  get =
    do c <- getByte
       case c of
         0 -> do
           t  <- get
           a  <- get
           ts <- get
           return $! IA_Arg t a ts
         1 -> return IA_Nil
         _ -> panic ("get IfaceAppArgs " ++ show c)

-------------------

-- Some notes about printing contexts
--
-- In the event that we are printing a singleton context (e.g. @Eq a@) we can
-- omit parentheses. However, we must take care to set the precedence correctly
-- to opPrec, since something like @a :~: b@ must be parenthesized (see
-- #9658).
--
-- When printing a larger context we use 'fsep' instead of 'sep' so that
-- the context doesn't get displayed as a giant column. Rather than,
--  instance (Eq a,
--            Eq b,
--            Eq c,
--            Eq d,
--            Eq e,
--            Eq f,
--            Eq g,
--            Eq h,
--            Eq i,
--            Eq j,
--            Eq k,
--            Eq l) =>
--           Eq (a, b, c, d, e, f, g, h, i, j, k, l)
--
-- we want
--
--  instance (Eq a, Eq b, Eq c, Eq d, Eq e, Eq f, Eq g, Eq h, Eq i,
--            Eq j, Eq k, Eq l) =>
--           Eq (a, b, c, d, e, f, g, h, i, j, k, l)



-- | Prints "(C a, D b) =>", including the arrow.
-- Used when we want to print a context in a type, so we
-- use 'funPrec' to decide whether to parenthesise a singleton
-- predicate; e.g.   Num a => a -> a
pprIfaceContextArr :: [IfacePredType] -> SDoc
pprIfaceContextArr []     = empty
pprIfaceContextArr [pred] = ppr_ty funPrec pred <+> darrow
pprIfaceContextArr preds  = ppr_parend_preds preds <+> darrow

-- | Prints a context or @()@ if empty
-- You give it the context precedence
pprIfaceContext :: PprPrec -> [IfacePredType] -> SDoc
pprIfaceContext _    []     = text "()"
pprIfaceContext prec [pred] = ppr_ty prec pred
pprIfaceContext _    preds  = ppr_parend_preds preds

ppr_parend_preds :: [IfacePredType] -> SDoc
ppr_parend_preds preds = parens (fsep (punctuate comma (map ppr preds)))

instance Binary IfaceType where
    put (IfaceFreeTyVar tv)
       = pprPanic "Can't serialise IfaceFreeTyVar" (ppr tv)

    put (IfaceForAllTy aa ab) = do
            putByte 0
            put aa
            put ab
    put (IfaceTyVar ad) = do
            putByte 1
            put ad
    put (IfaceAppTy ae af) = do
            putByte 2
            put ae
            put af
    put (IfaceFunTy af ag ah) = do
            putByte 3
            put af
            put ag
            put ah
    put (IfaceTyConApp tc tys)
      = do { putByte 5; put tc; put tys }
    put (IfaceCastTy a b)
      = do { putByte 6; put a; put b }
    put (IfaceCoercionTy a)
      = do { putByte 7; put a }
    put (IfaceTupleTy s i tys)
      = do { putByte 8; put s; put i; put tys }
    put (IfaceLitTy n)
      = do { putByte 9; put n }

    get = do
            h <- getByte
            case h of
              0 -> do aa <- get
                      ab <- get
                      return (IfaceForAllTy aa ab)
              1 -> do ad <- get
                      return (IfaceTyVar ad)
              2 -> do ae <- get
                      af <- get
                      return (IfaceAppTy ae af)
              3 -> do af <- get
                      ag <- get
                      ah <- get
                      return (IfaceFunTy af ag ah)
              5 -> do { tc <- get; tys <- get
                      ; return (IfaceTyConApp tc tys) }
              6 -> do { a <- get; b <- get
                      ; return (IfaceCastTy a b) }
              7 -> do { a <- get
                      ; return (IfaceCoercionTy a) }

              8 -> do { s <- get; i <- get; tys <- get
                      ; return (IfaceTupleTy s i tys) }
              _  -> do n <- get
                       return (IfaceLitTy n)

instance Binary IfaceMCoercion where
  put IfaceMRefl = do
      putByte 1
  put (IfaceMCo co) = do
      putByte 2
      put co

  get = do
    tag <- getByte
    case tag of
         1 -> return IfaceMRefl
         2 -> do a <- get
                 return $ IfaceMCo a
         _ -> panic ("get IfaceMCoercion " ++ show tag)

instance Binary IfaceCoercion where
  put (IfaceReflCo a) = do
      putByte 1
      put a
  put (IfaceGReflCo a b c) = do
      putByte 2
      put a
      put b
      put c
  put (IfaceFunCo a b c) = do
      putByte 3
      put a
      put b
      put c
  put (IfaceTyConAppCo a b c) = do
      putByte 4
      put a
      put b
      put c
  put (IfaceAppCo a b) = do
      putByte 5
      put a
      put b
  put (IfaceForAllCo a b c) = do
      putByte 6
      put a
      put b
      put c
  put (IfaceCoVarCo a) = do
      putByte 7
      put a
  put (IfaceAxiomInstCo a b c) = do
      putByte 8
      put a
      put b
      put c
  put (IfaceUnivCo a b c d) = do
      putByte 9
      put a
      put b
      put c
      put d
  put (IfaceSymCo a) = do
      putByte 10
      put a
  put (IfaceTransCo a b) = do
      putByte 11
      put a
      put b
  put (IfaceNthCo a b) = do
      putByte 12
      put a
      put b
  put (IfaceLRCo a b) = do
      putByte 13
      put a
      put b
  put (IfaceInstCo a b) = do
      putByte 14
      put a
      put b
  put (IfaceKindCo a) = do
      putByte 15
      put a
  put (IfaceSubCo a) = do
      putByte 16
      put a
  put (IfaceAxiomRuleCo a b) = do
      putByte 17
      put a
      put b
  put (IfaceFreeCoVar cv)
      = pprPanic "Can't serialise IfaceFreeCoVar" (ppr cv)
  put (IfaceHoleCo cv)
      = pprPanic "Can't serialise IfaceHoleCo" (ppr cv)
          -- See Note [Holes in IfaceCoercion]

  get = do
      tag <- getByte
      case tag of
           1 -> do a <- get
                   return $ IfaceReflCo a
           2 -> do a <- get
                   b <- get
                   c <- get
                   return $ IfaceGReflCo a b c
           3 -> do a <- get
                   b <- get
                   c <- get
                   return $ IfaceFunCo a b c
           4 -> do a <- get
                   b <- get
                   c <- get
                   return $ IfaceTyConAppCo a b c
           5 -> do a <- get
                   b <- get
                   return $ IfaceAppCo a b
           6 -> do a <- get
                   b <- get
                   c <- get
                   return $ IfaceForAllCo a b c
           7 -> do a <- get
                   return $ IfaceCoVarCo a
           8 -> do a <- get
                   b <- get
                   c <- get
                   return $ IfaceAxiomInstCo a b c
           9 -> do a <- get
                   b <- get
                   c <- get
                   d <- get
                   return $ IfaceUnivCo a b c d
           10-> do a <- get
                   return $ IfaceSymCo a
           11-> do a <- get
                   b <- get
                   return $ IfaceTransCo a b
           12-> do a <- get
                   b <- get
                   return $ IfaceNthCo a b
           13-> do a <- get
                   b <- get
                   return $ IfaceLRCo a b
           14-> do a <- get
                   b <- get
                   return $ IfaceInstCo a b
           15-> do a <- get
                   return $ IfaceKindCo a
           16-> do a <- get
                   return $ IfaceSubCo a
           17-> do a <- get
                   b <- get
                   return $ IfaceAxiomRuleCo a b
           _ -> panic ("get IfaceCoercion " ++ show tag)

instance Binary IfaceUnivCoProv where
  put IfaceUnsafeCoerceProv = putByte 1
  put (IfacePhantomProv a) = do
          putByte 2
          put a
  put (IfaceProofIrrelProv a) = do
          putByte 3
          put a
  put (IfacePluginProv a) = do
          putByte 4
          put a

  get = do
      tag <- getByte
      case tag of
           1 -> return $ IfaceUnsafeCoerceProv
           2 -> do a <- get
                   return $ IfacePhantomProv a
           3 -> do a <- get
                   return $ IfaceProofIrrelProv a
           4 -> do a <- get
                   return $ IfacePluginProv a
           _ -> panic ("get IfaceUnivCoProv " ++ show tag)


instance Binary (DefMethSpec IfaceType) where
    put VanillaDM     = putByte 0
    put (GenericDM t) = putByte 1 >> put t
    get = do
            h <- getByte
            case h of
              0 -> return VanillaDM
              _ -> do { t <- get; return (GenericDM t) }

instance NFData IfaceType where
  rnf = \case
    IfaceFreeTyVar f1 -> f1 `seq` ()
    IfaceTyVar f1 -> rnf f1
    IfaceLitTy f1 -> rnf f1
    IfaceAppTy f1 f2 -> rnf f1 `seq` rnf f2
    IfaceFunTy f1 f2 f3 -> f1 `seq` rnf f2 `seq` rnf f3
    IfaceForAllTy f1 f2 -> f1 `seq` rnf f2
    IfaceTyConApp f1 f2 -> rnf f1 `seq` rnf f2
    IfaceCastTy f1 f2 -> rnf f1 `seq` rnf f2
    IfaceCoercionTy f1 -> rnf f1
    IfaceTupleTy f1 f2 f3 -> f1 `seq` f2 `seq` rnf f3

instance NFData IfaceTyLit where
  rnf = \case
    IfaceNumTyLit f1 -> rnf f1
    IfaceStrTyLit f1 -> rnf f1

instance NFData IfaceCoercion where
  rnf = \case
    IfaceReflCo f1 -> rnf f1
    IfaceGReflCo f1 f2 f3 -> f1 `seq` rnf f2 `seq` rnf f3
    IfaceFunCo f1 f2 f3 -> f1 `seq` rnf f2 `seq` rnf f3
    IfaceTyConAppCo f1 f2 f3 -> f1 `seq` rnf f2 `seq` rnf f3
    IfaceAppCo f1 f2 -> rnf f1 `seq` rnf f2
    IfaceForAllCo f1 f2 f3 -> rnf f1 `seq` rnf f2 `seq` rnf f3
    IfaceCoVarCo f1 -> rnf f1
    IfaceAxiomInstCo f1 f2 f3 -> rnf f1 `seq` rnf f2 `seq` rnf f3
    IfaceAxiomRuleCo f1 f2 -> rnf f1 `seq` rnf f2
    IfaceUnivCo f1 f2 f3 f4 -> rnf f1 `seq` f2 `seq` rnf f3 `seq` rnf f4
    IfaceSymCo f1 -> rnf f1
    IfaceTransCo f1 f2 -> rnf f1 `seq` rnf f2
    IfaceNthCo f1 f2 -> rnf f1 `seq` rnf f2
    IfaceLRCo f1 f2 -> f1 `seq` rnf f2
    IfaceInstCo f1 f2 -> rnf f1 `seq` rnf f2
    IfaceKindCo f1 -> rnf f1
    IfaceSubCo f1 -> rnf f1
    IfaceFreeCoVar f1 -> f1 `seq` ()
    IfaceHoleCo f1 -> f1 `seq` ()

instance NFData IfaceUnivCoProv where
  rnf x = seq x ()

instance NFData IfaceMCoercion where
  rnf x = seq x ()

instance NFData IfaceOneShot where
  rnf x = seq x ()

instance NFData IfaceTyConSort where
  rnf = \case
    IfaceNormalTyCon -> ()
    IfaceTupleTyCon arity sort -> rnf arity `seq` sort `seq` ()
    IfaceSumTyCon arity -> rnf arity
    IfaceEqualityTyCon -> ()

instance NFData IfaceTyConInfo where
  rnf (IfaceTyConInfo f s) = f `seq` rnf s

instance NFData IfaceTyCon where
  rnf (IfaceTyCon nm info) = rnf nm `seq` rnf info

instance NFData IfaceBndr where
  rnf = \case
    IfaceIdBndr id_bndr -> rnf id_bndr
    IfaceTvBndr tv_bndr -> rnf tv_bndr

instance NFData IfaceAppArgs where
  rnf = \case
    IA_Nil -> ()
    IA_Arg f1 f2 f3 -> rnf f1 `seq` f2 `seq` rnf f3
