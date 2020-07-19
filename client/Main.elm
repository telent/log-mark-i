module Main exposing (main)


import Axis
import Color
import Path exposing (Path)
import Scale exposing (ContinuousScale)
import Shape
import Time
import TypedSvg exposing (g, svg)
import TypedSvg.Attributes exposing (class, fill, stroke, transform, viewBox)
import TypedSvg.Attributes.InPx exposing (strokeWidth)
import TypedSvg.Core exposing (Svg)
import TypedSvg.Types exposing (Paint(..), Transform(..))


w : Float
w =
    900


h : Float
h =
    450


padding : Float
padding =
    30

type alias Measure = ( Time.Posix, Float )

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


-- line : List Measure -> Path
line model =
    let transformToLineData (x, y) =
            Just ( Scale.convert (xScale model) x, Scale.convert (yScale model) y )
    in
    List.map transformToLineData model
        |> Shape.line Shape.monotoneInXCurve


-- exponential moving average, needs translating to elm
-- +type XtPoint = [Date, number];
-- +
-- +function smooth_ema(points : XtPoint[]) : XtPoint[] {
-- +    return points;
-- +    const lambda = 0.10/86400000;
-- +    let [prev_t, smooth_y] = points[0];
-- +    return points.map(d => {
-- +       let [t, y] = d;
-- +       let lag = +t - (+prev_t),
-- +           m = Math.exp(-lambda * lag);
-- +       smooth_y = (1-m) * y + m * smooth_y;
-- +       return [t, smooth_y];
-- +    });
-- +}
-- +


-- area : List Measure -> Path
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


view : List Measure -> Svg msg
view model =
    svg [ viewBox 0 0 w h ]
        [ g [ transform [ Translate (padding - 1) (h - padding) ] ]
            [ xAxis model ]
        , g [ transform [ Translate (padding - 1) padding ] ]
            [ yAxis model ]
        , g [ transform [ Translate padding padding ], class [ "series" ] ]
            [ Path.element (area model) [ strokeWidth 3, fill <| Paint <| Color.rgba 1 0 0 0.54 ]
            , Path.element (line model) [ stroke <| Paint <| Color.rgb 1 0 0, strokeWidth 3, fill PaintNone ]
            ]
        ]



-- From here onwards this is simply example boilerplate.
-- In a real app you would load the data from a server and parse it, perhaps in
-- a separate module.

timeSeries = List.map (\x -> ((Time.millisToPosix (x*86400*250 + 1458928000000)), toFloat (60 + (modBy 5 x)))) (List.range 1 100)

main =
    view timeSeries
