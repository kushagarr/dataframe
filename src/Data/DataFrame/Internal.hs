{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ExplicitNamespaces #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE OverloadedStrings #-}

module Data.DataFrame.Internal (
    DataFrame(..),
    Column(..),
    transformColumn,
    fetchColumn,
    empty) where

import qualified Data.ByteString.Char8 as C
import qualified Data.Map as M
import qualified Data.Map.Strict as MS
import qualified Data.Vector as V

import Data.DataFrame.Util ( applySnd, showTable, typeMismatchError )
import Data.Function (on)
import Data.List (groupBy, sortBy, elemIndex, transpose)
import Data.Map (Map)
import Data.Maybe (fromMaybe)
import Data.Typeable (Typeable)
import Data.Vector (Vector)
import Data.Type.Equality
    ( type (:~:)(Refl), TestEquality(testEquality) )
import Type.Reflection ( Typeable, TypeRep, typeRep )
import GHC.Stack (HasCallStack)

data Column where
    MkColumn :: (Typeable a, Show a) => Vector a -> Column

fetchColumn :: forall a . (HasCallStack, Typeable a, Show a) => Column -> Vector a
fetchColumn (MkColumn (column :: Vector b)) = let
                    repb :: Type.Reflection.TypeRep b = Type.Reflection.typeRep @b
                    repa :: Type.Reflection.TypeRep a = Type.Reflection.typeRep @a
                    -- These are the defaults selected by the extension
                    -- ExtendDefaults
                    repInteger :: Type.Reflection.TypeRep Integer = Type.Reflection.typeRep @Integer
                    repInt :: Type.Reflection.TypeRep Int = Type.Reflection.typeRep @Int
                in case repa `testEquality` repb of
                    Just Refl -> column
                    -- Asuming type defaults are on manualy handle the conversion between
                    -- integer and int
                    Nothing -> case repa `testEquality` repInt of
                        Just Refl -> case repb `testEquality` repInteger of
                            Just Refl -> V.map fromIntegral column
                            Nothing -> error $ typeMismatchError "" "" repa repb
                        Nothing -> case repa `testEquality` repInteger of
                            Just Refl -> case repb `testEquality` repInt of
                                Just Refl -> V.map fromIntegral column
                                -- TODO: This doesn't pass useful information about the call point.
                                Nothing -> error $ typeMismatchError "" "" repa repb
                            Nothing -> error $ typeMismatchError "" "" repa repb

transformColumn :: forall a b . (Typeable a, Show a, Typeable b, Show b)
                => (Vector a -> Vector b) -> Column -> Column
transformColumn f c = MkColumn $! f (fetchColumn c) 

instance Show Column where
    show :: Column -> String
    show (MkColumn column) = show column

data DataFrame = DataFrame {
    columns :: Map C.ByteString Column,
    _columnNames :: [C.ByteString]
}

empty :: DataFrame
empty = DataFrame { columns = M.empty, _columnNames = [] }

instance Show DataFrame where
    show :: DataFrame -> String
    show d = let
                 header = _columnNames d
                 get (MkColumn column) = V.map (C.pack . show) column
                 getByteStringColumnFromFrame df name = get $ (MS.!) (columns d) name
                 rows = transpose
                      $ map (V.toList . getByteStringColumnFromFrame d) header
             in C.unpack $ showTable header rows
