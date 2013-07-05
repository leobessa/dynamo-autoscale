module DynamoAutoscale
  class ScaleReport
    include DynamoAutoscale::Logger

    TEMPLATE = File.join(DynamoAutoscale.root, 'templates', 'scale_report_email.erb')

    def initialize table
      @table = table
      @erb = ERB.new(File.read(TEMPLATE))

      if config = DynamoAutoscale.config[:email]
        @enabled = true
        Pony.options = config
      else
        @enabled = false
      end
    end

    def email_content
      @erb.result(binding)
    end

    def send
      return false unless @enabled

      result = Pony.mail({
        subject: "Scale event for #{@table.name}",
        body:    email_content,
      })

      if result
        logger.info "[mailer] Mail sent successfully."
        result
      else
        logger.error "[mailer] Failed to send email. Result: #{result.inspect}"
        false
      end
    rescue => e
      logger.error "[mailer] Encountered an error: #{e.class}:#{e.message}"
      false
    end
  end
end
