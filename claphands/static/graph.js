var margin = {top: 50, right: 50, bottom: 50, left: 50}
, width = window.innerWidth - margin.left - margin.right // Use the window's width
, height = window.innerHeight - margin.top - margin.bottom; // Use the window's height

var parseTime = d3.isoParse;
var formatTime = d3.timeFormat("%e %B %H:%m");

var divTooltip = d3.select("body").append("div")
    .attr("class", "tooltip")
    .style("opacity", 0);

var xScale = d3.scaleTime();
var yScale = d3.scaleLinear();
var fatScale = d3.scaleLinear();

var svg = d3.select("body").append("svg")
    .attr("class", "svg")
    .attr("width", width + margin.left + margin.right)
    .attr("height", height + margin.top + margin.bottom)
    .append("g")
    .attr("transform", "translate(" + margin.left + "," + margin.top + ")");

var timeNow = new Date();
var dateExtent = [d3.timeDay.offset(timeNow, -60),
                  timeNow];

var data;

function reload_data() {
    let [startDate, endDate] = dateExtent.map(d => d.getTime());
    d3.json("/weights.json?start=" + startDate + "&end=" +endDate)
        .then(payload => { data = payload; refresh_view();});
}

function tooltipText(datum) {
    var f = new Intl.NumberFormat(navigator.language,
                                  { maximumSignificantDigits: 3 })
    return formatTime(datum.date) + "<br/>" +
        f.format(datum.weight) + "kg" + "<br/>" +
        f.format(datum.fat_ratio) + "%";
}

function popupForMeasure(index, datum, x, y)
{
    d3.select("circle.focus").attr("class", "dot");
    d3.select("circle:nth-child("+ (index +1 )+")").attr("class", "focus");

    divTooltip.transition()
        .duration(200)
        .style("opacity", 0.7)
    divTooltip.html(tooltipText(datum))
        .style("left", x + "px")
        .style("top", (y - 50) + "px");
}

function refresh_view() {
    width = window.innerWidth - margin.left - margin.right;
    height = window.innerHeight - margin.top - margin.bottom;

    svg.selectAll('*').remove();
    var listenerRect = svg.append('rect')
        .attr('class', 'listener-rect')
        .attr('x', 0)
        .attr('y', -margin.top)
        .attr('width', window.innerWidth)
        .attr('height', height + margin.top + margin.bottom)
        .style('opacity', 0);

    let earlier = null, lambda = 0.10/86400000;

    svg
        .attr("width", width + margin.left + margin.right)
        .attr("height", height + margin.top + margin.bottom);

    xScale
        .range([0, width])
        .domain(dateExtent);
    data.forEach(function(d, i) {
        d.date = parseTime(d.date);
        if(earlier) {
            let lag = earlier.date - d.date, // milliseconds
                m = Math.exp(-lag*lambda);
            earlier.weight = (1-m)*d.weight + (m)*earlier.weight
            d.fat_ratio = d.fat_ratio || earlier.fat_ratio;
            earlier.fat_ratio = (1-m)*d.fat_ratio + (m)*earlier.fat_ratio;
            // lag is ms since last point. we want to make intensity 0
            // if this point will be too close to the previous point
            // (overlapping or touching)
            if(xScale(earlier.date) - xScale(d.date) > 10)
                d.intensity = Math.max(0.2, Math.min(1,lag/86400000.0));
            else
                d.intensity = 0.2;
        } else {
            earlier = { weight: d.weight, fat_ratio: d.fat_ratio };
            d.intensity = 1;
        }
        earlier.date = d.date;
        d.fat_trend = earlier.fat_ratio;
        d.weight_trend = earlier.weight;
    });

    yScale
        .range([height, 0])
        .domain(d3.extent(data, d => d.weight))
        .nice();
    fatScale
        .range([height, 0])
        .domain(d3.extent(data, d => d.fat_ratio))
        .nice();

    var xAxis = d3.axisBottom(xScale);
    var gx = svg.insert("g", ":first-child")
        .attr("transform", "translate(0," + height + ")")
        .call(xAxis);

    var gy = svg.insert("g", ":first-child")
        .attr("class", "yaxis")
        .call(d3.axisLeft(yScale));

    svg.insert("g", ":first-child")
        .attr("class", "fataxis")
        .attr("transform", "translate(" + width + ",0)")
        .call(d3.axisRight(fatScale));

    var weightLine = d3.line()
        .x(d => xScale(d.date))
        .y(d => yScale(d.weight_trend))
        .curve(d3.curveBasis);

    var fatLine = d3.line()
        .x(d => xScale(d.date))
        .y(d => fatScale(d.fat_trend))
        .curve(d3.curveBasis)

    svg.insert("path", ":first-child")
        .datum(data)
        .attr("class", "weightLine")
        .attr("d", weightLine);

    function mousemove_cb() {
        var [x,y] = d3.mouse(d3.event.target);
        var index = nearest_measure(data, xScale.invert(x));
        if(index<0) index=0;
        popupForMeasure(index, data[index], x, y);
    };

    svg.append("path")
        .datum(data)
        .attr("class", "invisibleLine")
        .attr("d", weightLine)
        .on("mousemove", mousemove_cb);
    svg.append("path")
        .datum(data)
        .attr("class", "invisibleLine")
        .attr("d", fatLine)
        .on("mousemove", mousemove_cb);

    svg.insert("path", ":first-child")
        .datum(data)
        .attr("class", "fatLine")
        .attr("d", fatLine);

    var gDots = svg
        .append('g')    // after the listener
        .attr('class', 'dots-group');

    dots = gDots.selectAll(".dot")
        .data(data)
        .enter().append("circle")
        .attr("class", "dot")
        .attr("cx", function(d) { return xScale(d.date) })
        .attr("cy", function(d) { return yScale(d.weight) })
        .attr("opacity", function(d) { return d.intensity; })
        .attr("r", 5);

    var zoom = d3.zoom()
        .on("zoom", zooming)
        .on("end", zoomed);

    function zooming() {
        var transform = d3.event.transform;
        var newScale = transform.rescaleX(xScale);
        xAxis.scale(newScale);
        gx.call(xAxis);
        weightLine.x(function (d) { return newScale(d.date); });
        fatLine.x(function (d) { return newScale(d.date); });
        svg.select("path.weightLine").attr("d", weightLine);
        svg.select("path.fatLine").attr("d", fatLine);
        dots.attr('cx', function(d) { return newScale(d.date); })
    };
    function zoomed() {
        var transform = d3.event.transform;
        var newScale = transform.rescaleX(xScale);
        var newD = newScale.domain(),
            oldD = xScale.domain();
        dateExtent = newD;
        if(newD[0]<oldD[0] || newD[1]>oldD[1]) {
            setTimeout(reload_data);
        } else {
            setTimeout(refresh_view);
        }
    };
    listenerRect.call(zoom);
}

function nearest_measure(data, timestamp, s, e)
{
    // find oldest element newer than timestamp in the array
    // of data, noting that data is ordered most-recent-first

    // invariant: the interval data[s,e) which contains an
    // element > timestamp next to another element <= timestamp.  To
    // make this hold at the edges, we deem elements outside of the
    // array to have timestamps Inf or 0 as appropriate

    s = s || 0;
    e = e || data.length;

    if(e == s) return s;
    if(e == s+1) {
        // terminating
        console.assert((s<0) || (data[s].date  > timestamp),
                       "start", s, data[s], timestamp);
        console.assert((e>=data.length || (data[e].date  <= timestamp),
                        "end", e, data[e], timestamp));
        return s;
    }

    var mid = Math.floor((e + s) /2);

    if(data[mid].date > timestamp)
        return nearest_measure(data, timestamp, mid, e);
    else
        return nearest_measure(data, timestamp, s, mid);
}

function debounce(event, f) {
    let inner = () => {
        var timeout= null;
        window.addEventListener(event, (e) => {
            if(! timeout)
                timeout = window.requestAnimationFrame(() => {
                    f();
                    timeout = null;
                })
        });
    };
    inner()
};

debounce('resize', refresh_view);
debounce('orientationchange', refresh_view);

reload_data();
