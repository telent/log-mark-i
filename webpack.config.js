const path = require('path');

module.exports = {
    entry: './logmarki/static/graph.ts',
    devtool: 'inline-source-map',
    mode: 'production',
    module: {
	rules: [
	    {
		test: /\.tsx?$/,
		use: 'ts-loader',
		exclude: /node_modules/,
	    },
	],
    },
    resolve: {
	extensions: [ '.tsx', '.ts', '.js' ],
    },
    output: {
	filename: 'bundle.js',
	path: path.resolve(__dirname, 'logmarki/static/'),
    },
};
