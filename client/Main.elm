module Main exposing (main)


import Axis
import Browser
import Color
import Html exposing (Html, button, div, text)
import Html.Events exposing (onClick)
import Http
import Iso8601
import Json.Decode as JD exposing (field, Decoder, int, string)
import Path exposing (Path)
import Scale exposing (ContinuousScale)
import Shape
import Time
import TypedSvg exposing (g, svg)
import TypedSvg.Attributes exposing (class, fill, stroke, transform, viewBox)
import TypedSvg.Attributes.InPx exposing (strokeWidth)
import TypedSvg.Core exposing (Svg)
import TypedSvg.Types exposing (Paint(..), Transform(..))
import Url.Builder as UB

w : Float
w =
    900


h : Float
h =
    450


padding : Float
padding =
    50

type alias Measure = ( Time.Posix, Float )
type MeasureName = Mass | FatMass | FatRatio
type alias Series = { name: MeasureName, measures: List Measure  }

type alias Model = List Series

spy a =
    let _ = Debug.log "spy" a
    in a


xScale : List Measure -> ContinuousScale Time.Posix
xScale model =
    let times = List.map (Tuple.first >> Time.posixToMillis) model
        latest = List.foldl max 0 times
        earliest = List.foldl min latest times
    in
    Scale.time Time.utc ( 0, w - 2 * padding ) ( Time.millisToPosix earliest, Time.millisToPosix latest )

yScale : List Measure -> ContinuousScale Float
yScale model =
    let ys = List.map Tuple.second model
        top = List.foldl max 0 ys
        bottom = List.foldl min top ys
    in
    Scale.linear ( h - 2 * padding, 0 ) ( bottom, top )

xAxis : List Measure -> Svg msg
xAxis model =
    Axis.bottom [ Axis.tickCount 10 ] (xScale model)

yAxis : List Measure -> Svg msg
yAxis model =
    Axis.left [ Axis.tickCount 5 ] (yScale model)

line : List Measure -> Path
line model =
    let transformToLineData (x, y) =
            Just ( Scale.convert (xScale model) x, Scale.convert (yScale model) y )
    in
    List.map transformToLineData model
        |> Shape.line Shape.monotoneInXCurve

smoothMeasures : List Measure -> List Measure
smoothMeasures measures =
    let lambda = 0.10/86400000
        interval later earlier = Time.posixToMillis later - Time.posixToMillis earlier
        smoothMore (prev_t, prev_y) measures_ =
            case measures_ of
                [] -> []
                m1 :: [] -> [m1]
                (t, y) :: ms ->
                    let m = e ^ (-lambda * (toFloat (interval t prev_t)))
                        newSmooth = (t, (1.0-m) * y + m * prev_y)
                    in newSmooth :: (smoothMore newSmooth ms)
        in
        case measures of
            [] -> []
            x :: _ -> (smoothMore x measures)


area : List Measure -> Path
area model =
    let xsm = xScale model
        ysm = yScale model
        transfromToAreaData ( x, y ) =
            Just
            ( ( Scale.convert xsm x, Tuple.first (Scale.rangeExtent ysm) )
            , ( Scale.convert xsm x, Scale.convert ysm y ))
    in
    List.map transfromToAreaData model
        |> Shape.area Shape.monotoneInXCurve

viewSeries : Series -> Svg msg

viewSeries series =
    let {name, measures} = series
    in
    svg [ viewBox 0 0 w h ]
        [ g [ transform [ Translate (padding - 1) (h - padding) ] ]
            [ xAxis measures ]
        , g [ transform [ Translate (padding - 1) padding ] ]
            [ yAxis measures ]
        , g [ transform [ Translate padding padding ], class [ "series" ] ]
            [ -- Path.element (area measures) [ strokeWidth 3, fill <| Paint <| Color.rgba 1 0 0 0.54 ]
              Path.element (line measures) [ stroke <| Paint <| Color.rgb 1 0 0, strokeWidth 3, fill PaintNone ]
            , Path.element (line (smoothMeasures measures)) [ stroke <| Paint <| Color.rgb 0.4 0.9 0, strokeWidth 3, fill PaintNone ]
            ]
        ]

view model =
    div []
        [ div [] (List.map viewSeries model)
        , button [ onClick RefreshData ] [ text "( )" ]]

type alias MeasureJson =
    { date : String
    , mass : Float
    , fatMass : Maybe Float
    , fatRatio : Maybe Float
    , nonFatMass : Maybe Float
    }

measureDecoder =
    JD.map5 MeasureJson
        (field "date" string)
        (field "weight" JD.float)
        (JD.maybe (field "fat_mass_weight" JD.float))
        (JD.maybe (field "fat_ratio" JD.float))
        (JD.maybe (field "fat_free_mass" JD.float))

dataDecoder : Decoder (List MeasureJson)
dataDecoder = JD.list measureDecoder


getData : Cmd Msg
getData =
    let endDate = 1595189057000 + 15*86400*1000
        startDate = endDate - (86400*1000*120)
    in
    Http.get
        { url = UB.relative [ "/weights.json" ] [ UB.int "start" startDate, UB.int "end" endDate ]
        , expect = Http.expectJson DataReceived dataDecoder
        }

type Msg
    = RefreshData
    | DataReceived (Result Http.Error (List MeasureJson))

init : () -> (Model, Cmd Msg)
init _  = ([], getData)

parseDate possibleString =
    case (Iso8601.toTime possibleString) of
        Ok val -> val
        Err _ -> Time.millisToPosix 0

newModelForJson _ json =
    [ Series Mass (List.map
                       (\m -> (parseDate m.date, m.mass))
                       (List.reverse json)) ]

updateData model result =
    case result of
        Ok json ->
            (newModelForJson model json, Cmd.none)
        Err httpError ->
            let _ = Debug.log "errir" httpError
            in (model, Cmd.none)

-- timeSeries = List.map (\x -> ((Time.millisToPosix (x*86400*500 + 1458928000000)),  toFloat (52 +(modBy 5 x)))) (List.range 1 100)

update : Msg -> Model -> (Model, Cmd Msg )
update msg model =
    case msg of
        RefreshData -> ( model, getData)
        DataReceived result -> updateData model result
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = \_ -> Sub.none
        }
