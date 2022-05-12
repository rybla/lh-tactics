{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

{-@ LIQUID "--compile-spec" @-}

module Tactic.Core.Syntax where

import Data.Map as Map
import Language.Haskell.TH
import Language.Haskell.TH.Datatype
import Language.Haskell.TH.Ppr (pprint)
import Language.Haskell.TH.Quote
import Language.Haskell.TH.Syntax
import System.IO.Unsafe (unsafePerformIO)
import Tactic.Core.Debug
import qualified Data.List as List
import Prelude hiding (exp)

data Instr
  = -- | splices a lambda; adds name to environment
    Intro {name :: String}
  | -- | destructs a datatype
    Destruct {name :: String, intros :: Maybe [[String]]}
  | -- | inducts on an input argument
    Induct {name :: String, intros :: Maybe [[String]]}
  | -- | add hint to subsequent auto hints
    Hint {exp :: Exp}
  | -- | auto
    Auto {hints :: [Exp], depth :: Int}
  | -- | asserts a boolean exp must be true
    Assert {exp :: Exp}
  | -- | use refinment of an exp
    Use {exp :: Exp}
  | -- | condition on a boolean exp
    Cond {exp :: Exp}
  | -- | trivial
    Trivial

defaultAutoHints = [] :: [Exp]

defaultAutoDepth = 3 :: Int

instance Show Instr where
  show (Intro {name}) = "intro " ++ name
  show (Destruct {name, intros}) = "destruct " ++ name ++ case intros of {Just intros -> " as " ++ showIntros intros; Nothing -> ""}
  show (Induct {name, intros}) = "induct " ++ name ++ case intros of {Just intros -> " as " ++ showIntros intros; Nothing -> ""}
  show (Hint {exp}) = "hint " ++ pprint exp
  show (Auto {hints, depth}) = "auto " ++ show (pprint <$> hints) ++ " " ++ show depth
  show (Assert {exp}) = "assert " ++ pprint exp
  show (Use {exp}) = "use " ++ pprint exp
  show (Cond {exp}) = "cond " ++ pprint exp
  show Trivial = "trivial"

showIntros :: [[String]] -> String 
showIntros intros = "[" ++ List.intercalate " | " (List.intercalate " " <$> intros) ++ "]"

type Ctx = Map Exp Type

data Environment = Environment
  { def_name :: Name,
    def_type :: Type,
    def_argTypes :: [Type],
    def_argNames :: [Name],
    arg_i :: Int,
    args_rec_ctx :: Map Int Ctx, -- recursive-allowed context for each arg
    ctx :: Ctx,
    var_i :: Int
  }

instance Show Environment where
  show env =
    unlines
      [ "def_name: " ++ show (def_name env),
        "def_type: " ++ show (def_type env),
        "def_argTypes: " ++ show (def_argTypes env),
        "def_argNames: " ++ show (def_argNames env),
        "arg_i: " ++ show (arg_i env),
        "args_rec_ctx: " ++ show (args_rec_ctx env),
        "ctx: " ++ show (ctx env)
      ]

introArg :: Name -> Type -> Environment -> Environment
introArg name type_ env =
  env
    { -- these are handled during parsing
      -- def_argNames = def_argNames env ++ [name],
      -- def_argTypes = def_argTypes env ++ [type_],
      arg_i = arg_i env + 1,
      ctx = Map.insert (VarE name) type_ $ ctx env
    }

insertCtx :: Exp -> Type -> Environment -> Environment
insertCtx e type_ env =
  env
    { ctx = Map.insert e type_ $ ctx env
    }

deleteCtx :: Exp -> Environment -> Environment
deleteCtx e env =
  env
    { ctx = Map.delete e $ ctx env
    }

emptyEnvironment :: Environment
emptyEnvironment =
  Environment
    { def_name = undefined,
      def_type = undefined,
      def_argTypes = [],
      def_argNames = [],
      arg_i = 0,
      args_rec_ctx = Map.empty,
      ctx = Map.empty,
      var_i = 0
    }

inferType :: Exp -> Environment -> Q (Maybe Type)
inferType e env = do
  case Map.lookup e (ctx env) of
    Just type_ -> Just <$> pure type_
    Nothing -> case e of
      VarE name -> do
        -- just to check if the name is in scope
        mb <- lookupValueName (nameBase name)
        case mb of
          Just _ -> do
            debugM $! "inferType of " ++ show e
            Just <$> reifyType name
          Nothing ->
            pure Nothing
      ConE name -> Just <$> reifyType name
