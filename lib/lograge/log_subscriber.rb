require 'active_support/core_ext/class/attribute'
require 'active_support/log_subscriber'

module Lograge
  class RequestLogSubscriber < ActiveSupport::LogSubscriber
    def process_action(event)
      begin
        payload = event.payload
        return if payload[:headers]['X-StatusPage-Skip-Logging'] == 'true'

        message = ["#{payload[:remote_ip]} #{payload[:method]} #{payload[:host]}:#{payload[:port]}#{payload[:path].split('?').first} format=#{extract_format(payload)} action=#{payload[:params]['controller']}##{payload[:params]['action']}"]
        message << hash_to_string(extract_status(payload))
        message << hash_to_string(runtimes(event))
        message << hash_to_string(location(event))
        message << hash_to_string(custom_options(event))
        message << user_params(payload)
        logger.warn(message.join(' '))
      rescue Exception => e
        Utils.log_and_puts e.message
        Utils.log_and_puts e.backtrace.join "\n"
      end
    end

    def redirect_to(event)
      Thread.current[:lograge_location] = event.payload[:location]
    end

    private

    def extract_request(payload)
      {
        :method => payload[:method],
        :path => extract_path(payload),
        :format => extract_format(payload),
        :controller => payload[:params]['controller'],
        :action => payload[:params]['action']
      }
    end

    def extract_path(payload)
      payload[:path].split("?").first
    end

    def extract_format(payload)
      if ::ActionPack::VERSION::MAJOR == 3 && ::ActionPack::VERSION::MINOR == 0
        payload[:formats].first
      else
        payload[:format]
      end
    end

    def extract_status(payload)
      if payload[:status]
        { :status => payload[:status].to_i }
      elsif payload[:exception]
        exception, message = payload[:exception]
        { :status => 500, :error => "#{exception}:#{message}" }
      else
        { :status => 0 }
      end
    end

    def custom_options(event)
      Lograge.custom_options(event) || {}
    end

    def user_params(payload)
      payload[:params].reject{|k, v| ['controller','action','subdomain'].include?(k)}.inspect
    end

    def runtimes(event)
      {
        :duration => event.duration,
        :view => event.payload[:view_runtime],
        :db => event.payload[:db_runtime]
      }.inject({}) do |runtimes, (name, runtime)|
        runtimes[name] = runtime.to_f.round(2) if runtime
        runtimes
      end
    end

    def location(event)
      if location = Thread.current[:lograge_location]
        Thread.current[:lograge_location] = nil
        { :location => location }
      else
        {}
      end
    end

    def hash_to_string(h)
      h.collect{|k, v| "#{k}=#{v}"}.join(' ')
    end
  end
end
