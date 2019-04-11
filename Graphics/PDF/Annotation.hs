---------------------------------------------------------
-- |
-- Copyright   : (c) 2006-2016, alpheccar.org
-- License     : BSD-style
--
-- Maintainer  : misc@NOSPAMalpheccar.org
-- Stability   : experimental
-- Portability : portable
--
-- PDF Annotations
---------------------------------------------------------

module Graphics.PDF.Annotation(
   -- * Annotations
   -- ** Types
     TextAnnotation(..)
   , DetailedTextAnnotation(..)
   , BorderStyle(..)
   , BorderLineStyle(..)
   , URLLink(..)
   , PDFLink(..)
   , TextIcon(..)
   , TextMarkup(..)
   , MarkupType(..)
   -- ** Functions
   , newAnnotation
   , toAsciiString
 ) where

import           Control.Monad.State         (gets)
import qualified Data.Map                    as M
import qualified Data.Text                   as T
import           Graphics.PDF.Action
import           Graphics.PDF.Draw
import           Graphics.PDF.LowLevel.Types
import           Graphics.PDF.Pages
import           Network.URI
import Data.Maybe (fromMaybe, catMaybes)

--import Debug.Trace

data TextIcon = Note
              | Paragraph
              | NewParagraph
              | Key
              | Comment
              | Help
              | Insert
              deriving(Eq,Show)

data MarkupType = Highlight | Squiggle | Underline

data TextMarkup = TextMarkup { -- PDF 1.3
  tmContent :: T.Text, -- Content
  tmMarkup :: MarkupType,
  tmRect :: [PDFFloat], -- Rect
  tmColor :: Color,
  tmColorAlpha :: PDFFloat,
  tmFlag :: PDFInteger,
  tmQuads :: [[PDFFloat]] -- Quadpoints
}

data BorderStyle = BorderStyle {
  bsWidth :: PDFFloat,
  bsLine :: Maybe BorderLineStyle,
  bsDashPattern :: Maybe [PDFFloat]
                 }

data BorderLineStyle = BorderSolid | BorderDashed | BorderBeveled | BorderInset | BorderUnderline

instance Show BorderLineStyle where
  show BorderSolid = "S"
  show BorderDashed = "D"
  show BorderBeveled = "B"
  show BorderInset = "I"
  show BorderUnderline = "U"

data DetailedTextAnnotation = DetailedTextAnnotation {
  taContent :: T.Text,
  taIcon :: TextIcon,
  taRect :: [PDFFloat],
  taColor :: Maybe Color,
  taFlags :: Maybe PDFInteger,
  taBorder :: Maybe BorderStyle,
  taOpen :: Maybe Bool
}

buildDictEntry key value = (PDFName key, AnyPdfObject value)

buildBorderStyle :: BorderStyle -> PDFDictionary
buildBorderStyle bs =
  let entries = catMaybes [
        Just (buildDictEntry "Type" (PDFName "Border")),
        Just (buildDictEntry "W" (bsWidth bs)),
        buildDictEntry "S" . PDFName . show <$> (bsLine bs),
        buildDictEntry "D" <$> (bsDashPattern bs)]
  in PDFDictionary . M.fromList $ entries

instance PdfObject DetailedTextAnnotation where
      toPDF a = toPDF . PDFDictionary . M.fromList $
        let newEntries = catMaybes [
              Just (PDFName "Name",AnyPdfObject . PDFName $ show (taIcon a)),
              buildDictEntry "F" <$> (taFlags a),
              buildDictEntry "C" <$> (taColor a),
              buildDictEntry "BS" . buildBorderStyle <$> (taBorder a),
              buildDictEntry "Open" <$> (taOpen a)]
        in standardAnnotationDict a ++ newEntries

instance PdfLengthInfo DetailedTextAnnotation where

instance AnnotationObject DetailedTextAnnotation where
    addAnnotation = addObject
    annotationType _ = PDFName "Text"
    annotationContent a = AnyPdfObject (toPDFString (taContent a))
    annotationRect a = (taRect a)
    annotationToGlobalCoordinates a = do
        gr <- transformAnnotRect (taRect a)
        return $ a {taRect=gr}



data TextAnnotation = TextAnnotation
   T.Text -- Content
   [PDFFloat] -- Rect
   TextIcon

data URLLink = URLLink
  T.Text -- Content
  [PDFFloat] -- Rect
  URI -- URL
  Bool -- Border

data PDFLink = PDFLink
  T.Text -- Content
  [PDFFloat] -- Rect
  (PDFReference PDFPage) -- Page
  PDFFloat -- x
  PDFFloat -- y
  Bool -- Border
--data Screen = Screen (PDFReference Rendition) PDFString [PDFFloat] (PDFReference PDFPage) (Maybe (PDFReference ControlMedia)) (Maybe (PDFReference ControlMedia))

--det :: Matrix -> PDFFloat
--det (Matrix a b c d _ _) = a*d - b*c
--
--inverse :: Matrix -> Matrix
--inverse m@(Matrix a b c d e f) = (Matrix (d/de) (-b/de) (-c/de) (a/de) 0 0) * (Matrix 1 0 0 1 (-e) (-f))
--	where
--		de = det m

applyMatrixToQuadPoints :: Matrix -> [PDFFloat] -> [PDFFloat]
applyMatrixToQuadPoints m quad = -- [xa, ya, xb, yb, xc, yc, xd, yd] =
  let
    slicePairs (x0:x1:xs) = (x0, x1) : slicePairs xs
    slicePairs [] = []
    slicePairs _ = error "odd number of elements"

    catPairs [] = []
    catPairs ((x,y):xys) = x:y:catPairs xys

    applyTo (Matrix a b c d e f) (x,y) = (a*x+c*y+e,b*x+d*y+f)

  in catPairs $ (applyTo m) <$> slicePairs quad

applyMatrixToRectangle :: Matrix -> [PDFFloat] -> [PDFFloat]
applyMatrixToRectangle m [xa,ya,xb,yb] =
    let (xa',ya') = m `applyTo` (xa,ya)
        (xa'',yb') = m `applyTo` (xa,yb)
        (xb',ya'') = m `applyTo` (xb,ya)
        (xb'',yb'') = m `applyTo` (xb,yb)
        x1 = minimum [xa',xa'',xb',xb'']
        x2 = maximum [xa',xa'',xb',xb'']
        y1 = minimum [ya',ya'',yb',yb'']
        y2 = maximum [ya',ya'',yb',yb'']
    in
    [x1,y1,x2,y2]
 where
     applyTo (Matrix a b c d e f) (x,y) = (a*x+c*y+e,b*x+d*y+f)

applyMatrixToRectangle _ a = a



-- | Get the border shqpe depending on the style
getBorder :: Bool -> [PDFInteger]
getBorder False = [0,0,0]
getBorder True  = [0,0,1]

standardAnnotationDict :: AnnotationObject a => a -> [(PDFName,AnyPdfObject)]
standardAnnotationDict a = [(PDFName "Type",AnyPdfObject . PDFName $ "Annot")
                         , (PDFName "Subtype",AnyPdfObject $ annotationType a)
                         , (PDFName "Rect",AnyPdfObject . map AnyPdfObject $ annotationRect a)
                         , (PDFName "Contents",AnyPdfObject $ annotationContent a)
                         ]

--instance PdfObject Screen where
--   toPDF a@(Screen _ _ _ p play stop) = toPDF . PDFDictionary . M.fromList $
--        standardAnnotationDict a ++ [(PDFName "P",AnyPdfObject p)]
--                                    ++ (maybe [] (\x -> [(PDFName "A",AnyPdfObject x)]) play)
--                                    ++ (maybe [] (\x -> [(PDFName "AA",AnyPdfObject $ otherActions x)]) stop)
--         where
--             otherActions x = PDFDictionary . M.fromList $ [(PDFName "D",AnyPdfObject x)]
--
--instance AnnotationObject Screen where
--  addAnnotation (Screen video s rect p _ _) = do
--      r <- supply
--      playAction <- addObject $ ControlMedia Play r video
--      stopAction <- addObject $ ControlMedia Stop r video
--      updateObject (PDFReference r) $ Screen video s rect p (Just playAction) (Just playAction)
--      return $ PDFReference r
--  annotationType _ = PDFName "Screen"
--  annotationContent (Screen _ s _ _ _ _) = s
--  annotationRect (Screen _ _ r _ _ _) = r

instance PdfObject TextMarkup where
  toPDF a = toPDF . PDFDictionary . M.fromList $
    standardAnnotationDict a ++ [
    (PDFName "QuadPoints", AnyPdfObject . map AnyPdfObject $ concat $ tmQuads a),
    (PDFName "C", AnyPdfObject $ tmColor a),
    (PDFName "CA", AnyPdfObject $ tmColorAlpha a),
    (PDFName "F", AnyPdfObject $ tmFlag a)
    ]

instance PdfLengthInfo TextMarkup where

instance AnnotationObject TextMarkup where
  addAnnotation = addObject
  annotationType a = case tmMarkup a of
    Highlight -> PDFName "Highlight"
    Squiggle -> PDFName "Squiggly"
    Underline -> PDFName "Underline"
  annotationContent a = AnyPdfObject (toPDFString (tmContent a))
  annotationRect = tmRect
  annotationToGlobalCoordinates a = do
    gr <- transformAnnotRect (tmRect a)
    gq <- transformAnnotQuads (tmQuads a)
    return $ a {tmRect = gr, tmQuads = gq}



instance PdfObject TextAnnotation where
      toPDF a@(TextAnnotation _ _ i) = toPDF . PDFDictionary . M.fromList $
           standardAnnotationDict a ++ [(PDFName "Name",AnyPdfObject . PDFName $ show i)]

instance PdfLengthInfo TextAnnotation where

instance AnnotationObject TextAnnotation where
    addAnnotation = addObject
    annotationType _ = PDFName "Text"
    annotationContent (TextAnnotation s _ _) = AnyPdfObject (toPDFString s)
    annotationRect (TextAnnotation _ r _) = r
    annotationToGlobalCoordinates (TextAnnotation a r b) = do
        gr <- transformAnnotRect r
        return $ TextAnnotation a gr b

instance PdfObject URLLink where
    toPDF a@(URLLink _ _ url border) = toPDF . PDFDictionary . M.fromList $
           standardAnnotationDict a ++
            [ (PDFName "A",AnyPdfObject (GoToURL url))
            , (PDFName "Border",AnyPdfObject . map AnyPdfObject $ (getBorder border))
            ]

instance PdfLengthInfo URLLink where

instance AnnotationObject URLLink where
    addAnnotation = addObject
    annotationType _ = PDFName "Link"
    annotationContent (URLLink s _ _ _) = AnyPdfObject (toPDFString s)
    annotationRect (URLLink _ r _ _) = r
    annotationToGlobalCoordinates (URLLink a r b c) = do
        gr <- transformAnnotRect r
        return $ URLLink a gr b c

instance PdfObject PDFLink where
    toPDF a@(PDFLink _ _ page x y border) = toPDF . PDFDictionary . M.fromList $
               standardAnnotationDict a ++
                [(PDFName "Dest",AnyPdfObject dest)
                ,(PDFName "Border",AnyPdfObject . map AnyPdfObject $ (getBorder border))]
     where
         dest =  [ AnyPdfObject page
                 , AnyPdfObject (PDFName "XYZ")
                 , AnyPdfObject x
                 , AnyPdfObject y
                 , AnyPdfObject (PDFInteger 0)]

instance PdfLengthInfo PDFLink where

instance AnnotationObject PDFLink where
    addAnnotation = addObject
    annotationType _ = PDFName "Link"
    annotationContent (PDFLink s _ _ _ _ _) = AnyPdfObject (toPDFString s)
    annotationRect (PDFLink _ r _ _ _ _) = r
    annotationToGlobalCoordinates (PDFLink a r b c d e) = do
        gr <- transformAnnotRect r
        return $ PDFLink a gr b c d e

transformAnnotQuads :: [[PDFFloat]] -> Draw [[PDFFloat]]
transformAnnotQuads r = do
  l <- gets matrix
  let m = foldr (*) identity l
  return $ (applyMatrixToQuadPoints m) <$> r

transformAnnotRect :: [PDFFloat] -> Draw [PDFFloat]
transformAnnotRect r = do
    l <- gets matrix
    let m = foldr (*) identity l
    return $ m `applyMatrixToRectangle` r

-- | Create a new annotation object
newAnnotation :: (PdfObject a, AnnotationObject a) => a -> Draw ()
newAnnotation annot = do
    annot' <- annotationToGlobalCoordinates annot
    modifyStrict $ \s -> s {annots = (AnyAnnotation annot'):(annots s)}
    return ()
