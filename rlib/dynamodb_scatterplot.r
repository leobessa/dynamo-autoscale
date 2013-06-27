require(ggplot2)
require(reshape)
args <- commandArgs(trailingOnly = TRUE)
data = read.csv(args[1], header=T, sep=",")

data$time = strptime(data$time, "%Y-%m-%dT%H:%M:%SZ")
data$hour = as.factor(strftime(data$time, "%H"))
measure.vars = c(args[3])

ive.melted = melt(data, id.vars='hour', measure.vars = measure.vars)
g = ggplot(ive.melted, aes(x=hour, y=value, color=variable)) + geom_point()

ggsave(file=args[2], plot=g, width=10, height=8)
