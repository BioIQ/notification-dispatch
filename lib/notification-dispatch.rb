require "notification-dispatch/version"

module Notification
  module Dispatch

    class Client
      attr_reader :key_map, :clients, :msg_classes

      KEY_MAPS = {
        :aws => {:access_key => 'AWS_ACCESS_KEY', :secret_key => 'AWS_SECRET_KEY'},
        :datadog => {:api_key => 'DATADOG_API_KEY'}
      }

      def initialize
        @key_map     = {}
        @msg_classes = {}
        @clients     = lambda { return get_active_clients }
      end

      def is_active?
        @key_map.values.empty? ? false : @key_map.values.all? {|key| !ENV[key].nil? && !ENV[key].empty?}
      end

      def clients
        @clients.call
      end

      def has_active_clients?
        !clients.empty?
      end

      def handle_message?(msg_class, msg_type)
        @msg_classes.has_key?(msg_class) && @msg_classes[msg_class].include?(msg_type)
      end

      def message(msg_class, msg_type, subject, msg, opts={})
        clients.each { |client| client.message(msg_class, msg_type, subject, msg, opts) unless(!client.handle_message?(msg_class, msg_type)) }
      end

      private

      # Iterate over keys in client_key_map and return array of active clients
      def get_active_clients
        KEY_MAPS.each_key.inject([]) do |res, client|
          client_class = Notification::Dispatch.const_get(client.capitalize).new
          client_class.is_active? ? res.push(client_class) : res
        end
      end

    end

    class Aws < Client
      def initialize
        @key_map = self.class::KEY_MAPS[:aws]
      end
    end

    class Datadog < Client
      attr_reader :conn, :key

      def initialize
        @key_map     = self.class::KEY_MAPS[:datadog]
        @key         = ENV[@key_map[:api_key]]
        @msg_classes = {:event => [:error, :warning, :info, :success]}
        @conn        = self.is_active? ? connect : nil
      end

      def connect
        require 'dogapi'
        Dogapi::Client.new(key)
      end

      def message(msg_class, msg_type, subject, msg, opts={})
        raise "Datadog: unsupported msg_class and/or msg_type" unless(handle_message(msg_class, msg_type))
        options = {:source => 'my apps', :tags => []}
        options.merge!(opts)
        @conn.emit_event(Dogapi::Event.new(
          msg,
          :msg_title        => subject,
          :tags             => options[:tags], 
          :alert_type       => msg_type.to_s,
          :source_type_name => options[:source]))
      end
    end

  end
end