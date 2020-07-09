var margin = {top: 50, right: 50, bottom: 50, left: 50}
, width = window.innerWidth - margin.left - margin.right // Use the window's width
, height = window.innerHeight - margin.top - margin.bottom; // Use the window's height

var parseTime = d3.isoParse;
var formatTime = d3.timeFormat("%e %B %H:%m");

var divTooltip = d3.select("body").append("div")
    .attr("class", "tooltip")
    .style("opacity", 0);

var divBattery = d3.select("body").append("div")
    .attr("class", "battery");

var xScale = d3.scaleTime();
var yScale = d3.scaleLinear();
var fatScale = d3.scaleLinear();

var svg = d3.select("body").append("svg")
    .attr("class", "svg")
    .attr("width", width + margin.left + margin.right)
    .attr("height", height + margin.top + margin.bottom)
    .append("g")
    .attr("transform", "translate(" + margin.left + "," + margin.top + ")");

var refreshButton = d3.select("body").append("img")
    .attr("class", "iconify refresh")
    .attr("src", "/static/refresh.svg");

var timeNow = new Date();
var dateExtent = [d3.timeDay.offset(timeNow, -60),
                  timeNow];

var data;

function promptForReloadPage(message) {
    d3.select("body").insert("div", ":first-child")
	.attr("class", "flash")
	.html("<p><b>Received an error from Withings:</b> " + message +
	      "<p>Try reloading the page")
	.insert("button", ":first-child")
	.html("Reload now")
	.on('click', () => { window.location.reload(); });
}

function reload_data() {
    let [startDate, endDate] = dateExtent.map(d => d.getTime());
    d3.json("/weights.json?start=" + startDate + "&end=" +endDate)
        .then(payload => { data = payload; refresh_view();})
	.catch(err => {
	    if(err.message.startsWith("403")) promptForReloadPage(err.message);
	});
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
    d3.selectAll("circle.focus").attr("class", "dot");
    d3.select("circle:nth-child("+ (index +1 )+")").attr("class", "focus");
    d3.selectAll("rect.focus").attr("class", "fatdot");
    d3.select("rect.fatdot:nth-child("+ (index +1 )+")").attr("class", "focus");

    divTooltip.transition()
        .duration(200)
        .style("opacity", 0.7)
    divTooltip.html(tooltipText(datum))
        .style("left", x + "px")
        .style("top", (y - 50) + "px");
}

function mousemove_cb() {
    var [x,y] = d3.mouse(d3.event.target);
    var index = nearest_measure(data, xScale.invert(x));
    if(index<0) index=0;
    popupForMeasure(index, data[index], x, y);
};

function lineForMeasure(scale, key) {
    return d3.line()
        .x(d => xScale(d.date))
        .y(d => scale(d[key]))
        .curve(d3.curveBasis)
}

function attrs_for_invisible_line(path, line, dots_selection) {
    path.attr("class", "invisibleLine")
        .attr("d", line)
	.attr("stroke-linecap", "round")
	.on("mouseover",
	    () => { dots_selection.attr("visibility", "visible") })
	.on("mouseleave",
	    () => { dots_selection.attr("visibility", "hidden") })
        .on("mousemove", mousemove_cb);
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

    var gStripes = svg
        .insert('g', ':first-child')
        .attr('class', 'stripes');

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

    var weightLine = lineForMeasure(yScale, 'weight_trend')
    var fatLine = lineForMeasure(fatScale, 'fat_trend')

    svg.insert("path", ":first-child")
        .datum(data)
        .attr("class", "weightLine")
        .attr("d", weightLine);

    svg.insert("path", ":first-child")
        .datum(data)
        .attr("class", "fatLine")
        .attr("d", fatLine);

    gStripes.selectAll(".weekend")
	.data(xScale.ticks(d3.timeWeek).map(d=>d3.timeSaturday(d)))
	.enter()
	.append("rect")
	.attr("x",
	      d => xScale(d))
	.attr("y", 0)
	.attr("width",
	      d => xScale(d3.timeMonday.ceil(d)) - xScale(d))
	.attr("height", -yScale(height))

    var gDots = svg
        .append('g')    // after the listener
	.attr("visibility", "hidden")
        .attr('class', 'dots-group');

    dots = gDots.selectAll(".dot")
        .data(data)
        .enter().append("circle")
        .attr("class", "dot")
        .attr("cx", function(d) { return xScale(d.date) })
        .attr("cy", function(d) { return yScale(d.weight) })
        .attr("opacity", function(d) { return d.intensity; })
        .attr("r", 5);

    var gFatDots = svg
        .append('g')    // after the listener
	.attr("visibility", "hidden")
        .attr('class', 'fat-dots-group');

    fatDots = gFatDots.selectAll(".fatdot")
        .data(data)
        .enter().append("rect")
        .attr("class", "fatdot")
        .attr("x", function(d) { return xScale(d.date)-4; })
        .attr("y", function(d) {
	    return fatScale(d.fat_ratio)-4;
	})
        .attr("opacity", function(d) { return d.intensity; })
        .attr("width", 8)
	.attr("height", 8);

    attrs_for_invisible_line(svg.append("path").datum(data),
			     weightLine, gDots);
    attrs_for_invisible_line(svg.append("path").datum(data),
			     fatLine, gFatDots);
    var zoom = d3.zoom()
        .on("zoom", zooming)
        .on("end", zoomed);

    function zooming() {
        var transform = d3.event.transform;
        var newScale = transform.rescaleX(xScale);
        xAxis.scale(newScale);
        gx.call(xAxis);
        weightLine.x(function (d) { return newScale(d.date); });
	gStripes.selectAll("g.stripes rect").attr('x', d => newScale(d));
        fatLine.x(function (d) { return newScale(d.date); });
        svg.select("path.weightLine").attr("d", weightLine);
        svg.select("path.fatLine").attr("d", fatLine);
        dots.attr('cx', function(d) { return newScale(d.date); })
	fatDots.attr('x', function(d) { return newScale(d.date)-3; })
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
	var startdate = (s<0) ? (new Date()) : data[s].date;
	var enddate = (e>=data.length) ? (new Date(0)) : data[e].date;
        console.assert((startdate  > timestamp),
                       "start", s, data[s], timestamp);
        console.assert((enddate <= timestamp),
                       "end", e, data[e], timestamp);
	var dleft = startdate - timestamp;
	var dright = timestamp - enddate;
	return (dleft < dright) ? s : e
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

function updateBattery(devices) {
    var [deviceClass, model, battery] = devices[0];
    divBattery.html(model + " " + deviceClass +
		    ": " + battery + " battery");
}

d3.json("/device").then(updateBattery);
window.setInterval(() => { d3.json("/device").then(updateBattery) },
		   10*60*1000);


refreshButton.on('click', reload_data);
reload_data();
