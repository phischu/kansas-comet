{-# LANGUAGE OverloadedStrings, ScopedTypeVariables, KindSignatures, GADTs #-}

-- Example of using Kansas Comet

module Main where

import Data.Aeson as A hiding ((.=))
import Data.Aeson.Types as AP hiding ((.=))
import qualified Web.Scotty as Scotty
import Web.Scotty (scotty, get, file, literal, middleware)
import Web.KansasComet as KC
import Data.Default
import Data.Map (Map)
import Control.Monad
import Control.Applicative ((<$>),(<*>))
import qualified Control.Applicative as A
import Control.Concurrent
import Control.Concurrent.STM
import Data.Semigroup
import Data.List as L
import Control.Monad.IO.Class
import Network.Wai.Middleware.Static
-- import Network.Wai      -- TMP for debug

import qualified Data.Text.Lazy as LT
import qualified Data.Text      as T

main = scotty 3000 $ do
    kcomet <- liftIO kCometPlugin

    let pol = only [ ("","index.html")
                   , ("js/kansas-comet.js",kcomet)
                   ]
              <|> ((hasPrefix "css/" <|> hasPrefix "js/") >-> addBase ".")

    middleware $ staticPolicy pol

    connect opts web_app

opts :: KC.Options
opts = def { prefix = "/example", verbose = 3 }

-- This is run each time the page is first accessed
web_app :: Document -> IO ()
web_app doc = do
    send doc $ unlines
        [ "$('body').on('slide', '.slide', function (event,aux) {"
        , "$.kc.reply(0,{eventname: 'slide', count: aux.value });"
        , "});"
        ]
    send doc $ unlines
        [ "$('body').on('click', '.click', function (event,aux) {"
        , "$.kc.reply(0,{eventname: 'click', id: $(this).attr('id'), pageX: event.pageX, pageY: event.pageY });"
        , "});"
        ]
    forkIO $ control doc 0
    return ()

control :: Document -> Int -> IO ()
control doc model = do
    res <- getReply doc 0
    case parse parseEvent res of
           Success evt -> case evt of
                   Slide n                        -> view doc n
                   Click "up"    _ _ | model < 25 -> view doc (model + 1)
                   Click "down"  _ _ | model > 0  -> view doc (model - 1)
                   Click "reset" _ _              -> view doc 0
                   _ -> control doc model
           _ -> control doc model

view :: Document -> Int -> IO ()
view doc n = do
    send doc $ concat
                [ "$('#slider').slider('value'," ++ show n ++ ");"
                , "$('#fib-out').html('fib " ++ show n ++ " = ...')"
                ]
    -- sent a 2nd packet, because it will take time to compute fib
    send doc ("$('#fib-out').text('fib " ++ show n ++ " = " ++ show (fib n) ++ "')")

    control doc n

fib n = if n < 2 then 1 else fib (n-1) + fib (n-2)

parseEvent (Object v) = (do
                e :: String <- v .: "eventname"
                n <- v .: "count"
                if e == "slide" then return $ Slide n
                                else mzero) A.<|>
                                (do
                e :: String <- v .: "eventname"
                tag :: String <- v .: "id"
                x :: Int <- v .: "pageX"
                y :: Int <- v .: "pageY"
                if e == "click" then return $ Click tag x y
                                else mzero)
          -- A non-Object value is of the wrong type, so fail.
parseEvent _          = mzero

data Event = Slide Int
           | Click String Int Int
    deriving (Show)
