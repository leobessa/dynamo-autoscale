Signal.trap("USR1") do
  DynamoAutoscale.logger.info "[signal] Caught SIGUSR1. Dumping CSV for all tables in #{Dir.pwd}"

  DynamoAutoscale.tables.each do |name, table|
    table.to_csv! path: File.join(Dir.pwd, "#{table.name}.csv")
  end
end

Signal.trap("USR2") do
  DynamoAutoscale.logger.info "[signal] Caught SIGUSR2. Dumping graphs for all tables in #{Dir.pwd}"

  DynamoAutoscale.tables.each do |name, table|
    table.graph! path: File.join(Dir.pwd, "#{table.name}.png")
  end
end
