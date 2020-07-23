require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/ext/http'
require 'ddtrace/contrib/grape/ext'

module Datadog
  module Contrib
    module Grape
      module Configuration
        # Custom settings for the Grape integration
        class Settings < Contrib::Configuration::Settings
          option :analytics_enabled do |o|
            o.default { env_to_bool([Ext::ENV_ANALYTICS_ENABLED, Ext::ENV_ANALYTICS_ENABLED_OLD], nil) }
            o.lazy
          end

          option :analytics_sample_rate do |o|
            o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
            o.lazy
          end

          option :enabled, default: true
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
