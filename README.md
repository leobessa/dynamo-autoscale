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
  	they are tolerated for seems to vary.

This project aims to take all of this into consideration and automatically scale
your throughputs to enable you to deal with spikes and save money where
possible.

**IMPORTANT**: It's highly recommended that you read this README before
continuing. This project, if used incorrectly, has a lot of potential to cost
you huge amounts of money. Proceeding with caution is paramount, as we cannot be
held responsible for misuse that leads to excessive cost on your part.

There are tools and flags in place that will allow you to dry-run the project
before actually allowing it to change your provisioned throughputs and it is
highly recommended that you first try running the project as a dry-run and
inspecting the log output to make sure it is doing what you expect.

It is also worth noting that this project is very much in its infancy.

You have been warned.

# Configuration

This library requires AWS keys that have access to both CloudWatch and DynamoDB,
for retriving data and sending scaling requests.

The project will look for a YAML file in the following locations on start up:

  - ./aws.yml
  - ENV['AWS_CONFIG']

If it doesn't find an AWS YAML config in any of those locations, the process
prints an error and exits.

**A sample config can be found in the project root directory.**

# Usage

First of all, you'll need to install this project as a gem:

    $ gem install dynamo-autoscale

This will give you access to the `dynamo-autoscale` executable file. For some
internal documentation on the executable, you can run:

    $ dynamo-autoscale -h

This should tell you what flags you can set and what arguments the command
expects.

## Rulesets

One of the first things you'll notice upon looking into the `--help` on the
executable is that it's looking for a "rule set". What on earth is a rule set?

A rule set is the primary user input for dynamo-autoscale. It is a DSL for
specifying when to increase and decrease your provisioned throughputs. Here is a
very basic rule set:

``` ruby
reads  last: 1, greater_than: "90%", scale: { on: :consumed, by: 2 }
writes last: 1, greater_than: "90%", scale: { on: :consumed, by: 2 }

reads  for:  2.hours, less_than: "50%", min: 2, scale: { on: :consumed, by: 2 }
writes for:  2.hours, less_than: "50%", min: 2, scale: { on: :consumed, by: 2 }
```

The first two rules are designed to deal with spikes. They are saying that if
the consumed capacity units is greater than %90 of the provisioned throughput
for a single data point, scale the provisioned throughput up by the last
consumed units multipled by two.

For example, if we had a provisioned reads of 100 and a consumed units of
95 comes through, that will trigger that rule and the table will be scaled up to
have a provisioned reads of 190.

The last two rules are controlling downscaling. Because downscaling can only
happen 4 times per day per table, the rules are far less aggressive. Those rules
are saying: if the consumed capacity is less than 50% of the provisioned for a
whole two hours, with a minimum of 2 data points, scale the provisioned
throughput to the consumed units multipled by 2.

### The :last and :for options

These options declare how many points or what time range you want to examine. If
you don't specify a `:min` or `:max` option, they will just get as many points
as they can and evaluate the rest of the rule even if they don't get a full 2
hours of data, or a full 6 points of data. This only affects the start of the
process's lifetime, eventually it will have enough data to always get the full
range of points you're asking for.

### The :min and :max options

If you're not keen on asking for 2 hours of data and not receiving the full
range before evaluating the rest of the rule, you can specify a minimum or
maximum number of points to evaluate. Currently, this only supports a numeric
value. So you can ask for at least 20 points to be present like so:

### The :greater_than and :less_than options



``` ruby
reads for: 2.hours, less_than: "50%", min: 20, scale: { on: :consumed, by: 2 }
```

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
script called `script/historic_data` that you can run to gather data on a
specific table and store it into the `data/` directory in a format that all of
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
