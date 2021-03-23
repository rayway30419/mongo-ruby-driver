module Mongo
  module CRUD
    class Requirement
      YAML_KEYS = %w(minServerVersion maxServerVersion topology topologies serverParameters).freeze

      def initialize(spec)
        spec = spec.dup
        # Legacy tests have the requirements mixed with other test fields
        spec.delete('data')
        spec.delete('tests')

        unless (unhandled_keys = spec.keys - YAML_KEYS).empty?
          raise "Unhandled requirement specification keys: #{unhandled_keys}"
        end

        @min_server_version = spec['minServerVersion']
        @max_server_version = spec['maxServerVersion']
        # topologies is for unified test format.
        # topology is for legacy tests.
        @topologies = if topologies = spec['topology'] || spec['topologies']
          topologies.map do |topology|
            {
              'replicaset' => :replica_set,
              'single' => :single,
              'sharded' => :sharded,
              'sharded-replicaset' => :sharded,
            }[topology].tap do |v|
              unless v
                raise "Unknown topology #{topology}"
              end
            end
          end
        else
          nil
        end
        @server_parameters = spec['serverParameters']
      end

      attr_reader :min_server_version
      attr_reader :max_server_version
      attr_reader :topologies

      def short_min_server_version
        if min_server_version
          min_server_version.split('.')[0..1].join('.')
        else
          nil
        end
      end

      def short_max_server_version
        if max_server_version
          max_server_version.split('.')[0..1].join('.')
        else
          nil
        end
      end

      def satisfied?
        cc = ClusterConfig.instance
        ok = true
        if short_min_server_version
          ok &&= cc.fcv_ish >= short_min_server_version
        end
        if max_server_version
          ok &&= cc.short_server_version <= max_server_version
        end
        if topologies
          ok &&= topologies.include?(cc.topology)
        end
        if @server_parameters
          @server_parameters.each do |k, required_v|
            actual_v = cc.server_parameters[k]
            if actual_v.nil? && !required_v.nil?
              ok = false
            elsif actual_v != required_v
              if Numeric === actual_v && Numeric === required_v
                if actual_v.to_f != required_v.to_f
                  ok = false
                end
              else
                ok = false
              end
            end
          end
        end
        ok
      end

      def description
        versions = [min_server_version, max_server_version].compact
        if versions.any?
          versions = versions.join('-')
        else
          versions = nil
        end
        topologies = if self.topologies
          self.topologies.map(&:to_s).join(',')
        else
          nil
        end
        [versions, topologies].compact.join('/')
      end
    end
  end
end
