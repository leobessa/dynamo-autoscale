require(ggplot2)
require(reshape)
args <- commandArgs(trailingOnly = TRUE)
data = read.csv(args[1], header=T, sep=",")

data$time = strptime(data$time, "%Y-%m-%dT%H:%M:%SZ")

measure.vars = c('provisioned_reads','provisioned_writes',
                 'consumed_reads','consumed_writes')

ive.melted = melt(data, id.vars='time', measure.vars = measure.vars)

g = ggplot(ive.melted, aes(x=time, y=value, color=variable)) + geom_line()

ggsave(file=args[2], plot=g, width=20, height=8)
