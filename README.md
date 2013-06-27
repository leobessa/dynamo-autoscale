# DynamoDB Autoscaling

Welcome to the delightful mini-game that is DynamoDB provisioned throughputs.
Here are the rules of the game:

  - In a single API call, you can only change your threshold by up to 100% in
  	either direction. In other words, you can decrease as much as you want but
  	you can only increase to up to double what the current threshold is.

  - You may scale up as many times per day as you like, however you may only
  	scale down 4 times per day per metric (citation needed).

  - Scaling is not an instantaneous event.

  - Small spikes over your threshold are tolerated but the exact amount of time
  	they are tolerated for varies.

# Usage



# Technical details

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

  - `DynamoAutoscale.actioner`: The actioner is what performs provision scaling.
  	Locally this is faked, in production it makes API calls to DynamoDB.

  - `DynamoAutoscale.tables`: This is a hash table of `TableTracker` objects,
  	keyed on the table name.

All of these components are globally available because most of them need access
to each other and it was a pain to pass instances of them around to everybody
that needed them.

They're also completely swappable. As long as they implement the right methods
you can get your data from anywhere, dispatch your data to anywhere and send
your actions to whatever you want. The defaults all work on local data.
