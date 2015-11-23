{-# LANGUAGE TypeFamilies #-}
module Small where

class CoCCC k where
        type Coexp k :: * -> * -> *
        type Sum k :: * -> * -> *
        coapply' :: k b (Sum k (Coexp k a b) a)
        cocurry' :: k c (Sum k a b) -> k (Coexp k b c) a
        uncocurry' :: k (Coexp k b c) a -> k c (Sum k a b)

coapply   :: CoCCC k => k b (Sum k (Coexp k a b) a)
{-# INLINE [1] coapply #-}
coapply = coapply'

cocurry   :: CoCCC k => k c (Sum k a b) -> k (Coexp k b c) a
{-# INLINE [1] cocurry #-}
cocurry = cocurry'

uncocurry :: CoCCC k => k (Coexp k b c) a -> k c (Sum k a b)
{-# INLINE [1] uncocurry #-}
uncocurry = uncocurry'

{-# RULES
"cocurry coapply"               cocurry coapply = id
"cocurry . uncocurry"           forall x. cocurry (uncocurry x) = x
"uncocurry . cocurry"           forall x. uncocurry (cocurry x) = x
 #-}


{-
cocurry coapply :: a -> a
cocurry (coapply :: k b (Sum k (Coexp k a b) a))

[W] w1 ::  k b (Sum k (Coexp k a b) a) ~ k b (Sum k2 a2 b2)

cocurry coapply :: k (Coexp k b2 b) a2

[W] w2 :: (Coexp (->) b2 b) -> x  ~  x -> x

[G] Sum (->) (Coexp (->) a b) a ~ Sum k2 x b2
[G]
-}
