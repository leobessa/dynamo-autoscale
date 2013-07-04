module DynamoAutoscale
  class StandardFormatter
    def initialize
      @formatter = ::Logger::Formatter.new
    end

    def call(severity, time, progname, msg)
      table = DynamoAutoscale.current_table
      msg   = "[#{table.name}] #{msg}" if table

      @formatter.call(severity, time, progname, msg)
    end
  end
end
