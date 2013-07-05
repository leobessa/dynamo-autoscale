# DynamoDB Autoscaling

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

# Usage

First of all, you'll need to install this project as a gem:

    $ gem install dynamo-autoscale

This will give you access to the `dynamo-autoscale` executable. The executable
takes a single argument, the path to a config file.

## Configuration

The configuration file is the central thing that `dynamo-autoscale` requires to
function. It specifies what tables to monitor, maximum and minimum throughputs
and where your ruleset is located.

The `dynamo-autoscale` executable takes a single argument, and that is the path
to the configuration file you want to use.

**A sample config can be found in the project root directory.** It documents all
of the options you can specify.

This library requires AWS keys that have access to both CloudWatch and DynamoDB,
for retriving data and sending scaling requests. Using IAM, create a new user, and
assign the 'CloudWatch Read Only Access' policy template. In addition, you will
need to use the Policy Generator to add at least the following Amazon DynamoDB actions:

  - "dynamodb:DescribeTable"
  - "dynamodb:ListTables"
  - "dynamodb:UpdateTable"

The ARN for the custom policy can be specified as '\*' to allow access to all tables,
or alternatively you can refer to the IAM documentation to limit access to specific
tables only.

### Minimal "getting started" configuration

``` yaml
:aws:
  :access_key_id:      "your_id"
  :secret_access_key:  "your_key"
  :dynamo_db_endpoint: "dynamodb.us-east-1.amazonaws.com"

# There are some example rulesets in the rulesets/ directory of this project.
:ruleset: "path_to_your_ruleset.rb"

:tables:
  - "your_table_name"

# In dry-run mode, the program will do exactly what it would normally except it
# won't touch DynamoDB at all. It will just log the changes it would have made
# in production locally.
:dry_run: true
```

Save this somewhere on your filesystem and point the `dynamo-autoscale`
executable to it:

    $ dynamo-autoscale path/to/config.yml

## Logging

By default, not a whole lot will be logged at first. If you want to be sure that
the gem is working and doing things, you can run with the `DEBUG` environment
variable set to `true`:

    $ DEBUG=true dynamo-autoscale <args...>

## Rulesets

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
the consumed capacity units is greater than 90% of the provisioned throughput
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

### The :times option

The `:times` option allows you to specify that a rule must be triggered a set
number of times in a row before its action is executed.

Example:

``` ruby
writes for: 10.minutes, greater_than: "90%", times: 3, scale: { on: :consumed, by: 1.5 }
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

Because of this, the actioner can handle the grouping up of downscales by adding
the following to your config:

``` yaml
:group_downscales: true
:flush_after: 300
```

What this is saying is that if a write downscale came in, the actioner wouldn't
fire it off immediately. It would wait 300 seconds, or 5 minutes, to see if a
corresponding read downscale was triggered and would run them both at the same
time. If no corresponding read came in, after 5 minutes the pending write
downscale would get "flushed" and applied without a read downscale.

This technique helps to save downscales on tables that may have unpredictable
consumption. You may need to tweak the `flush_after` value to match your own
situation. By default, there is no `flush_after` and downscales will wait
indefinitely, but this may not be desirable.

## Signalling

The `dynamo-autoscale` process responds to the SIGUSR1 and SIGUSR2 signals. What
we've done may be a dramatic bastardisation of what signals are intended for or
how they work, but here's what each does.

### USR1

If you send SIGUSR1 to the process as it's running, the process will dump all of
the data it has collected on all of the tables it is collecting for into CSV
files in the directory it was run in.

Example:

    $ dynamo-autoscale path/to/config.yml
    # Runs as PID 1234. Wait for some time to pass...
    $ kill -USR1 1234
    $ cat some_table.csv

The CSV is in the following format:

    time,provisioned_reads,provisioned_writes,consumed_reads,consumed_writes
    2013-07-02T10:48:00Z,800.0,600.0,390.93666666666667,30.54
    2013-07-02T10:49:00Z,800.0,600.0,390.93666666666667,30.54
    2013-07-02T10:53:00Z,800.0,600.0,386.4533333333333,95.26666666666667
    2013-07-02T10:54:00Z,800.0,600.0,386.4533333333333,95.26666666666667
    2013-07-02T10:58:00Z,800.0,600.0,110.275,25.406666666666666
    2013-07-02T10:59:00Z,800.0,600.0,246.12,54.92

### USR2

If you send SIGUSR2 to the process as it's running, the process will take all of
the data it has on all of its tables and generate a graph for each table using R
(see the Graphs section below). This is handy for visualising what the process
is doing, especially after doing a few hours of a `dry_run`.

## Scale Report Emails

If you would like to receive email notifications whenever a scale event happens,
you can specify some email options in your configuration. Specifying the email
options implicitly activates email reports. Not including your email config
implicitly turns it off.

Sample email config:

``` yaml
:email:
  :to: "john.doe@example.com"
  :from: "dynamo-autoscale@example.com"
  :via: :smtp
  :via_options:
    :port: 25
    :enable_starttls_auto: false
    :authentication: :plain
    :address: "mailserver.example.com"
    :user_name: "user"
    :password: "password"
```

We're using Pony internally to send email and this part of the config just gets
passed to Pony verbatim. Check out the [Pony](https://github.com/benprew/pony)
documentation for more details on the options it supports.

# Developers / Tooling

Everything below this part of the README is intended for people that want to
work on the dynamo-autoscale codebase or use the internal tools that we use for
testing new rulesets.

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
your actions to whatever you want. The defaults all work on local data gathered
with the `script/historic_data` executable.

## Testing rules locally

If you want to test rules on your local machine without having to query
CloudWatch or hit DynamoDB, there are tools that facilitate that nicely.

### Running a test

You can run a big batch of data all in one go with the `script/test` script.
This script can be invoked like this:

    $ script/test path/to/config.yml

You will need to make sure you have historic data available for whatever tables
you have listed in your config file. If you don't, it's easy to gather it:

    $ script/historic_data path/to/config.yml

This script goes off to CloudWatch and pulls down about a week of data for each
table you have listed in your config. Then you can continue to re-run the
`script/test` command and watch a tonne of log output fly by.

#### Graphs

If you felt so inclined, you could add the `--graph` flag to the above command
and the script will generate a graph for you at the end. This will shell out to
an R process to generate the graph, so you will need to ensure that you have R
installed on your system with the `ggplot2` and `reshape` packages installed.

Personally, I use a Mac and I attempted to install R through Homebrew but had
troubles with compiling packages. I had far more success when I installed R
straight from the R website, http://cran.r-project.org/bin/macosx/, and used
their GUI R.app to install the packages.

None of this is required to run the `dynamo-autoscale` executable in production.

### Simulating data coming in

There's a script called `script/simulator` that allows you to step through data
as it arrives. It takes the exact same arguments as the `script/test` script but
instead of running all the way through the data and generating a report,
`script/simulate` will pause after each round of new data and drop you into a
REPL. This is very handy for debugging tricky situations with your rules or the
codebase.

The simulator does not hit CloudWatch or DynamoDB at any point.

## Contributing

Report Issues/Feature requests on
[GitHub Issues](https://github.com/invisiblehand/dynamo-autoscale/issues).

#### Note on Patches/Pull Requests

 * Fork the project.
 * Make your feature addition or bug fix.
 * Add tests for it. This is important so we don't break it in a future version
 	 unintentionally.
 * Commit, do not modify the rakefile, version, or history.  (if you want to
 	 have your own version, that is fine but bump version in a commit by itself so
 	 it can be ignored when we pull)
 * Send a pull request. Bonus points for topic branches.

### About InvisibleHand

InvisibleHand is a price comparison API and browser extension which provides real-time
prices for millions of products at hundreds of retailers, and automatic price comparison.

For more information about our API and technologies, please read our [DevBlog](http://devblog.getinvisiblehand.com/).

### Copyright

Copyright (c) 2013 InvisibleHand Software Ltd. See
[LICENSE](https://github.com/invisiblehand/dynamo-autoscale/blob/master/LICENSE)
for details.
