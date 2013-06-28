# DynamoDB Autoscaling

Welcome to the delightful mini-game that is DynamoDB provisioned throughputs.
Here are the rules of the game:

  - In a single API call, you can only change your threshold by up to 100% in
  	either direction. In other words, you can decrease as much as you want but
  	you can only increase to up to double what the current threshold is.

  - You may scale up as many times per day as you like, however you may only
  	scale down 4 times per day per table. (If you scale both reads and writes
  	down in the same request, that only counts as 1 scale used)

  - Scaling is not an instantaneous event.

  - Small spikes over your threshold are tolerated but the exact amount of time
  	they are tolerated for varies.

# Configuration

This library requires AWS keys that have access to both CloudWatch and DynamoDB,
for retriving data and sending scaling requests.

The project will look for a YAML file in the following locations on start up:

  - ./aws.yml
  - ENV['AWS_CONFIG']
  - [project_root]/config/aws.yml

If it doesn't find an AWS YAML config in any of those locations, the process
prints an error and exits.

A sample config can be found in the project root directory.

# Usage

TODO: Make the project usable. Roffle.

# Developers

Everything below this part of the README is intended for people that want to
work on the dynamo-autoscale codebase.

## Technical details

The code has a set number of moving parts that are globally available and must
implement certain interfaces (for exact details, you would need to study the
code):

  - `DynamoAutoscale.poller`: This component is responsible for pulling data
  	from a data source (CloudWatch or Local at the moment) and piping it into
  	the next stage in the pipeline.

  - `DynamoAutoscale.dispatcher`: The dispatcher takes data from the poller and
  	populates a hash table of `TableTracker` objects, as well as checking to see
  	if any of the tables have triggered any rules.

  - `DynamoAutoscale.rules`: The ruleset contains an array of `Rule` objects
  	inside a hash table keyed by table name. The ruleset initializer takes a
  	file path as an argument, or a block, either of these needs to contain a set
  	of rules (examples can be found in the `rulesets/` directory).

  - `DynamoAutoscale.actioners`: The actioners are what perform provision scaling.
  	Locally this is faked, in production it makes API calls to DynamoDB.

  - `DynamoAutoscale.tables`: This is a hash table of `TableTracker` objects,
  	keyed on the table name.

All of these components are globally available because most of them need access
to each other and it was a pain to pass instances of them around to everybody
that needed them.

They're also completely swappable. As long as they implement the right methods
you can get your data from anywhere, dispatch your data to anywhere and send
your actions to whatever you want. The defaults all work on local data.

## Testing rules locally

If you want to test rules on your local machine without having to query
CloudWatch or hit DynamoDB, there are tools that facilitate that nicely.

The first thing you would need to do is gather some historic data. There's a
script called `script/historic_data` that you can run to gather data on all of
your tables and store them into the `data/` directory in a format that all of
the other scripts are familiar with.

Next there are a couple of things you can do.

### Running a test

You can run a big batch of data all in one go with the `script/test` script.
This script can be invoked like this:

    $ script/test rulesets/default.rb table_name

Substituting `table_name` with the name of a table that exists in your DynamoDB.
This will run through all of the data for that table in time order, logging
along the way and triggering rules from the rule set if any were defined.

At the end, it shows you a report on the amount of wasted, used and lost units.

#### Graphs

If you felt so inclined, you could add the `--graph` flag to the above command
and the script will generate a graph for you at the end. This will shell out to
an R process to generate the graph, so you will need to ensure that you have R
installed on your system with the `ggplot2` and `reshape` packages installed.

### Simulating data coming in

There's a script called `script/simulator` that allows you to step through data
as it arrives. It takes the exact same arguments as the `script/test` script but
instead of running all the way through the data and generating a report,
`script/simulate` will pause after each round of new data and drop you into a
REPL. This is very handy for debugging tricky situations with your rules or the
codebase.
