%
% (c) The AQUA Project, Glasgow University, 1994-1998
%

\section[TysPrim]{Wired-in knowledge about primitive types}

\begin{code}
{-# LANGUAGE CPP #-}

-- | This module defines TyCons that can't be expressed in Haskell.
--   They are all, therefore, wired-in TyCons.  C.f module TysWiredIn
module TysPrim(
        mkPrimTyConName, -- For implicit parameters in TysWiredIn only

        tyVarList, alphaTyVars, alphaTyVar, betaTyVar, gammaTyVar, deltaTyVar,
        alphaTys, alphaTy, betaTy, gammaTy, deltaTy,
        levity1TyVar, levity2TyVar, levity1Ty, levity2Ty,
        openAlphaTy, openBetaTy, openAlphaTyVar, openBetaTyVar,
        kKiVar,

        -- Kind constructors...
        liftedTypeKindTyCon,
        tYPETyCon, unliftedTypeKindTyCon, constraintKindTyCon,

        liftedTypeKindTyConName,
        tYPETyConName, unliftedTypeKindTyConName,
        constraintKindTyConName,

        -- Kinds
        liftedTypeKind, unliftedTypeKind, constraintKind,
        tYPE,
        mkArrowKind, mkArrowKinds,

        funTyCon, funTyConName,
        primTyCons, primAxioms,

        charPrimTyCon,          charPrimTy,
        intPrimTyCon,           intPrimTy,
        wordPrimTyCon,          wordPrimTy,
        addrPrimTyCon,          addrPrimTy,
        floatPrimTyCon,         floatPrimTy,
        doublePrimTyCon,        doublePrimTy,

        voidPrimTyCon,          voidPrimTy,
        statePrimTyCon,         mkStatePrimTy,
        realWorldTyCon,         realWorldTy, realWorldStatePrimTy,

        proxyPrimTyCon,         mkProxyPrimTy,

        arrayPrimTyCon, mkArrayPrimTy,
        byteArrayPrimTyCon,     byteArrayPrimTy,
        arrayArrayPrimTyCon, mkArrayArrayPrimTy,
        smallArrayPrimTyCon, mkSmallArrayPrimTy,
        mutableArrayPrimTyCon, mkMutableArrayPrimTy,
        mutableByteArrayPrimTyCon, mkMutableByteArrayPrimTy,
        mutableArrayArrayPrimTyCon, mkMutableArrayArrayPrimTy,
        smallMutableArrayPrimTyCon, mkSmallMutableArrayPrimTy,
        mutVarPrimTyCon, mkMutVarPrimTy,

        mVarPrimTyCon,                  mkMVarPrimTy,
        tVarPrimTyCon,                  mkTVarPrimTy,
        stablePtrPrimTyCon,             mkStablePtrPrimTy,
        stableNamePrimTyCon,            mkStableNamePrimTy,
        bcoPrimTyCon,                   bcoPrimTy,
        weakPrimTyCon,                  mkWeakPrimTy,
        threadIdPrimTyCon,              threadIdPrimTy,

        int32PrimTyCon,         int32PrimTy,
        word32PrimTyCon,        word32PrimTy,

        int64PrimTyCon,         int64PrimTy,
        word64PrimTyCon,        word64PrimTy,

        eqPrimTyCon,            -- ty1 ~# ty2
        eqReprPrimTyCon,        -- ty1 ~R# ty2  (at role Representational)

        -- * Any
        anyTy, anyTyCon, anyTypeOfKind,

        -- * SIMD
#include "primop-vector-tys-exports.hs-incl"
  ) where

#include "HsVersions.h"

import {-# SOURCE #-} TysWiredIn ( levityTy, liftedDataConTy, unliftedDataConTy )

import Var		( TyVar, KindVar, mkTyVar )
import Name		( Name, BuiltInSyntax(..), mkInternalName, mkWiredInName )
import OccName          ( mkTyVarOccFS, mkTcOccFS )
import TyCon
import SrcLoc
import Unique           ( mkAlphaTyVarUnique )
import PrelNames
import FastString
import TyCoRep

import Data.Char
\end{code}

%************************************************************************
%*                                                                      *
\subsection{Primitive type constructors}
%*                                                                      *
%************************************************************************

\begin{code}
primTyCons :: [TyCon]
primTyCons
  = [ addrPrimTyCon
    , arrayPrimTyCon
    , byteArrayPrimTyCon
    , arrayArrayPrimTyCon
    , smallArrayPrimTyCon
    , charPrimTyCon
    , doublePrimTyCon
    , floatPrimTyCon
    , intPrimTyCon
    , int32PrimTyCon
    , int64PrimTyCon
    , bcoPrimTyCon
    , weakPrimTyCon
    , mutableArrayPrimTyCon
    , mutableByteArrayPrimTyCon
    , mutableArrayArrayPrimTyCon
    , smallMutableArrayPrimTyCon
    , mVarPrimTyCon
    , tVarPrimTyCon
    , mutVarPrimTyCon
    , realWorldTyCon
    , stablePtrPrimTyCon
    , stableNamePrimTyCon
    , statePrimTyCon
    , voidPrimTyCon
    , proxyPrimTyCon
    , threadIdPrimTyCon
    , wordPrimTyCon
    , word32PrimTyCon
    , word64PrimTyCon
    , anyTyCon
    , eqPrimTyCon
    , eqReprPrimTyCon

    , liftedTypeKindTyCon
    , unliftedTypeKindTyCon
    , tYPETyCon
    , constraintKindTyCon
    , castTyCon

#include "primop-vector-tycons.hs-incl"
    ]

primAxioms :: [CoAxiom Branched]
primAxioms = [castAxiom]

mkPrimTc :: FastString -> Unique -> TyCon -> Name
mkPrimTc fs unique tycon
  = mkWiredInName gHC_PRIM (mkTcOccFS fs)
                  unique
                  (ATyCon tycon)        -- Relevant TyCon
                  UserSyntax

mkBuiltInPrimTc :: FastString -> Unique -> TyCon -> Name
mkBuiltInPrimTc fs unique tycon
  = mkWiredInName gHC_PRIM (mkTcOccFS fs)
                  unique
                  (ATyCon tycon)        -- Relevant TyCon
                  BuiltInSyntax


charPrimTyConName, intPrimTyConName, int32PrimTyConName, int64PrimTyConName, wordPrimTyConName, word32PrimTyConName, word64PrimTyConName, addrPrimTyConName, floatPrimTyConName, doublePrimTyConName, statePrimTyConName, proxyPrimTyConName, realWorldTyConName, arrayPrimTyConName, arrayArrayPrimTyConName, smallArrayPrimTyConName, byteArrayPrimTyConName, mutableArrayPrimTyConName, mutableByteArrayPrimTyConName, mutableArrayArrayPrimTyConName, smallMutableArrayPrimTyConName, mutVarPrimTyConName, mVarPrimTyConName, tVarPrimTyConName, stablePtrPrimTyConName, stableNamePrimTyConName, bcoPrimTyConName, weakPrimTyConName, threadIdPrimTyConName, eqPrimTyConName, eqReprPrimTyConName, voidPrimTyConName :: Name
charPrimTyConName             = mkPrimTc (fsLit "Char#") charPrimTyConKey charPrimTyCon
intPrimTyConName              = mkPrimTc (fsLit "Int#") intPrimTyConKey  intPrimTyCon
int32PrimTyConName            = mkPrimTc (fsLit "Int32#") int32PrimTyConKey int32PrimTyCon
int64PrimTyConName            = mkPrimTc (fsLit "Int64#") int64PrimTyConKey int64PrimTyCon
wordPrimTyConName             = mkPrimTc (fsLit "Word#") wordPrimTyConKey wordPrimTyCon
word32PrimTyConName           = mkPrimTc (fsLit "Word32#") word32PrimTyConKey word32PrimTyCon
word64PrimTyConName           = mkPrimTc (fsLit "Word64#") word64PrimTyConKey word64PrimTyCon
addrPrimTyConName             = mkPrimTc (fsLit "Addr#") addrPrimTyConKey addrPrimTyCon
floatPrimTyConName            = mkPrimTc (fsLit "Float#") floatPrimTyConKey floatPrimTyCon
doublePrimTyConName           = mkPrimTc (fsLit "Double#") doublePrimTyConKey doublePrimTyCon
statePrimTyConName            = mkPrimTc (fsLit "State#") statePrimTyConKey statePrimTyCon
voidPrimTyConName             = mkPrimTc (fsLit "Void#") voidPrimTyConKey voidPrimTyCon
proxyPrimTyConName            = mkPrimTc (fsLit "Proxy#") proxyPrimTyConKey proxyPrimTyCon
eqPrimTyConName               = mkPrimTc (fsLit "~#") eqPrimTyConKey eqPrimTyCon
eqReprPrimTyConName           = mkBuiltInPrimTc (fsLit "~R#") eqReprPrimTyConKey eqReprPrimTyCon
realWorldTyConName            = mkPrimTc (fsLit "RealWorld") realWorldTyConKey realWorldTyCon
arrayPrimTyConName            = mkPrimTc (fsLit "Array#") arrayPrimTyConKey arrayPrimTyCon
byteArrayPrimTyConName        = mkPrimTc (fsLit "ByteArray#") byteArrayPrimTyConKey byteArrayPrimTyCon
arrayArrayPrimTyConName           = mkPrimTc (fsLit "ArrayArray#") arrayArrayPrimTyConKey arrayArrayPrimTyCon
smallArrayPrimTyConName       = mkPrimTc (fsLit "SmallArray#") smallArrayPrimTyConKey smallArrayPrimTyCon
mutableArrayPrimTyConName     = mkPrimTc (fsLit "MutableArray#") mutableArrayPrimTyConKey mutableArrayPrimTyCon
mutableByteArrayPrimTyConName = mkPrimTc (fsLit "MutableByteArray#") mutableByteArrayPrimTyConKey mutableByteArrayPrimTyCon
mutableArrayArrayPrimTyConName= mkPrimTc (fsLit "MutableArrayArray#") mutableArrayArrayPrimTyConKey mutableArrayArrayPrimTyCon
smallMutableArrayPrimTyConName= mkPrimTc (fsLit "SmallMutableArray#") smallMutableArrayPrimTyConKey smallMutableArrayPrimTyCon
mutVarPrimTyConName           = mkPrimTc (fsLit "MutVar#") mutVarPrimTyConKey mutVarPrimTyCon
mVarPrimTyConName             = mkPrimTc (fsLit "MVar#") mVarPrimTyConKey mVarPrimTyCon
tVarPrimTyConName             = mkPrimTc (fsLit "TVar#") tVarPrimTyConKey tVarPrimTyCon
stablePtrPrimTyConName        = mkPrimTc (fsLit "StablePtr#") stablePtrPrimTyConKey stablePtrPrimTyCon
stableNamePrimTyConName       = mkPrimTc (fsLit "StableName#") stableNamePrimTyConKey stableNamePrimTyCon
bcoPrimTyConName              = mkPrimTc (fsLit "BCO#") bcoPrimTyConKey bcoPrimTyCon
weakPrimTyConName             = mkPrimTc (fsLit "Weak#") weakPrimTyConKey weakPrimTyCon
threadIdPrimTyConName         = mkPrimTc (fsLit "ThreadId#") threadIdPrimTyConKey threadIdPrimTyCon
\end{code}

%************************************************************************
%*                                                                      *
\subsection{Support code}
%*                                                                      *
%************************************************************************

alphaTyVars is a list of type variables for use in templates:
        ["a", "b", ..., "z", "t1", "t2", ... ]

\begin{code}
tyVarList :: Kind -> [TyVar]
tyVarList kind = [ mkTyVar (mkInternalName (mkAlphaTyVarUnique u)
                                           (mkTyVarOccFS (mkFastString name))
                                           noSrcSpan) kind
                 | u <- [2..],
                   let name | c <= 'z'  = [c]
                            | otherwise = 't':show u
                            where c = chr (u-2 + ord 'a')
                 ]

alphaTyVars :: [TyVar]
alphaTyVars = tyVarList liftedTypeKind

alphaTyVar, betaTyVar, gammaTyVar, deltaTyVar :: TyVar
(alphaTyVar:betaTyVar:gammaTyVar:deltaTyVar:_) = alphaTyVars

alphaTys :: [Type]
alphaTys = mkOnlyTyVarTys alphaTyVars
alphaTy, betaTy, gammaTy, deltaTy :: Type
(alphaTy:betaTy:gammaTy:deltaTy:_) = alphaTys

levity1TyVar, levity2TyVar :: TyVar
(levity1TyVar : levity2TyVar : _) = drop 21 (tyVarList levityTy)  -- selects 'v','w'

levity1Ty, levity2Ty :: Type
levity1Ty = mkOnlyTyVarTy levity1TyVar
levity2Ty = mkOnlyTyVarTy levity2TyVar

openAlphaTyVar, openBetaTyVar :: TyVar
openAlphaTyVar = tyVarList (tYPE levity1Ty) !! 0
openBetaTyVar  = tyVarList (tYPE levity2Ty) !! 1

openAlphaTy, openBetaTy :: Type
openAlphaTy = mkOnlyTyVarTy openAlphaTyVar
openBetaTy  = mkOnlyTyVarTy openBetaTyVar

kKiVar :: KindVar
kKiVar = (tyVarList liftedTypeKind) !! 10
  -- the 10 selects the 11th letter in the alphabet: 'k'

\end{code}


%************************************************************************
%*                                                                      *
                FunTyCon
%*                                                                      *
%************************************************************************

\begin{code}
funTyConName :: Name
funTyConName = mkPrimTyConName (fsLit "(->)") funTyConKey funTyCon

funTyCon :: TyCon
funTyCon = mkFunTyCon funTyConName $
           mkArrowKinds [liftedTypeKind, liftedTypeKind] liftedTypeKind
        -- You might think that (->) should have type (?? -> ? -> *), and you'd be right
        -- But if we do that we get kind errors when saying
        --      instance Control.Arrow (->)
        -- because the expected kind is (*->*->*).  The trouble is that the
        -- expected/actual stuff in the unifier does not go contra-variant, whereas
        -- the kind sub-typing does.  Sigh.  It really only matters if you use (->) in
        -- a prefix way, thus:  (->) Int# Int#.  And this is unusual.
        -- because they are never in scope in the source

-- One step to remove subkinding.
-- (->) :: * -> * -> *
-- but we should have (and want) the following typing rule for fully applied arrows
--      Gamma |- tau   :: k1    k1 in {*, #}
--      Gamma |- sigma :: k2    k2 in {*, #, (#)}
--      -----------------------------------------
--      Gamma |- tau -> sigma :: *
-- Currently we have the following rule which achieves more or less the same effect
--      Gamma |- tau   :: ??
--      Gamma |- sigma :: ?
--      --------------------------
--      Gamma |- tau -> sigma :: *
-- In the end we don't want subkinding at all.
\end{code}


%************************************************************************
%*                                                                      *
                Kinds
%*                                                                      *
%************************************************************************

Note [TYPE]
~~~~~~~~~~~
There are a few places where we wish to be able to deal interchangeably
with kind * and kind #. unsafeCoerce#, error, and (->) are some of these
places. The way we do this is to use kind polymorphism.

We have (levityTyCon, liftedDataCon, unliftedDataCon)

    data Levity = Lifted | Unlifted

and a magical constant (tYPETyCon)

    TYPE :: Levity -> TYPE Lifted

We then have synonyms (liftedTypeKindTyCon, unliftedTypeKindTyCon)

    type * = TYPE Lifted
    type # = TYPE Unlifted

So, for example, we get

    unsafeCoerce# :: forall (v1 :: Levity) (v2 :: Levity)
                            (a :: TYPE v1) (b :: TYPE v2). a -> b

This replaces the old sub-kinding machinery. We call variables `a` and `b`
above "sort-polymorphic".

\begin{code}
liftedTypeKindTyCon,
      tYPETyCon, unliftedTypeKindTyCon,
      constraintKindTyCon, castTyCon
   :: TyCon
liftedTypeKindTyConName,
      tYPETyConName, unliftedTypeKindTyConName,
      constraintKindTyConName, castTyConName, castAxiomName
   :: Name

constraintKindTyCon   = mkKindTyCon constraintKindTyConName   liftedTypeKind []
tYPETyCon = mkKindTyCon tYPETyConName
                        (ForAllTy (Anon levityTy) liftedTypeKind)
                        [Nominal]

   -- See Note [TYPE]
liftedTypeKindTyCon   = mkSynTyCon liftedTypeKindTyConName
                                   liftedTypeKind
                                   [] []
                                   (SynonymTyCon (tYPE liftedDataConTy))
                                   NoParentTyCon
unliftedTypeKindTyCon = mkSynTyCon unliftedTypeKindTyConName
                                   liftedTypeKind
                                   [] []
                                   (SynonymTyCon (tYPE unliftedDataConTy))
                                   NoParentTyCon

-- type family Cast (t :: k1) (g :: k1 ~ k2) where
--   Cast t (Eq# co) = t |> co
castTyCon = mkSynTyCon castTyConName
                       cast_kind
                       [k1, k2] [Nominal, Nominal]
                       (ClosedSynFamilyTyCon castAxiom)
                       NoParentTyCon
  where
    k1:k2:_ = tyVarList liftedTypeKind
    k1ty    = mkOnlyTyVarTy k1
    k2ty    = mkOnlyTyVarTy k2
    cast_kind = mkInvForAllTys [k1, k2] $
                mkFunTy k1ty $
                mkFunTy (mkEqPred k1ty k2ty) $
                mkOnlyTyVarTy k2

castAxiom :: CoAxiom Branched
castAxiom = mkBranchedCoAxiom castAxiomName castTyCon [cast_branch]
  where
    k1:k2:_ = tyVarList liftedTypeKind
    k1ty    = mkOnlyTyVarTy k1
    k2ty    = mkOnlyTyVarTy k2
    _:_:t:_ = tyVarList k1ty
    tty     = mkOnlyTyVarTy t
    c       = mkFreshCoVar (emptyInScopeSet `extendInScopeSetList` [k1,k2,t])
                           k1ty k2ty
    cco     = mkCoVarCo c
    cast_branch = mkCoAxBranch [k1,k2,t,c]
                               [k1ty, k2ty, tty, mkTyConApp (promoteDataCon eqBoxDataCon)
                                                            [mkCoercionTy cco]]
                               (mkCastTy tty cco)
                               noSrcLoc

--------------------------
-- ... and now their names

-- If you edit these, you may need to update the GHC formalism
-- See Note [GHC Formalism] in coreSyn/CoreLint.lhs
liftedTypeKindTyConName   = mkPrimTyConName (fsLit "*") liftedTypeKindTyConKey liftedTypeKindTyCon
tYPETyConName             = mkPrimTyConName (fsLit "TYPE") tYPETyConKey tYPETyCon
unliftedTypeKindTyConName = mkPrimTyConName (fsLit "#") unliftedTypeKindTyConKey unliftedTypeKindTyCon
constraintKindTyConName   = mkPrimTyConName (fsLit "Constraint") constraintKindTyConKey constraintKindTyCon
castTyConName             = mkPrimTyConName (fsLit "Cast") castTyConKey castTyCon
castAxiomName             = mkWiredInName gHC_PRIM
                                          (mkTcOccFS (fsLit "axCast"))
                                          castAxiomKey
                                          (ACoAxiom castAxiom)
                                          BuiltInSyntax

mkPrimTyConName :: FastString -> Unique -> TyCon -> Name
mkPrimTyConName occ key tycon = mkWiredInName gHC_PRIM (mkTcOccFS occ)
                                              key
                                              (ATyCon tycon)
                                              BuiltInSyntax
        -- All of the super kinds and kinds are defined in Prim and use BuiltInSyntax,
        -- because they are never in scope in the source
\end{code}


\begin{code}
kindTyConType :: TyCon -> Type
kindTyConType kind = TyConApp kind []   -- mkTyConApp isn't defined yet

-- | See Note [TYPE]
liftedTypeKind, unliftedTypeKind, constraintKind :: Kind

liftedTypeKind   = kindTyConType liftedTypeKindTyCon
unliftedTypeKind = kindTyConType unliftedTypeKindTyCon
constraintKind   = kindTyConType constraintKindTyCon

-----------------------------
-- | Given a Levity, applies TYPE to it. See Note [TYPE].
tYPE :: Type -> Type
tYPE lev = TyConApp tYPETyCon [lev]

-- | Given two kinds @k1@ and @k2@, creates the 'Kind' @k1 -> k2@
mkArrowKind :: Kind -> Kind -> Kind
mkArrowKind k1 k2 = mkFunTy k1 k2

-- | Iterated application of 'mkArrowKind'
mkArrowKinds :: [Kind] -> Kind -> Kind
mkArrowKinds arg_kinds result_kind = foldr mkArrowKind result_kind arg_kinds
\end{code}

%************************************************************************
%*                                                                      *
\subsection[TysPrim-basic]{Basic primitive types (@Char#@, @Int#@, etc.)}
%*                                                                      *
%************************************************************************

\begin{code}
-- only used herein
pcPrimTyCon :: Name -> [Role] -> PrimRep -> TyCon
pcPrimTyCon name roles rep
  = mkPrimTyCon name kind roles rep
  where
    kind        = mkArrowKinds (map (const liftedTypeKind) roles) result_kind
    result_kind = unliftedTypeKind

pcPrimTyCon0 :: Name -> PrimRep -> TyCon
pcPrimTyCon0 name rep
  = mkPrimTyCon name result_kind [] rep
  where
    result_kind = unliftedTypeKind

charPrimTy :: Type
charPrimTy      = mkTyConTy charPrimTyCon
charPrimTyCon :: TyCon
charPrimTyCon   = pcPrimTyCon0 charPrimTyConName WordRep

intPrimTy :: Type
intPrimTy       = mkTyConTy intPrimTyCon
intPrimTyCon :: TyCon
intPrimTyCon    = pcPrimTyCon0 intPrimTyConName IntRep

int32PrimTy :: Type
int32PrimTy     = mkTyConTy int32PrimTyCon
int32PrimTyCon :: TyCon
int32PrimTyCon  = pcPrimTyCon0 int32PrimTyConName IntRep

int64PrimTy :: Type
int64PrimTy     = mkTyConTy int64PrimTyCon
int64PrimTyCon :: TyCon
int64PrimTyCon  = pcPrimTyCon0 int64PrimTyConName Int64Rep

wordPrimTy :: Type
wordPrimTy      = mkTyConTy wordPrimTyCon
wordPrimTyCon :: TyCon
wordPrimTyCon   = pcPrimTyCon0 wordPrimTyConName WordRep

word32PrimTy :: Type
word32PrimTy    = mkTyConTy word32PrimTyCon
word32PrimTyCon :: TyCon
word32PrimTyCon = pcPrimTyCon0 word32PrimTyConName WordRep

word64PrimTy :: Type
word64PrimTy    = mkTyConTy word64PrimTyCon
word64PrimTyCon :: TyCon
word64PrimTyCon = pcPrimTyCon0 word64PrimTyConName Word64Rep

addrPrimTy :: Type
addrPrimTy      = mkTyConTy addrPrimTyCon
addrPrimTyCon :: TyCon
addrPrimTyCon   = pcPrimTyCon0 addrPrimTyConName AddrRep

floatPrimTy     :: Type
floatPrimTy     = mkTyConTy floatPrimTyCon
floatPrimTyCon :: TyCon
floatPrimTyCon  = pcPrimTyCon0 floatPrimTyConName FloatRep

doublePrimTy :: Type
doublePrimTy    = mkTyConTy doublePrimTyCon
doublePrimTyCon :: TyCon
doublePrimTyCon = pcPrimTyCon0 doublePrimTyConName DoubleRep
\end{code}


%************************************************************************
%*                                                                      *
\subsection[TysPrim-state]{The @State#@ type (and @_RealWorld@ types)}
%*                                                                      *
%************************************************************************

Note [The ~# TyCon]
~~~~~~~~~~~~~~~~~~~~
There is a perfectly ordinary type constructor ~# that represents the type
of coercions (which, remember, are values).  For example
   Refl Int :: ~# * * Int Int

It is a kind-polymorphic type constructor like Any:
   Refl Maybe :: ~# (* -> *) (* -> *) Maybe Maybe

(~) only appears saturated. So we check that in CoreLint.

Note [The State# TyCon]
~~~~~~~~~~~~~~~~~~~~~~~
State# is the primitive, unlifted type of states.  It has one type parameter,
thus
        State# RealWorld
or
        State# s

where s is a type variable. The only purpose of the type parameter is to
keep different state threads separate.  It is represented by nothing at all.

The type parameter to State# is intended to keep separate threads separate.
Even though this parameter is not used in the definition of State#, it is
given role Nominal to enforce its intended use.

\begin{code}
mkStatePrimTy :: Type -> Type
mkStatePrimTy ty = TyConApp statePrimTyCon [ty]

statePrimTyCon :: TyCon   -- See Note [The State# TyCon]
statePrimTyCon   = pcPrimTyCon statePrimTyConName [Nominal] VoidRep

voidPrimTy :: Type
voidPrimTy = TyConApp voidPrimTyCon []

voidPrimTyCon :: TyCon
voidPrimTyCon    = pcPrimTyCon voidPrimTyConName [] VoidRep

mkProxyPrimTy :: Type -> Type -> Type
mkProxyPrimTy k ty = TyConApp proxyPrimTyCon [k, ty]

proxyPrimTyCon :: TyCon
proxyPrimTyCon = mkPrimTyCon proxyPrimTyConName kind [Nominal,Nominal] VoidRep
  where kind = ForAllTy (Named kv Invisible) $
               mkArrowKind k unliftedTypeKind
        kv   = kKiVar
        k    = mkOnlyTyVarTy kv

eqPrimTyCon :: TyCon  -- The representation type for equality predicates
                      -- See Note [The ~# TyCon]
eqPrimTyCon  = mkPrimTyCon eqPrimTyConName kind roles VoidRep
  where kind = ForAllTy (Named kv1 Invisible) $
               ForAllTy (Named kv2 Invisible) $
               mkArrowKinds [k1, k2] unliftedTypeKind
        kVars = tyVarList liftedTypeKind
        kv1 : kv2 : _ = kVars
        k1 = mkOnlyTyVarTy kv1
        k2 = mkOnlyTyVarTy kv2
        roles = [Representational, Representational, Nominal, Nominal]

-- like eqPrimTyCon, but the type for *Representational* coercions
-- this should only ever appear as the type of a covar. Its role is
-- interpreted in coercionRole
eqReprPrimTyCon :: TyCon
eqReprPrimTyCon = mkPrimTyCon eqReprPrimTyConName kind
                              (replicate 4 Representational)
                              VoidRep
  where kind = ForAllTy (Named kv1 Invisible) $
               ForAllTy (Named kv2 Invisible) $
               mkArrowKinds [k1, k2] unliftedTypeKind
        kVars         = tyVarList liftedTypeKind
        kv1 : kv2 : _ = kVars
        k1            = mkOnlyTyVarTy kv1
        k2            = mkOnlyTyVarTy kv2
\end{code}

RealWorld is deeply magical.  It is *primitive*, but it is not
*unlifted* (hence ptrArg).  We never manipulate values of type
RealWorld; it's only used in the type system, to parameterise State#.

\begin{code}
realWorldTyCon :: TyCon
realWorldTyCon = mkLiftedPrimTyCon realWorldTyConName liftedTypeKind [] PtrRep
realWorldTy :: Type
realWorldTy          = mkTyConTy realWorldTyCon
realWorldStatePrimTy :: Type
realWorldStatePrimTy = mkStatePrimTy realWorldTy        -- State# RealWorld
\end{code}

Note: the ``state-pairing'' types are not truly primitive, so they are
defined in \tr{TysWiredIn.lhs}, not here.

%************************************************************************
%*                                                                      *
\subsection[TysPrim-arrays]{The primitive array types}
%*                                                                      *
%************************************************************************

\begin{code}
arrayPrimTyCon, mutableArrayPrimTyCon, mutableByteArrayPrimTyCon,
    byteArrayPrimTyCon, arrayArrayPrimTyCon, mutableArrayArrayPrimTyCon,
    smallArrayPrimTyCon, smallMutableArrayPrimTyCon :: TyCon
arrayPrimTyCon             = pcPrimTyCon arrayPrimTyConName             [Representational] PtrRep
mutableArrayPrimTyCon      = pcPrimTyCon  mutableArrayPrimTyConName     [Nominal, Representational] PtrRep
mutableByteArrayPrimTyCon  = pcPrimTyCon mutableByteArrayPrimTyConName  [Nominal] PtrRep
byteArrayPrimTyCon         = pcPrimTyCon0 byteArrayPrimTyConName        PtrRep
arrayArrayPrimTyCon        = pcPrimTyCon0 arrayArrayPrimTyConName       PtrRep
mutableArrayArrayPrimTyCon = pcPrimTyCon mutableArrayArrayPrimTyConName [Nominal] PtrRep
smallArrayPrimTyCon        = pcPrimTyCon smallArrayPrimTyConName        [Representational] PtrRep
smallMutableArrayPrimTyCon = pcPrimTyCon smallMutableArrayPrimTyConName [Nominal, Representational] PtrRep

mkArrayPrimTy :: Type -> Type
mkArrayPrimTy elt           = TyConApp arrayPrimTyCon [elt]
byteArrayPrimTy :: Type
byteArrayPrimTy             = mkTyConTy byteArrayPrimTyCon
mkArrayArrayPrimTy :: Type
mkArrayArrayPrimTy = mkTyConTy arrayArrayPrimTyCon
mkSmallArrayPrimTy :: Type -> Type
mkSmallArrayPrimTy elt = TyConApp smallArrayPrimTyCon [elt]
mkMutableArrayPrimTy :: Type -> Type -> Type
mkMutableArrayPrimTy s elt  = TyConApp mutableArrayPrimTyCon [s, elt]
mkMutableByteArrayPrimTy :: Type -> Type
mkMutableByteArrayPrimTy s  = TyConApp mutableByteArrayPrimTyCon [s]
mkMutableArrayArrayPrimTy :: Type -> Type
mkMutableArrayArrayPrimTy s = TyConApp mutableArrayArrayPrimTyCon [s]
mkSmallMutableArrayPrimTy :: Type -> Type -> Type
mkSmallMutableArrayPrimTy s elt = TyConApp smallMutableArrayPrimTyCon [s, elt]
\end{code}

%************************************************************************
%*                                                                      *
\subsection[TysPrim-mut-var]{The mutable variable type}
%*                                                                      *
%************************************************************************

\begin{code}
mutVarPrimTyCon :: TyCon
mutVarPrimTyCon = pcPrimTyCon mutVarPrimTyConName [Nominal, Representational] PtrRep

mkMutVarPrimTy :: Type -> Type -> Type
mkMutVarPrimTy s elt        = TyConApp mutVarPrimTyCon [s, elt]
\end{code}

%************************************************************************
%*                                                                      *
\subsection[TysPrim-synch-var]{The synchronizing variable type}
%*                                                                      *
%************************************************************************

\begin{code}
mVarPrimTyCon :: TyCon
mVarPrimTyCon = pcPrimTyCon mVarPrimTyConName [Nominal, Representational] PtrRep

mkMVarPrimTy :: Type -> Type -> Type
mkMVarPrimTy s elt          = TyConApp mVarPrimTyCon [s, elt]
\end{code}

%************************************************************************
%*                                                                      *
\subsection[TysPrim-stm-var]{The transactional variable type}
%*                                                                      *
%************************************************************************

\begin{code}
tVarPrimTyCon :: TyCon
tVarPrimTyCon = pcPrimTyCon tVarPrimTyConName [Nominal, Representational] PtrRep

mkTVarPrimTy :: Type -> Type -> Type
mkTVarPrimTy s elt = TyConApp tVarPrimTyCon [s, elt]
\end{code}

%************************************************************************
%*                                                                      *
\subsection[TysPrim-stable-ptrs]{The stable-pointer type}
%*                                                                      *
%************************************************************************

\begin{code}
stablePtrPrimTyCon :: TyCon
stablePtrPrimTyCon = pcPrimTyCon stablePtrPrimTyConName [Representational] AddrRep

mkStablePtrPrimTy :: Type -> Type
mkStablePtrPrimTy ty = TyConApp stablePtrPrimTyCon [ty]
\end{code}

%************************************************************************
%*                                                                      *
\subsection[TysPrim-stable-names]{The stable-name type}
%*                                                                      *
%************************************************************************

\begin{code}
stableNamePrimTyCon :: TyCon
stableNamePrimTyCon = pcPrimTyCon stableNamePrimTyConName [Representational] PtrRep

mkStableNamePrimTy :: Type -> Type
mkStableNamePrimTy ty = TyConApp stableNamePrimTyCon [ty]
\end{code}

%************************************************************************
%*                                                                      *
\subsection[TysPrim-BCOs]{The ``bytecode object'' type}
%*                                                                      *
%************************************************************************

\begin{code}
bcoPrimTy    :: Type
bcoPrimTy    = mkTyConTy bcoPrimTyCon
bcoPrimTyCon :: TyCon
bcoPrimTyCon = pcPrimTyCon0 bcoPrimTyConName PtrRep
\end{code}

%************************************************************************
%*                                                                      *
\subsection[TysPrim-Weak]{The ``weak pointer'' type}
%*                                                                      *
%************************************************************************

\begin{code}
weakPrimTyCon :: TyCon
weakPrimTyCon = pcPrimTyCon weakPrimTyConName [Representational] PtrRep

mkWeakPrimTy :: Type -> Type
mkWeakPrimTy v = TyConApp weakPrimTyCon [v]
\end{code}

%************************************************************************
%*                                                                      *
\subsection[TysPrim-thread-ids]{The ``thread id'' type}
%*                                                                      *
%************************************************************************

A thread id is represented by a pointer to the TSO itself, to ensure
that they are always unique and we can always find the TSO for a given
thread id.  However, this has the unfortunate consequence that a
ThreadId# for a given thread is treated as a root by the garbage
collector and can keep TSOs around for too long.

Hence the programmer API for thread manipulation uses a weak pointer
to the thread id internally.

\begin{code}
threadIdPrimTy :: Type
threadIdPrimTy    = mkTyConTy threadIdPrimTyCon
threadIdPrimTyCon :: TyCon
threadIdPrimTyCon = pcPrimTyCon0 threadIdPrimTyConName PtrRep
\end{code}

%************************************************************************
%*                                                                      *
                Any
%*                                                                      *
%************************************************************************

Note [Any types]
~~~~~~~~~~~~~~~~
The type constructor Any of kind forall k. k has these properties:

  * It is defined in module GHC.Prim, and exported so that it is
    available to users.  For this reason it's treated like any other
    primitive type:
      - has a fixed unique, anyTyConKey,
      - lives in the global name cache

  * It is a *closed* type family, with no instances.  This means that
    if   ty :: '(k1, k2)  we add a given coercion
             g :: ty ~ (Fst ty, Snd ty)
    If Any was a *data* type, then we'd get inconsistency because 'ty'
    could be (Any '(k1,k2)) and then we'd have an equality with Any on
    one side and '(,) on the other. See also #9097.

  * It is lifted, and hence represented by a pointer

  * It is inhabited by at least one value, namely bottom

  * You can unsafely coerce any lifted type to Any, and back.

  * It does not claim to be a *data* type, and that's important for
    the code generator, because the code gen may *enter* a data value
    but never enters a function value.

  * It is used to instantiate otherwise un-constrained type variables
    For example         length Any []
    See Note [Strangely-kinded void TyCons]

Note [Strangely-kinded void TyCons]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
See Trac #959 for more examples

When the type checker finds a type variable with no binding, which
means it can be instantiated with an arbitrary type, it usually
instantiates it to Void.  Eg.

        length []
===>
        length Any (Nil Any)

But in really obscure programs, the type variable might have a kind
other than *, so we need to invent a suitably-kinded type.

This commit uses
        Any for kind *
        Any(*->*) for kind *->*
        etc

\begin{code}
anyTyConName :: Name
anyTyConName = mkPrimTc (fsLit "Any") anyTyConKey anyTyCon

anyTy :: Type
anyTy = mkTyConTy anyTyCon

anyTyCon :: TyCon
anyTyCon = mkSynTyCon anyTyConName kind [kKiVar] [Nominal]
                      syn_rhs
                      NoParentTyCon
  where
    kind = ForAllTy (Named kKiVar Invisible) (mkOnlyTyVarTy kKiVar)
    syn_rhs = AbstractClosedSynFamilyTyCon

anyTypeOfKind :: Kind -> Type
anyTypeOfKind kind = TyConApp anyTyCon [kind]
\end{code}

%************************************************************************
%*                                                                      *
\subsection{SIMD vector types}
%*                                                                      *
%************************************************************************

\begin{code}
#include "primop-vector-tys.hs-incl"
\end{code}
