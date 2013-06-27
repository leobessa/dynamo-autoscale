module DynamoAutoscale
  module Logger
    def self.logger= new_logger
      @@logger = new_logger
    end

    def self.logger
      @@logger
    end

    def logger
      DynamoAutoscale::Logger.logger
    end
  end
end
