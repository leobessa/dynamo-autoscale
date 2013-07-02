# DynamoDB Autoscaling

*IMPORTANT*: It's highly recommended that you read this README before
continuing. This project, if used incorrectly, has a lot of potential to cost
you huge amounts of money. Proceeding with caution is paramount, as we cannot be
held responsible for misuse that leads to excessive cost on your part.

There are tools and flags in place that will allow you to dry-run the project
before actually allowing it to change your provisioned throughputs and it is
highly recommended that you first try running the project as a dry-run and
inspecting the log output to make sure it is doing what you expect.

It is also worth noting that this project is very much in its infancy.

You have been warned.

## Rules of the game

Welcome to the delightful mini-game that is DynamoDB provisioned throughputs.
Here are the rules of the game:

  - In a single API call, you can only change your throughput by up to 100% in
  	either direction. In other words, you can decrease as much as you want but
  	you can only increase to up to double what the current throughput is.

  - You may scale up as many times per day as you like, however you may only
  	scale down 4 times per day per table. (If you scale both reads and writes
  	down in the same request, that only counts as 1 downscale used)

  - Scaling is not an instantaneous event. It can take up to 5 minutes for a
  	table's throughput to be updated.

  - Small spikes over your threshold are tolerated but the exact amount of time
  	they are tolerated for seems to vary.

This project aims to take all of this into consideration and automatically scale
your throughputs to enable you to deal with spikes and save money where
possible.

# Configuration

This library requires AWS keys that have access to both CloudWatch and DynamoDB,
for retriving data and sending scaling requests.

The project will look for a YAML file in the following locations on start up:

  - ./aws.yml
  - ENV['AWS_CONFIG']

If it doesn't find an AWS YAML config in any of those locations, the process
prints an error and exits.

*A sample config can be found in the project root directory.*

# Usage

First of all, you'll need to install this project as a gem:

    $ gem install dynamo-autoscale

This will give you access to the `dynamo-autoscale` executable. For some
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

You would put this ruleset in a file and then pass that file in as the first
argument to `dynamo-autoscale` on the command line.

The first two rules are designed to deal with spikes. They are saying that if
the consumed capacity units is greater than %90 of the provisioned throughput
for a single data point, scale the provisioned throughput up by the last
consumed units multiplied by two.

For example, if we had a provisioned reads of 100 and a consumed units of
95 comes through, that will trigger that rule and the table will be scaled up to
have a provisioned reads of 190.

The last two rules are controlling downscaling. Because downscaling can only
happen 4 times per day per table, the rules are far less aggressive. Those rules
are saying: if the consumed capacity is less than 50% of the provisioned for a
whole two hours, with a minimum of 2 data points, scale the provisioned
throughput to the consumed units multiplied by 2.

### The :last and :for options

These options declare how many points or what time range you want to examine.
They're aliases of each other and if you specify both, one will be ignored. If
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

``` ruby
reads for: 2.hours, less_than: "50%", min: 20, scale: { on: :consumed, by: 2 }
```

### The :greater_than and :less_than options

You must specify at least one of these options for the rule to actually validate
without throwing an error. Having neither makes no sense.

You can specify either an absolute value or a percentage specified as a string.
The percentage will calculate the percentage consumed against the amount
provisioned.

Examples:

``` ruby
reads for: 2.hours, less_than: 10, scale: { on: :consumed, by: 2 }

reads for: 2, less_than: "20%", scale: { on: :consumed, by: 2 }
```

### The :scale option

The `:scale` option is a way of doing a simple change to the provisioned
throughput without having to specify repetitive stuff in a block. `:scale`
expects to be a hash and it expects to have two keys in the hash: `:on` and
`:by`.

`:on` specifies what part of the metric you want to scale on. It can either by
`:provisioned` or `:consumed`. In most cases, `:consumed` makes a lot more sense
than `:provisioned`.

`:by` specifies the scale factor. If you want to double the provisioned capacity
when a rule triggers, you would write something like this:

``` ruby
reads for: 2.hours, less_than: "30%", scale: { on: :provisioned, by: 0.5 }
```

And that would half the provisioned throughput for reads if the consumed is
less than 30% of the provisioned for 2 hours.

### Passing a block

If you want to do something a little bit more complicated with your rules, you
can pass a block to them. The block will get passed three things: the table the
rule was triggered for, the rule object that triggered and the actioner for that
table.

An actioner is an abstraction of communication with Dynamo and it allows
communication to be faked if you want to do a dry run. It exposes a very simple
interface. Here's an example:

``` ruby
writes for: 2.hours, greater_than: 200 do |table, rule, actioner|
  actioner.set(:writes, 300)
end
```

This rule will set the provisioned write throughput to 300 if the consumed
writes are greater than 200 for 2 hours. The actioner handles a tonne of things
under the hood, such as making sure you don't scale up more than you're allowed
to in a single call and making sure you don't try to change a table when it's in
the updating state.

It also handles the grouping of downscales, which we will talk about in a later
section of the README.

The `table` argument is a `TableTracker` object. For a run down of what
information is available to you I advise checking out the source code in
`lib/dynamo-autoscale/table_tracker.rb`.

### The :count option

The `:count` option allows you to specify that a rule must be triggered a set
number of times in a row before its action is executed.

Example:

``` ruby
writes for: 10.minutes, greater_than: "90%", count: 3, scale: { on: :consumed, by: 1.5 }
```

This says that is writes are greater than 90% for 10 minutes three checks in a
row, scale by the amount consumed multiplied by 1.5. A new check will only
happen when the table receives new data from cloud watch, which means that the
10 minute windows could potentially overlap.

## Downscale grouping

You can downscale reads or writes individually and this will cost you one of
your four downscales for the current day. Or, you can downscale reads and writes
at the same time and this also costs you one of your four. (Reference:
http://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Limits.html)

Because of this, the actioner can handle the grouping up of downscales. Let's
say you passed in the following options in at the command line:

    $ dynamo-autoscale some/ruleset.rb some_table --group-downscales --flush-after 300

What this is saying is that if a write downscale came in, the actioner wouldn't
fire it off immediately. It would wait 300 seconds, or 5 minutes, to see if a
corresponding read downscale was triggered and would run them both at the same
time. If no corresponding read came in, after 5 minutes the pending write
downscale would get "flushed" and applied without a read downscale.

This technique helps to save downscales on tables that may have unpredictable
consumption. You may need to tweak the `--flush-after` value to match your own
situation. By default, there is no `--flush-after` and downscales will wait
indefinitely, this may not be desirable.

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
