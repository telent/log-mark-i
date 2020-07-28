module Main exposing (main)


import Axis
import Browser
import Color exposing (Color)
import Html exposing (Html, button, div, text)
import Html.Events exposing (onClick)
import Http
import Iso8601
import Json.Decode as JD exposing (field, Decoder, int, string)
import Path exposing (Path)
import Scale exposing (ContinuousScale)
import Shape
import Task
import Time
import TypedSvg exposing (g, svg)
import TypedSvg.Attributes as SvgA exposing (class, fill, stroke, transform, viewBox)
import TypedSvg.Attributes.InPx exposing (strokeWidth)
import TypedSvg.Core exposing (Svg)
import TypedSvg.Types exposing (Paint(..), Transform(..), px)
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
type alias Series = { name: MeasureName
                    , scale: ContinuousScale Float
                    , color: Color
                    , measures: List Measure  }
type PendingRequest = None | Started Time.Posix

type alias Model = { series: List Series
                   , zoom: Zoom
                   , dates: (Time.Posix, Time.Posix)
                   , initialDates: (Time.Posix, Time.Posix)
                   , pendingRequest: PendingRequest
                   , smoothness: Float }



seriesOf : Model -> MeasureName -> Maybe Series
seriesOf model name =
    case List.filter (\s -> s.name == name) model.series of
        [] -> Nothing
        series :: [] -> Just series
        series :: _ -> Nothing

spy a =
    let _ = Debug.log "spy" a
    in a

-- we have different sets of start/end
--  - the model dates
--  - the visible dates
-- if the visible dates are outside the range of the model dates,
--  we need to fetch new data and update the model dates.

-- The visible dates are a function of the initial visible dates and the zoom.
--  Unless we want to reset the zoom level every time we load data, we
--  cannot treat initial visible dates and model dates as the same thing

-- having observed that we need to fetch data, we should store
-- somewhere that we've asked for more, so that we don't ask for it
-- again 60 times a second until it arrives. Ideally we do this without
-- clobbering the model dates, so that in future we can get elaborate
-- about merging new and existing data. Also store the request timestamp
-- so that we can signal error/retry later if no reply


visibleDates model =
    let scale = (Zoom.asRecord model.zoom).scale
        (startDate, endDate) = model.initialDates
        startT = Time.posixToMillis startDate
        endT = Time.posixToMillis endDate
        midT = toFloat (startT + endT)/2
        newTimeRange = toFloat (endT - startT)/scale
    in
        ( Time.millisToPosix (round (midT - newTimeRange/2))
        , Time.millisToPosix (round (midT + newTimeRange/2)))


xScale : Model -> ContinuousScale Time.Posix
xScale model =
    Scale.time Time.utc ( 0, w - 2 * padding ) (visibleDates model)

-- we need a separate yscale for each mass measure, but they should
-- differ in offset only, not in scale, so they're related.

extentHeight : (Float, Float) ->  Float
extentHeight (lower, upper) = upper - lower

yExtent : List Measure -> (Float, Float)
yExtent measures =
    let ys = List.map Tuple.second measures
        max = Maybe.withDefault 0 (List.maximum ys)
        min = Maybe.withDefault max (List.minimum ys)
    in (min, max)

yScales massMeasures fatMassMeasures =
    let massExtent = (yExtent massMeasures)
        fatExtent = (yExtent fatMassMeasures)
        height = max (extentHeight massExtent) (extentHeight fatExtent)
        mkScale ex = Scale.linear ( h - 2 * padding, 0 )
                  ( Tuple.first ex, height + Tuple.first ex) |> (Scale.nice 10)
    in (mkScale massExtent, mkScale fatExtent)

xAxis : Model -> Svg msg
xAxis model =
    Axis.bottom [ Axis.tickCount 10 ] (xScale model)

yAxis : Model -> Svg msg
yAxis model =
    g [] [ (case seriesOf model FatMass of
                Nothing -> g [] []
                Just series -> g [ class ["fat"]] [ Axis.right [ Axis.tickCount 5 ] series.scale])
         , (case seriesOf model Mass of
                Nothing -> g [] []
                Just series -> g [ class ["mass"]] [ Axis.left [ Axis.tickCount 5 ] series.scale])
         ]

line : ContinuousScale Time.Posix ->
       ContinuousScale Float ->
       List Measure ->
       Path

line xscale yscale measures =
    let transformToLineData (x, y) =
            Just ( Scale.convert xscale x, Scale.convert yscale y )
    in
    List.map transformToLineData measures
        |> Shape.line Shape.monotoneInXCurve

points xscale yscale color measures =
    let transformToLineData (x, y) =
            ( Scale.convert xscale x, Scale.convert yscale y )
    in
        List.map (\m ->
                      let (x, y) = transformToLineData m
                      in TypedSvg.rect [ SvgA.x (px  (x-2))
                                       , SvgA.y (px (y-2))
                                       , SvgA.width (px 4)
                                       , SvgA.height (px 4)
                                       , SvgA.rx (px 1)
                                       , SvgA.ry (px 1)
                                       , fill <| Paint color] [] )
            measures

timeInterval later earlier =
    Time.posixToMillis later - Time.posixToMillis earlier

timeBefore time seconds =
    Time.millisToPosix ((Time.posixToMillis time) - 1000 * seconds)

intervalWithin (start1, end1) (start2, end2) =
    let earlier a b =  (Time.posixToMillis a) <= (Time.posixToMillis b)
        later a b = earlier b a
    in (later start1 start2) && (earlier end1 end2)


smoothMeasures : Float -> List Measure -> List Measure
smoothMeasures factor measures =
    let lambda = factor/86400000
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
    let {name, scale, color} = series
        xscale = xScale model
        measures = List.filter
                   (\(t, _) -> intervalWithin (t,t) (visibleDates model))
                   series.measures
        smooth = smoothMeasures model.smoothness
    in
    g [ transform [ Translate padding padding ], class [ "series" ] ]
        [ g [] (points xscale scale color measures)
        , Path.element (line xscale scale (smooth measures))
              [ stroke <| Paint <| color, strokeWidth 2, fill PaintNone ]
        ]

viewPending pending =
    case pending of
        None -> div [] [text "Ready"]
        Started ts -> div [] [text "Refreshing"]

view : Model -> Html Msg
view model =
    let attrs = [ viewBox 0 0 w h
                ] ++ (Zoom.events model.zoom ZoomMsg)
    in
    div []
        [ viewPending model.pendingRequest
        , svg attrs
              ([ g [ transform [ Translate (padding - 1) (h - padding) ] ]
                   [ xAxis model ]
               , g [ transform [ Translate (padding - 1) padding ] ]
                   [ yAxis model ]] ++
                   (List.map (viewSeries model) model.series))
        , button [ onClick SmoothMore ] [ text "smoother" ]
        , button [ onClick SmoothLess ] [ text "rougher" ]]

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


getNow = Time.now |> Task.perform SetNow

type Msg
    = RefreshData
    | SetNow Time.Posix
    | ZoomMsg OnZoom
    | DataReceived (Result Http.Error (List MeasureJson))
    | SmoothMore
    | SmoothLess
    | Tick Time.Posix


init : () -> (Model, Cmd Msg)
init _  =
    let z = Zoom.init { width = w-2*padding, height = h-2*padding }
        model = { zoom = z
                , series = []
                , initialDates = ( Time.millisToPosix 0 , Time.millisToPosix 0)
                , dates = ( Time.millisToPosix 0 , Time.millisToPosix 0)
                , pendingRequest = None
                , smoothness = 0.1
                }
    in (model, getNow)

parseDate possibleString =
    case (Iso8601.toTime possibleString) of
        Ok val -> val
        Err _ -> Time.millisToPosix 0

newModelForJson model json =
    let massMeasures =
            List.map (\m -> (parseDate m.date, m.mass)) json
        fatMassMeasures =
            List.filterMap (\{date, fatMass} ->
                                case fatMass of
                                    Just m -> Just ((parseDate date), m)
                                    Nothing -> Nothing)
                json
        (massScale, fatScale) = yScales massMeasures fatMassMeasures
        s = [ Series Mass
                  massScale
                  (Color.rgb 0.4 0.9 0)
                  massMeasures,
              Series FatMass
                  fatScale
                  (Color.rgb 1 0 0)
                  fatMassMeasures]
    in { zoom = model.zoom
       , dates = model.dates
       , initialDates = model.initialDates
       , series = s
       , pendingRequest = None
       , smoothness = 0.1
       }


updateData model result =
    case result of
        Ok json ->
            (newModelForJson model (List.reverse json), Cmd.none)
        Err httpError ->
            let _ = Debug.log "errir" httpError
            in (model, Cmd.none)


refreshIfNeeded model ts =
    if  intervalWithin (visibleDates model) model.dates
        && model.pendingRequest == None
    then
        ( model, Cmd.none )
    else
        let model1 = { model
                        | pendingRequest = Started ts
                        ,  dates = (visibleDates model) }
        in (model1, getData model1)

update : Msg -> Model -> (Model, Cmd Msg )
update msg model =
    case msg of
        RefreshData -> ( model , getData model)
        DataReceived result -> updateData model result
        SmoothMore -> ( { model | smoothness = model.smoothness - 0.01 },
                            Cmd.none)
        SmoothLess -> ( { model | smoothness = model.smoothness + 0.01 },
                            Cmd.none)
        SetNow time ->
            let newModel =
                    { model
                        | initialDates = (timeBefore time (86400*60), time) }
            in (newModel, getData newModel)
        Tick time -> refreshIfNeeded model time
        ZoomMsg zm ->
            let newZoom = Zoom.update zm model.zoom
            in ( { model | zoom = newZoom }, Cmd.none )


subscriptions model =
    Sub.batch [ Zoom.subscriptions model.zoom ZoomMsg
              , Time.every 500 Tick]

main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
