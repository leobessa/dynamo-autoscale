module DynamoAutoscale
  class ScaleReport
    include DynamoAutoscale::Logger

    TEMPLATE = File.join(DynamoAutoscale.root, 'templates', 'scale_report_email.erb')

    def initialize table
      @table = table
      @erb = ERB.new(File.read(TEMPLATE), nil, '-')

      if DynamoAutoscale.config[:dry_run]
        @enabled = false
      elsif config = DynamoAutoscale.config[:email]
        @enabled = true
        Pony.options = config
      else
        @enabled = false
      end
    end

    def email_subject
      "Scale event for #{@table.name}"
    end

    def email_content
      @erb.result(binding)
    end

    def send
      return false unless @enabled

      result = Pony.mail({
        subject: email_subject,
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

    def formatted_scale_event(scale_event)
      max_length = max_metric_length(scale_event)
      ['reads', 'writes'].map do |type|
        type_from = scale_event["#{type}_from".to_sym].to_s.rjust(max_length)
        type_to   = scale_event["#{type}_to".to_sym].to_s.rjust(max_length)

        "#{type.capitalize.rjust(6)}: #{scale_direction(type_from, type_to)} from #{type_from} to #{type_to}"
      end
    end

    def max_metric_length(scale_event)
      scale_event.values.max.to_s.length
    end

    def scale_direction(from, to)
      from > to ? 'DOWN' : ' UP '
    end
  end
end
