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
import Zoom exposing (OnZoom, Zoom)

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

type alias Model = { series: List Series
                   , zoom: Zoom
                   , dates: (Time.Posix, Time.Posix)  }

spy a =
    let _ = Debug.log "spy" a
    in a


xScale : Model -> ContinuousScale Time.Posix
xScale model =
    let (earliest, latest) = model.dates
    in
    Scale.time Time.utc ( 0, w - 2 * padding ) model.dates

yScale : List Measure -> ContinuousScale Float
yScale measures =
    let ys = List.map Tuple.second measures
        top = List.foldl max 0 ys
        bottom = List.foldl min top ys
    in
    Scale.linear ( h - 2 * padding, 0 ) ( bottom, top )

xAxis : Model -> Svg msg
xAxis model =
    Axis.bottom [ Axis.tickCount 10 ] (xScale model)

yAxis : Model -> Svg msg
yAxis model =
    case model.series of
        [] -> g [] []
        series :: _ -> Axis.left [ Axis.tickCount 5 ] (yScale series.measures)

line : Model -> List Measure -> Path
line model measures =
    let transformToLineData (x, y) =
            Just ( Scale.convert (xScale model) x, Scale.convert (yScale measures) y )
    in
    List.map transformToLineData measures
        |> Shape.line Shape.monotoneInXCurve

timeInterval later earlier =
    Time.posixToMillis later - Time.posixToMillis earlier

smoothMeasures : List Measure -> List Measure
smoothMeasures measures =
    let lambda = 0.10/86400000
        smoothMore (prev_t, prev_y) measures_ =
            case measures_ of
                [] -> []
                m1 :: [] -> [m1]
                (t, y) :: ms ->
                    let m = e ^ (-lambda * (toFloat (timeInterval t prev_t)))
                        newSmooth = (t, (1.0-m) * y + m * prev_y)
                    in newSmooth :: (smoothMore newSmooth ms)
        in
        case measures of
            [] -> []
            x :: _ -> (smoothMore x measures)

viewSeries : Model -> Series -> Svg Msg
viewSeries model series =
    let {name, measures} = series
    in
    g [ transform [ Translate padding padding ], class [ "series" ] ]
        [ Path.element (line model measures) [ stroke <| Paint <| Color.rgb 1 0 0, strokeWidth 2, fill PaintNone ]
        , Path.element (line model (smoothMeasures measures)) [ stroke <| Paint <| Color.rgb 0.4 0.9 0, strokeWidth 2, fill PaintNone ]
        ]

view : Model -> Html Msg
view model =
    let attrs = [ viewBox 0 0 w h
                , Zoom.transform model.zoom
                ] ++ (Zoom.events model.zoom ZoomMsg)
    in
    div []
        [ div []
              [ svg attrs
                    ([ g [ transform [ Translate (padding - 1) (h - padding) ] ]
                          [ xAxis model ]
                     , g [ transform [ Translate (padding - 1) padding ] ]
                        [ yAxis model ]] ++
                     (List.map (viewSeries model) model.series))]]


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

getData : Model -> Cmd Msg
getData model =
    let (startDate, endDate) = model.dates
    in
    Http.get
        { url = UB.relative [ "/weights.json" ]
              [ UB.int "start" (Time.posixToMillis startDate)
              , UB.int "end" (Time.posixToMillis endDate) ]
        , expect = Http.expectJson DataReceived dataDecoder
        }

type Msg
    = RefreshData
    | ZoomMsg OnZoom
    | DataReceived (Result Http.Error (List MeasureJson))

init : () -> (Model, Cmd Msg)
init _  =
    let z = Zoom.init { width = w-2*padding, height = h-2*padding }
        endDate = 1595189057000 + 15*86400*1000
        startDate = endDate - (86400*1000*120)
        model = { zoom = z
                , series = []
                , dates = ( Time.millisToPosix startDate
                          , Time.millisToPosix endDate)
                }
    in (model, getData model)

parseDate possibleString =
    case (Iso8601.toTime possibleString) of
        Ok val -> val
        Err _ -> Time.millisToPosix 0

newModelForJson model json =
    let s = [ Series Mass (List.map
                           (\m -> (parseDate m.date, m.mass))
                           (List.reverse json)) ]
    in { zoom = model.zoom
       , dates = model.dates
       , series = s
       }


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
        RefreshData -> ( model, getData model)
        DataReceived result -> updateData model result
        ZoomMsg zm ->
            let newZoom = spy (Zoom.update zm model.zoom)
                scale = (Zoom.asRecord newZoom).scale
                (startDate, endDate) = model.dates
                newTimeRange = round (toFloat (timeInterval endDate startDate)/scale)
            in
            -- zoom transform has k, x, y where k is magnification from
            -- initial, x and y seem to be in pixels. we need to use those
            -- numbers to recalculate start and end date
            ( { model
                  | dates = ( startDate
                            , Time.millisToPosix
                                ((Time.posixToMillis startDate) + newTimeRange))
              }
            , Cmd.none
            )

subscriptions model =
    Zoom.subscriptions model.zoom ZoomMsg

main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
